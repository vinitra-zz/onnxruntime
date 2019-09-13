// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#include "core/optimizer/unsqueeze_elimination.h"
#include "core/graph/graph_utils.h"
#include "core/graph/graph.h"

using namespace ONNX_NAMESPACE;
using namespace ::onnxruntime::common;

namespace onnxruntime {

Status UnsqueezeElimination::Apply(Graph& graph, Node& node, RewriteRuleEffect& rule_effect) const {
  // Get "axes" attribute.
  const ONNX_NAMESPACE::AttributeProto* attr = graph_utils::GetNodeAttribute(node, "axes");
  if (attr == nullptr || attr->type() != AttributeProto_AttributeType_INTS) {
    return Status::OK();
  }

  std::vector<int64_t> axes;
  axes.reserve(attr->ints_size());
  for (int i = 0; i < attr->ints_size(); i++) {
    axes.push_back(static_cast<int64_t>(attr->ints(i)));
  }

  // Generate new dims.
  NodeArg* input_def = node.MutableInputDefs()[0];
  const auto* tensor_proto = graph_utils::GetConstantInitializer(graph, input_def->Name());
  ORT_ENFORCE(tensor_proto);

  std::vector<int64_t> new_dims(axes.size() + tensor_proto->dims().size(), 0);
  if (new_dims.size() >= static_cast<unsigned int>(std::numeric_limits<int>::max())) {
    return Status(ONNXRUNTIME, FAIL, "index out of range");
  }

  for (int64_t axis : axes) {
    new_dims[axis] = 1;
  }

  auto begin = tensor_proto->dims().cbegin();
  for (auto& axis : new_dims) {
    if (axis == 0) {
      axis = *begin++;
    }
  }

  // Update shape of tensor proto.
  ONNX_NAMESPACE::TensorProto new_tensor_proto(*tensor_proto);

  for (int i = 0; i < static_cast<int>(new_dims.size()); i++) {
    if (i < tensor_proto->dims().size()) {
      new_tensor_proto.set_dims(i, new_dims[i]);
    } else {
      new_tensor_proto.add_dims(new_dims[i]);
    }
  }

  // TODO: This seems wrong as there's no check whether another node is using the initializer before replacing it.
  //       Shouldn't we check that or alternatively create an initializer with a different name and let
  //       Graph::CleanUnusedInitializers remove the original one if nothing else consumes it?
  // graph.RemoveInitializedTensor(input_def->Name());
  // graph.AddInitializedTensor(new_tensor_proto);
  graph_utils::ReplaceInitializer(graph, input_def->Name(), new_tensor_proto);

  // Update shape of NodeArg.
  TensorShapeProto shape;
  for (auto dim : new_dims) {
    shape.add_dim()->set_dim_value(dim);
  }
  input_def->SetShape(shape);

  // Remove Unsqueeze node.
  if (graph_utils::RemoveNode(graph, node)) {
    rule_effect = RewriteRuleEffect::kRemovedCurrentNode;
  }

  return Status::OK();
}  // namespace onnxruntime

bool UnsqueezeElimination::SatisfyCondition(const Graph& graph, const Node& node) const {
  // Attempt to remove an Unsqueeze operator only if it gets a constant initializer as input.
  return graph_utils::IsConstantInitializer(graph, node.InputDefs()[0]->Name()) &&
         !graph.IsNodeOutputsInGraphOutputs(node);
}

}  // namespace onnxruntime
