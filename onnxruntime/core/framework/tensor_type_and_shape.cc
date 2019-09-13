// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#include "core/session/onnxruntime_c_api.h"
#include "core/framework/tensor_shape.h"
#include "core/framework/ml_value.h"
#include "core/framework/onnxruntime_typeinfo.h"
#include "core/framework/sparse_tensor.h"
#include "core/framework/tensor_type_and_shape.h"
#include "core/graph/onnx_protobuf.h"

#include <assert.h>
#include <stdexcept>
#include <atomic>

using onnxruntime::BFloat16;
using onnxruntime::DataTypeImpl;
using onnxruntime::MLFloat16;
using onnxruntime::Tensor;
using onnxruntime::SparseTensor;

#define API_IMPL_BEGIN try {
#define API_IMPL_END                                          \
  }                                                           \
  catch (std::exception & ex) {                               \
    return OrtCreateStatus(ORT_RUNTIME_EXCEPTION, ex.what()); \
  }

ORT_API_STATUS_IMPL(OrtCreateTensorTypeAndShapeInfo, _Out_ OrtTensorTypeAndShapeInfo** out) {
  API_IMPL_BEGIN
  *out = new OrtTensorTypeAndShapeInfo();
  return nullptr;
  API_IMPL_END
}

ORT_API(void, OrtReleaseTensorTypeAndShapeInfo, _Frees_ptr_opt_ OrtTensorTypeAndShapeInfo* ptr) {
  delete ptr;
}

ORT_API_STATUS_IMPL(OrtSetTensorElementType, _In_ OrtTensorTypeAndShapeInfo* this_ptr, enum ONNXTensorElementDataType type) {
  API_IMPL_BEGIN
  this_ptr->type = type;
  return nullptr;
  API_IMPL_END
}

ORT_API_STATUS_IMPL(OrtSetDimensions, OrtTensorTypeAndShapeInfo* this_ptr, _In_ const int64_t* dim_values, size_t dim_count) {
  API_IMPL_BEGIN
  this_ptr->shape = onnxruntime::TensorShape(dim_values, dim_count);
  return nullptr;
  API_IMPL_END
}

ORT_API_STATUS_IMPL(OrtGetTensorElementType, _In_ const struct OrtTensorTypeAndShapeInfo* info, _Out_ ONNXTensorElementDataType* out) {
  *out = info->type;
  return nullptr;
}

ORT_API_STATUS_IMPL(OrtGetDimensionsCount, _In_ const struct OrtTensorTypeAndShapeInfo* info, _Out_ size_t* out) {
  *out = info->shape.NumDimensions();
  return nullptr;
}

ORT_API_STATUS_IMPL(OrtGetDimensions, _In_ const struct OrtTensorTypeAndShapeInfo* info, _Out_ int64_t* dim_values, size_t dim_values_length) {
  info->shape.CopyDims(dim_values, dim_values_length);
  return nullptr;
}

ORT_API_STATUS_IMPL(OrtGetTensorShapeElementCount, _In_ const OrtTensorTypeAndShapeInfo* this_ptr, _Out_ size_t* out) {
  *out = static_cast<size_t>(this_ptr->shape.Size());
  return nullptr;
}

struct OrtValue;

