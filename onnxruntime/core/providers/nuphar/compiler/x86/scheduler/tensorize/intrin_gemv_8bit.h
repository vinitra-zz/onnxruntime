// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#pragma once
#include "tensorize_base.h"

namespace onnxruntime {
namespace nuphar {

class Gemv8bitTensorization : public tvm_codegen::TensorizeBase {
 public:
  Gemv8bitTensorization(const std::string& name, const std::vector<int32_t>& vshape);

  virtual ~Gemv8bitTensorization() = default;

  tvm::TensorIntrin CreateTensorIntrin() override;
};

}  // namespace nuphar
}  // namespace onnxruntime
