// Copyright(C) 2019 Intel Corporation
// Licensed under the MIT License

#pragma once

#if defined(_MSC_VER)
#pragma warning(disable : 4244 4245)
#elif __GNUC__
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-parameter"
#endif
#include <ngraph/ngraph.hpp>
#if defined(_MSC_VER)
#pragma warning(default : 4244 4245)
#elif __GNUC__
#pragma GCC diagnostic pop
#endif

#include "core/session/onnxruntime_c_api.h"
#include "core/framework/func_api.h"
#include "core/graph/onnx_protobuf.h"

namespace onnxruntime {
namespace ngraph_ep {

class NGRAPHCustomOp {
 public:
  NGRAPHCustomOp(const ComputeContext* context,
                 const ONNX_NAMESPACE::ModelProto& model_proto,
                 const std::shared_ptr<ngraph::runtime::Backend>& ng_backend);

  Status Compute(const OrtCustomOpApi* api, OrtKernelContext* context) const;

  ~NGRAPHCustomOp();

 private:
  void Initialize(const OrtCustomOpApi* api, OrtKernelContext* context) const;

  std::shared_ptr<ngraph::runtime::Backend> ng_backend_;

  mutable std::shared_ptr<ngraph::runtime::Executable> ng_curr_exe_ = nullptr;

  AllocateFunc allocate_func_ = nullptr;

  DestroyFunc release_func_ = nullptr;

  AllocatorHandle allocator_ = nullptr;

  std::string name_;

  /*
  nGraph::Executable objects are specific to input shapes.
  Here we keep of a cache of nGraph::Executable objects with key as input shapes. TODO: Configure size of this cache.
  Logically, key = [i0.rank,[i0.dims],i1.rank,[i1.dims] ... iN.rank,[iN.dims]] raw bytes enclosed inside a string.
  Example: input0.shape(1,2,3) input1.shape(4,5)
  key = [3,1,2,3,2,4,5]
*/
  mutable std::unordered_map<std::string, std::shared_ptr<ngraph::runtime::Executable>> ng_exe_map_;
  mutable std::list<std::string> keyCache;
  
  mutable std::mutex compute_lock_;

  mutable ONNX_NAMESPACE::ModelProto model_proto_;
};
}  // namespace ngraph_ep
}  // namespace onnxruntime