ONNXTensorElementDataType MLDataTypeToOnnxRuntimeTensorElementDataType(
    const onnxruntime::DataTypeImpl* cpp_type) {
  ONNXTensorElementDataType type;
  if (cpp_type == onnxruntime::DataTypeImpl::GetType<float>()) {
    type = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
  } else if (cpp_type == onnxruntime::DataTypeImpl::GetType<uint8_t>()) {
    type = ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8;
  } else if (cpp_type == onnxruntime::DataTypeImpl::GetType<int8_t>()) {
    type = ONNX_TENSOR_ELEMENT_DATA_TYPE_INT8;
  } else if (cpp_type == onnxruntime::DataTypeImpl::GetType<uint16_t>()) {
    type = ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16;
  } else if (cpp_type == onnxruntime::DataTypeImpl::GetType<int16_t>()) {
    type = ONNX_TENSOR_ELEMENT_DATA_TYPE_INT16;
  } else if (cpp_type == onnxruntime::DataTypeImpl::GetType<int32_t>()) {
    type = ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32;
  } else if (cpp_type == onnxruntime::DataTypeImpl::GetType<int64_t>()) {
    type = ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64;
  } else if (cpp_type == onnxruntime::DataTypeImpl::GetType<std::string>()) {
    type = ONNX_TENSOR_ELEMENT_DATA_TYPE_STRING;
  } else if (cpp_type == onnxruntime::DataTypeImpl::GetType<bool>()) {
    type = ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL;
  } else if (cpp_type == onnxruntime::DataTypeImpl::GetType<MLFloat16>()) {
    type = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16;
  } else if (cpp_type == onnxruntime::DataTypeImpl::GetType<BFloat16>()) {
    type = ONNX_TENSOR_ELEMENT_DATA_TYPE_BFLOAT16;
  } else if (cpp_type == onnxruntime::DataTypeImpl::GetType<double>()) {
    type = ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE;
  } else if (cpp_type == onnxruntime::DataTypeImpl::GetType<uint32_t>()) {
    type = ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT32;
  } else if (cpp_type == onnxruntime::DataTypeImpl::GetType<uint64_t>()) {
    type = ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT64;
  } else {
    type = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED;
  }
  return type;
}

ONNXTensorElementDataType TensorDataTypeToOnnxRuntimeTensorElementDataType(
    int32_t dtype) {
  namespace o = ONNX_NAMESPACE;
  ONNXTensorElementDataType type;
  switch (dtype) {
    case o::TensorProto_DataType_FLOAT:
      type = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
      break;
    case o::TensorProto_DataType_DOUBLE:
      type = ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE;
      break;
    case o::TensorProto_DataType_FLOAT16:
      type = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16;
      break;
    case o::TensorProto_DataType_BFLOAT16:
      type = ONNX_TENSOR_ELEMENT_DATA_TYPE_BFLOAT16;
      break;
    case o::TensorProto_DataType_INT8:
      type = ONNX_TENSOR_ELEMENT_DATA_TYPE_INT8;
      break;
    case o::TensorProto_DataType_UINT8:
      type = ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8;
      break;
    case o::TensorProto_DataType_INT16:
      type = ONNX_TENSOR_ELEMENT_DATA_TYPE_INT16;
      break;
    case o::TensorProto_DataType_UINT16:
      type = ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16;
      break;
    case o::TensorProto_DataType_INT32:
      type = ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32;
      break;
    case o::TensorProto_DataType_UINT32:
      type = ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT32;
      break;
    case o::TensorProto_DataType_INT64:
      type = ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64;
      break;
    case o::TensorProto_DataType_UINT64:
      type = ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT64;
      break;
    case o::TensorProto_DataType_STRING:
      type = ONNX_TENSOR_ELEMENT_DATA_TYPE_STRING;
      break;
    case o::TensorProto_DataType_BOOL:
      type = ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL;
      break;
    default:
      type = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED;
      break;
  }
  return type;
}

OrtStatus* GetTensorShapeAndTypeHelper(ONNXTensorElementDataType type, const onnxruntime::TensorShape* shape, OrtTensorTypeAndShapeInfo** out) {
  OrtTensorTypeAndShapeInfo* ret;
  if (auto* status = OrtCreateTensorTypeAndShapeInfo(&ret))
    return status;
  if (auto* status = OrtSetTensorElementType(ret, type)) {
    OrtReleaseTensorTypeAndShapeInfo(ret);
    return status;
  }
  if (shape != nullptr) {
    auto* status = OrtSetDimensions(ret, shape->GetDims().data(), shape->GetDims().size());
    if (status != nullptr) {
      OrtReleaseTensorTypeAndShapeInfo(ret);
      return status;
    }
  }
  *out = ret;
  return nullptr;
}

