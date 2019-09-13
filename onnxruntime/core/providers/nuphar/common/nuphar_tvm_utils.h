// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#pragma once
#include <tvm/tvm.h>
#include <string>

#include "core/graph/graph.h"

namespace onnxruntime {
class CodeGenTarget;  //forward

namespace nuphar {

struct NupharSubgraphUnit;  //forward
// Helper functions to create or load from offline cached dll
// note after saving to obj file, we need to use tvm Python to create dll
// using script at onnxruntime/core/codegen/mti/scripts/create_shared.py
tvm::runtime::PackedFunc
LoadTVMPackedFuncFromCache(const std::string& func_name);
void SaveTVMModuleToCache(const std::string& filename, tvm::runtime::Module& module);

std::string GetPackedFuncName(const nuphar::NupharSubgraphUnit& subgraph, const CodeGenTarget& codegen_target);

}  // namespace nuphar
}  //  namespace onnxruntime
