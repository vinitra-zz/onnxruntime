// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#include "core/providers/nuphar/mti_x86/math/matmul_ops.h"

#include "core/codegen/common/profile.h"
#include "core/codegen/mti/math/matmul_ops.h"
#include "core/providers/cpu/math/matmul_helper.h"
#include "core/providers/nuphar/common/nuphar_settings.h"
#include "core/codegen/mti/math/matmul_ops.h"
#include "core/codegen/mti/mti_tvm_utils.h"
#include "core/util/math.h"
#include "core/util/math_cpuonly.h"
#include <topi/detail/extern.h>
#include <topi/transform.h>

namespace onnxruntime {
namespace nuphar {

tvm::Tensor MatMul2D(const tvm::Tensor& A, const tvm::Tensor& B, bool trans_a, bool trans_b, const std::string& name) {
  tvm::Tensor Y;
  if (MatMulExternCpu(A, B, Y, trans_a, trans_b))
    return Y;

  return topi::matmul(A, B, trans_a, trans_b, name);
}

TVM_REGISTER_GLOBAL("tvm.contrib.onnxruntime.sgemm_cpu")
    .set_body([](tvm::TVMArgs args, tvm::TVMRetValue* /*ret*/) {
      CODEGEN_PROFILER_EVENT("math_sgemm");
      // Explicitly construct TVMArgValue instead of calling operator[] on args for saving some cycles.
      DLTensor* A = tvm::runtime::TVMArgValue(args.values[0], args.type_codes[0]);
      DLTensor* B = tvm::runtime::TVMArgValue(args.values[1], args.type_codes[1]);
      DLTensor* C = tvm::runtime::TVMArgValue(args.values[2], args.type_codes[2]);
      bool trans_a = tvm::runtime::TVMArgValue(args.values[3], args.type_codes[3]);
      bool trans_b = tvm::runtime::TVMArgValue(args.values[4], args.type_codes[4]);
      float alpha = 1.0f;
      float beta = 0.0f;

      DCHECK(C->strides == nullptr);
      DCHECK(B->strides == nullptr);
      DCHECK(A->strides == nullptr);
      DCHECK(tvm::runtime::TypeMatch(A->dtype, kDLFloat, 32));
      DCHECK(tvm::runtime::TypeMatch(B->dtype, kDLFloat, 32));
      DCHECK(tvm::runtime::TypeMatch(C->dtype, kDLFloat, 32));

      int64_t M, N, K;

      // compute default M by flatten A dims
      M = 1;
      for (int d = 0; d < A->ndim - 1; ++d)
        M *= A->shape[d];

      if (A->ndim == 1) {
        DCHECK(!trans_a);
        DCHECK_GT(B->ndim, 1);
        M = 1;
        N = B->shape[trans_b ? 0 : B->ndim - 1];
        K = A->shape[0];
      } else if (B->ndim == 1) {
        // N-D x 1-D
        DCHECK(!trans_a);
        DCHECK(!trans_b);
        DCHECK_GT(A->ndim, 1);
        N = 1;
        K = A->shape[A->ndim - 1];
      } else {
        // N-D x N-D
        DCHECK(!trans_a || A->ndim == 2);  // only allow trans_a for 2D
        if (trans_a) {
          M = A->shape[1];
          K = A->shape[0];
        } else {
          K = A->shape[A->ndim - 1];
        }

        // B is essentially 2D, allowing >2D here to reduce flatten at extern input
        N = B->shape[trans_b ? B->ndim - 2 : B->ndim - 1];
      }

      // for empty tensor, don't do anything
      if (M == 0 || N == 0 || K == 0)
        return;

      math::Gemm<float, concurrency::ThreadPool>(
          trans_a ? CblasTrans : CblasNoTrans,
          trans_b ? CblasTrans : CblasNoTrans,
          M,
          N,
          K,
          alpha,
          reinterpret_cast<float*>(static_cast<char*>(A->data) + A->byte_offset),
          reinterpret_cast<float*>(static_cast<char*>(B->data) + B->byte_offset),
          beta,
          reinterpret_cast<float*>(static_cast<char*>(C->data) + C->byte_offset),
          nullptr);
    });

TVM_REGISTER_GLOBAL("tvm.contrib.onnxruntime.batched_matmul_cpu")
    .set_body([](tvm::TVMArgs args, tvm::TVMRetValue* /*ret*/) {
      CODEGEN_PROFILER_EVENT("math_batched_sgemm");
      DLTensor* A = tvm::runtime::TVMArgValue(args.values[0], args.type_codes[0]);
      DLTensor* B = tvm::runtime::TVMArgValue(args.values[1], args.type_codes[1]);
      DLTensor* C = tvm::runtime::TVMArgValue(args.values[2], args.type_codes[2]);

      DCHECK(C->strides == nullptr);
      DCHECK(B->strides == nullptr);
      DCHECK(A->strides == nullptr);
      DCHECK(tvm::runtime::TypeMatch(A->dtype, kDLFloat, 32));
      DCHECK(tvm::runtime::TypeMatch(B->dtype, kDLFloat, 32));
      DCHECK(tvm::runtime::TypeMatch(C->dtype, kDLFloat, 32));

      MatMulComputeHelper helper;
      TensorShape A_shape(A->shape, A->ndim);
      TensorShape B_shape(B->shape, B->ndim);
      helper.Compute(A_shape, B_shape);

      size_t max_len = helper.OutputOffsets().size();
      for (size_t i = 0; i < max_len; i++) {
        math::MatMul<float>(
            static_cast<int>(helper.M()),
            static_cast<int>(helper.N()),
            static_cast<int>(helper.K()),
            (float*)A->data + helper.LeftOffsets()[i],
            (float*)B->data + helper.RightOffsets()[i],
            (float*)C->data + helper.OutputOffsets()[i],
            nullptr);  // TODO: use thread pool from OpContext
      }
    });

bool MatMulExternCpu(
    const tvm::Tensor& A,
    const tvm::Tensor& B,
    tvm::Tensor& Y,
    bool trans_a,
    bool trans_b,
    const std::string& name) {
  // Note: currently default behavior is always prefer extern
  const codegen::CodeGenSettings& settings = codegen::CodeGenSettings::Instance();
  if (settings.HasOption(kNupharMatmulExec)) {
    bool prefer_extern = settings.OptionMatches(
        kNupharMatmulExec,
        kNupharMatMulExec_ExternCpu);
    if (!prefer_extern)
      return false;
  }

  // TODO: add support for mixed precisions
  if (A->dtype != B->dtype ||
      !A->dtype.is_float() ||
      A->dtype.bits() != 32)
    return false;

  // inputs need to be at least 1D
  auto rank_A = A->shape.size();
  auto rank_B = B->shape.size();
  if (rank_A < 1 || rank_B < 1)
    return false;

  // only allow trans_a for 2D inputs
  if (rank_A != 2 && trans_a)
    return false;

  // do not support 1-D x 1-D as tvm extern require buffer size > 0
  if (rank_A == 1 && rank_B == 1)
    return false;

  tvm::Array<tvm::Expr> out_shape;
  if (rank_A == 1) {
    // 1-D x N-D
    if (trans_b) {
      ORT_ENFORCE(rank_B == 2);
      out_shape.push_back(B->shape[0]);
    } else {
      for (size_t d = 0; d < rank_B - 2; ++d)
        out_shape.push_back(B->shape[d]);
      out_shape.push_back(B->shape[rank_B - 1]);
    }
  } else if (rank_B == 1) {
    // N-D x 1-D
    for (size_t d = 0; d < rank_A - 1; ++d)
      out_shape.push_back(A->shape[d]);
  } else {
    // N-D x N-D
    if (rank_B == 2) {
      if (trans_a) {
        // trans_a is only allowed for 2D
        out_shape.push_back(A->shape[rank_A - 1]);
      } else {
        for (size_t d = 0; d < rank_A - 1; ++d)
          out_shape.push_back(A->shape[d]);
      }
      out_shape.push_back(B->shape[trans_b ? rank_B - 2 : rank_B - 1]);
    } else {
      ORT_ENFORCE(!trans_a && !trans_b);
      // batched matmul
      out_shape = tvm_codegen::ComputeMatMulShape(A->shape, B->shape);
    }
  }

  Y = topi::detail::make_extern(
      {out_shape}, {A->dtype}, {A, B},
      [&](tvm::Array<tvm::Buffer> ins, tvm::Array<tvm::Buffer> outs) {
        if (rank_B <= 2) {
          return topi::detail::call_packed({tvm::Expr("tvm.contrib.onnxruntime.sgemm_cpu"),
                                            topi::detail::pack_buffer(ins[0]),
                                            topi::detail::pack_buffer(ins[1]),
                                            topi::detail::pack_buffer(outs[0]),
                                            trans_a,
                                            trans_b});
        } else {
          return topi::detail::call_packed({tvm::Expr("tvm.contrib.onnxruntime.batched_matmul_cpu"),
                                            topi::detail::pack_buffer(ins[0]),
                                            topi::detail::pack_buffer(ins[1]),
                                            topi::detail::pack_buffer(outs[0])});
        }
      },
      name, "", {})[0];

  return true;
}

tvm::Tensor MatMul(const tvm::Tensor& A, const tvm::Tensor& B, const std::string& name) {
  tvm::Tensor Y;
  if (MatMulExternCpu(A, B, Y))
    return Y;
  // go through generic case otherwise
  return tvm_codegen::MatMul(A, B, name);
}

}  // namespace nuphar
}  // namespace onnxruntime