OrtStatus* GetTensorShapeAndType(const onnxruntime::TensorShape* shape,
                                 const onnxruntime::DataTypeImpl* tensor_data_type, OrtTensorTypeAndShapeInfo** out) {
  ONNXTensorElementDataType type = MLDataTypeToOnnxRuntimeTensorElementDataType(tensor_data_type);
  if (ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED == type) {
    return OrtCreateStatus(ORT_NOT_IMPLEMENTED, "Not implemented");
  }
  return GetTensorShapeAndTypeHelper(type, shape, out);
}

OrtStatus* GetTensorShapeAndType(const onnxruntime::TensorShape* shape,
                                 const ONNX_NAMESPACE::TypeProto* type_proto, OrtTensorTypeAndShapeInfo** out) {
  assert(type_proto != nullptr);
  auto value_case = type_proto->value_case();
  assert(value_case == ONNX_NAMESPACE::TypeProto::kTensorType || value_case == ONNX_NAMESPACE::TypeProto::kSparseTensorType);
  auto dtype = (value_case == ONNX_NAMESPACE::TypeProto::kTensorType) ? 
    type_proto->tensor_type().elem_type() : type_proto->sparse_tensor_type().elem_type();
  ONNXTensorElementDataType type = TensorDataTypeToOnnxRuntimeTensorElementDataType(dtype);
  if (ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED == type) {
    return OrtCreateStatus(ORT_NOT_IMPLEMENTED, "Not implemented");
  }
  return GetTensorShapeAndTypeHelper(type, shape, out);
}

ORT_API_STATUS_IMPL(OrtGetTensorTypeAndShape, _In_ const OrtValue* v,
                    _Out_ OrtTensorTypeAndShapeInfo** out) {
  API_IMPL_BEGIN
  onnxruntime::MLDataType type = v->Type();
  ORT_ENFORCE(type != nullptr, "OrtValue is not a Tensor");
  if (type->IsTensorType() || type->IsSparseTensorType()) {
    const onnxruntime::TensorShape* shape = nullptr;
    onnxruntime::MLDataType data_type = nullptr;
    if (type->IsTensorType()) {
      const Tensor& tensor = v->Get<onnxruntime::Tensor>();
      shape = &tensor.Shape();
      data_type = tensor.DataType();
    } else {
      const SparseTensor& tensor = v->Get<onnxruntime::SparseTensor>();
      shape = &tensor.Shape();
      data_type = tensor.Values().DataType();
    }
    return GetTensorShapeAndType(shape, data_type, out);
  } else {
    ORT_THROW("Argument is not a tensor");
  }
  API_IMPL_END
}

ORT_API_STATUS_IMPL(OrtGetValueType, _In_ const OrtValue* v, _Out_ ONNXType* out) {
  API_IMPL_BEGIN
  onnxruntime::MLDataType type = v->Type();
  OrtTypeInfo* type_info;
  if (auto status = OrtTypeInfo::FromDataTypeImpl(type, nullptr, nullptr, &type_info))
    return status;
  *out = type_info->type;
  OrtReleaseTypeInfo(type_info);
  return nullptr;
  API_IMPL_END
}

/**
 * Get the type information of an OrtValue
 * \param value
 * \return The returned value should be freed by OrtReleaseTypeInfo after use
 */
ORT_API_STATUS_IMPL(OrtGetTypeInfo, _In_ const OrtValue* v, struct OrtTypeInfo** out) {
  onnxruntime::MLDataType type = v->Type();
  if (type == nullptr) {
    *out = nullptr;
    return nullptr;
  }
  if (type->IsTensorType() || type->IsSparseTensorType()) {
    const onnxruntime::TensorShape* shape = nullptr;
    onnxruntime::MLDataType data_type = nullptr;
    if (type->IsTensorType()) {
      const Tensor& tensor = v->Get<onnxruntime::Tensor>();
      shape = &tensor.Shape();
      data_type = tensor.DataType();
    } else {
      const SparseTensor& tensor = v->Get<onnxruntime::SparseTensor>();
      shape = &tensor.Shape();
      data_type = tensor.Values().DataType();
    }
    return OrtTypeInfo::FromDataTypeImpl(type, shape, data_type, out);
  }
  return OrtTypeInfo::FromDataTypeImpl(type, nullptr, nullptr, out);
}
