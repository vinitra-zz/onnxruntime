/**
* Copyright (c) 2016-present, Facebook, Inc.
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/
/* Modifications Copyright (c) Microsoft. */
#include "core/framework/op_kernel_context_internal.h"

#include "core/providers/cpu/nn/conv.h"
#include "core/framework/op_kernel_context_internal.h"
#include "core/util/math_cpuonly.h"

namespace onnxruntime {

template <typename T>
Status Conv<T>::Compute(OpKernelContext* context) const {
  size_t num_inputs = OpKernel::Node().InputDefs().size();
  auto ctx_internal = static_cast<OpKernelContextInternal*>(context);
  concurrency::ThreadPool* tp = ctx_internal->GetOperatorThreadPool();

  const auto* X = context->Input<Tensor>(0);
  const auto* W = context->Input<Tensor>(1);
  const Tensor* B = num_inputs == 3 ? context->Input<Tensor>(2) : nullptr;
  const int64_t N = X->Shape()[0];
  const int64_t C = X->Shape()[1];
  const int64_t M = W->Shape()[0];
  ORT_RETURN_IF_ERROR(ValidateInputShape(X, W));

  std::vector<int64_t> kernel_shape;
  ORT_RETURN_IF_ERROR(ComputeKernelShape(W->Shape(), kernel_shape));

  bool Is2DKernel = kernel_shape.size() == 2;
  std::vector<int64_t> pads(pads_);
  if (pads.empty()) {
    pads.resize(kernel_shape.size() * 2, 0);
  }
  std::vector<int64_t> dilations(dilations_);
  if (dilations.empty()) {
    dilations.resize(kernel_shape.size(), 1);
  }
  std::vector<int64_t> strides(strides_);
  if (strides.empty()) {
    strides.resize(kernel_shape.size(), 1);
  }

  std::vector<int64_t> Y_dims;
  Y_dims.insert(Y_dims.begin(), {N, M});
  TensorShape input_shape = X->Shape().Slice(2);
  ORT_RETURN_IF_ERROR(InferOutputShape(input_shape, kernel_shape, strides, dilations, &pads, &Y_dims));
  Tensor* Y = context->Output(0, TensorShape(Y_dims));
  TensorShape output_shape = Y->Shape().Slice(2);

  const int64_t input_image_size = input_shape.Size();
  const int64_t output_image_size = output_shape.Size();
  const int64_t kernel_size = TensorShape(kernel_shape).Size();
  const int64_t X_offset = C / group_ * input_image_size;
  const int64_t Y_offset = Y->Shape().Size() / Y->Shape()[0] / group_;
  const int64_t W_offset = W->Shape().Size() / group_;
  const int64_t kernel_dim = C / group_ * kernel_size;
  const int64_t col_buffer_size = kernel_dim * output_image_size;

  AllocatorPtr alloc;
  ORT_RETURN_IF_ERROR(context->GetTempSpaceAllocator(&alloc));

  auto col_data = alloc->Alloc(sizeof(T) * col_buffer_size);
  BufferUniquePtr col_buffer(col_data, BufferDeleter(alloc));
  T* col_buffer_data = static_cast<T*>(col_buffer.get());

  const T* Xdata = X->template Data<T>();
  T* Ydata = Y->template MutableData<T>();

  TensorShape image_shape = X->Shape().Slice(1);
  std::vector<int64_t> col_buffer_shape{kernel_dim};
  col_buffer_shape.insert(col_buffer_shape.end(), output_shape.GetDims().begin(),
                          output_shape.GetDims().end());

  for (int image_id = 0; image_id < N; ++image_id) {
    for (int group_id = 0; group_id < group_; ++group_id) {
      if (Is2DKernel) {
        math::Im2col<T, CPUMathUtil, StorageOrder::NCHW>(
            Xdata + group_id * X_offset,
            C / group_,
            input_shape[0],
            input_shape[1],
            kernel_shape[0],
            kernel_shape[1],
            dilations[0],
            dilations[1],
            pads[0],
            pads[1],
            pads[2],
            pads[3],
            strides[0],
            strides[1],
            col_buffer_data,
            &CPUMathUtil::Instance());
      } else {
        math::Im2colNd<T, CPUMathUtil, StorageOrder::NCHW>()(
            Xdata + group_id * X_offset,
            image_shape.GetDims().data(),
            col_buffer_shape.data(),
            C * input_image_size,
            col_buffer_size,
            kernel_shape.data(),
            strides.data(),
            dilations.data(),
            pads.data(),
            static_cast<int>(kernel_shape.size()),
            col_buffer_data,
            &CPUMathUtil::Instance());
      }
      math::Gemm<T>(
          CblasNoTrans,
          CblasNoTrans,
          M / group_,
          output_image_size,
          kernel_dim,
          1,
          W->template Data<T>() + group_id * W_offset,
          col_buffer_data,
          0,
          Ydata + group_id * Y_offset,
          tp);
    }

    if (B != nullptr) {
      auto Ymatrix = EigenMatrixMap<T>(Ydata, output_image_size, M);
      auto Bvec = ConstEigenVectorMap<T>(B->template Data<T>(), M);
      Ymatrix.rowwise() += Bvec.transpose();
    }

    Xdata += X_offset * group_;
    Ydata += Y_offset * group_;
  }

  return Status::OK();
}

Status Conv<float>::Compute(OpKernelContext* context) const {
  auto ctx_internal = static_cast<OpKernelContextInternal*>(context);
  concurrency::ThreadPool* tp = ctx_internal->GetOperatorThreadPool();

  size_t num_inputs = OpKernel::Node().InputDefs().size();
  const auto* X = context->Input<Tensor>(0);
  const auto* W = context->Input<Tensor>(1);
  const Tensor* B = num_inputs == 3 ? context->Input<Tensor>(2) : nullptr;
  const int64_t N = X->Shape()[0];
  const int64_t C = X->Shape()[1];
  const int64_t M = W->Shape()[0];
  ORT_RETURN_IF_ERROR(ValidateInputShape(X, W));

  std::vector<int64_t> kernel_shape;
  ORT_RETURN_IF_ERROR(ComputeKernelShape(W->Shape(), kernel_shape));

  std::vector<int64_t> pads(pads_);
  if (pads.empty()) {
    pads.resize(kernel_shape.size() * 2, 0);
  }
  std::vector<int64_t> dilations(dilations_);
  if (dilations.empty()) {
    dilations.resize(kernel_shape.size(), 1);
  }
  std::vector<int64_t> strides(strides_);
  if (strides.empty()) {
    strides.resize(kernel_shape.size(), 1);
  }

  std::vector<int64_t> Y_dims;
  Y_dims.insert(Y_dims.begin(), {N, M});
  TensorShape input_shape = X->Shape().Slice(2);
  ORT_RETURN_IF_ERROR(InferOutputShape(input_shape, kernel_shape, strides, dilations, &pads, &Y_dims));
  Tensor* Y = context->Output(0, TensorShape(Y_dims));
  TensorShape output_shape = Y->Shape().Slice(2);

  AllocatorPtr alloc;
  ORT_RETURN_IF_ERROR(context->GetTempSpaceAllocator(&alloc));

  const auto* Xdata = X->template Data<float>();
  const auto* Bdata = B != nullptr ? B->template Data<float>() : nullptr;
  auto* Ydata = Y->template MutableData<float>();

  const size_t kernel_rank = kernel_shape.size();

  if (kernel_rank == 2 || kernel_rank == 3) {
    MLAS_CONV_PARAMETERS Parameters;
    size_t WorkingBufferSize;
    MlasConvPrepare(&Parameters,
                    kernel_rank,
                    static_cast<size_t>(N),
                    static_cast<size_t>(group_),
                    static_cast<size_t>(C / group_),
                    input_shape.GetDims().data(),
                    kernel_shape.data(),
                    dilations.data(),
                    pads.data(),
                    strides.data(),
                    output_shape.GetDims().data(),
                    static_cast<size_t>(M / group_),
                    &activation_,
                    &WorkingBufferSize,
                    tp);

    auto working_data = WorkingBufferSize > 0 ? alloc->Alloc(sizeof(float) * WorkingBufferSize) : nullptr;
    BufferUniquePtr working_buffer(working_data, BufferDeleter(alloc));

    MlasConv(&Parameters,
             Xdata,
             W->template Data<float>(),
             Bdata,
             static_cast<float*>(working_buffer.get()),
             Ydata,
             tp);
  } else {
    const int64_t input_image_size = input_shape.Size();
    const int64_t output_image_size = output_shape.Size();
    const int64_t kernel_size = TensorShape(kernel_shape).Size();
    const int64_t X_offset = C / group_ * input_image_size;
    const int64_t Y_offset = Y->Shape().Size() / Y->Shape()[0] / group_;
    const int64_t W_offset = W->Shape().Size() / group_;
    const int64_t kernel_dim = C / group_ * kernel_size;
    const int64_t col_buffer_size = kernel_dim * output_image_size;

    auto col_data = alloc->Alloc(sizeof(float) * col_buffer_size);
    BufferUniquePtr col_buffer(col_data, BufferDeleter(alloc));
    auto* col_buffer_data = static_cast<float*>(col_buffer.get());

    TensorShape image_shape = X->Shape().Slice(1);
    std::vector<int64_t> col_buffer_shape{kernel_dim};
    col_buffer_shape.insert(col_buffer_shape.end(), output_shape.GetDims().begin(),
                            output_shape.GetDims().end());

    for (int image_id = 0; image_id < N; ++image_id) {
      for (int group_id = 0; group_id < group_; ++group_id) {
        math::Im2colNd<float, CPUMathUtil, StorageOrder::NCHW>()(
            Xdata + group_id * X_offset,
            image_shape.GetDims().data(),
            col_buffer_shape.data(),
            C * input_image_size,
            col_buffer_size,
            kernel_shape.data(),
            strides.data(),
            dilations.data(),
            pads.data(),
            static_cast<int>(kernel_shape.size()),
            col_buffer_data,
            &CPUMathUtil::Instance());
        math::Gemm<float>(
            CblasNoTrans,
            CblasNoTrans,
            M / group_,
            output_image_size,
            kernel_dim,
            1,
            W->template Data<float>() + group_id * W_offset,
            col_buffer_data,
            0,
            Ydata + group_id * Y_offset,
            tp);
      }

      MlasActivation(&activation_, Ydata, Bdata, M, output_image_size, output_image_size);

      Xdata += X_offset * group_;
      Ydata += Y_offset * group_;
    }
  }

  return Status::OK();
}

ONNX_CPU_OPERATOR_KERNEL(
    Conv,
    1,
    KernelDefBuilder().TypeConstraint("T", DataTypeImpl::GetTensorType<float>()),
    Conv<float>);

}  // namespace onnxruntime
