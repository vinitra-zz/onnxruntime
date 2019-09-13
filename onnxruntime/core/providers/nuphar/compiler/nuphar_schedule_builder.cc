// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#include "core/providers/nuphar/compiler/nuphar_schedule_builder.h"

#include "core/codegen/common/settings.h"
#include "core/codegen/passes/scheduler/schedule_utils.h"
#include "core/codegen/passes/scheduler/tvm_schedule_builder.h"

#include "core/providers/nuphar/common/analysis/subgraph_codegen_stats.h"

// TODO change name space
namespace onnxruntime {
namespace nuphar {

// Traverse iterates a tvm::Tensor and itself dependencies
// and builds schedule (in ScheduleContext)
// based on corresponding ORT ir and TVM ir
static void Traverse(const tvm::Tensor& tensor,
                     const Node* node,
                     NupharCodeGenCtx& ctx_codegen,
                     tvm_codegen::ScheduleContext& ctx_schedule) {
  // no need to traverse on nodes already marked as closured
  if (ctx_schedule.scheduled_tensors.count(tensor->op.get()) > 0) {
    if (ctx_schedule.scheduled_tensors[tensor->op.get()] == tvm_codegen::ScheduleType::ScheduleClosure) {
      return;
    }
  }

  ctx_codegen.GetCodeGenHandle()->schedule_builder->Evaluate(tensor, node, ctx_codegen, ctx_schedule);

  // for real ouput
  bool is_real_output = nullptr != node &&
                        Promote<CodeGenUnitStats>(ctx_codegen.GetGraphStats())->IsOutputNode(node);

  if (is_real_output) {
    // TODO change it to the value from Target
    int64_t natural_vector_size = 16;

    TryVectorization(tensor, natural_vector_size, ctx_schedule);  // to x86
    InsertRootScheduleAndClosure(tensor, ctx_schedule);
  }

  // Traverse tensor's children
  for (auto& t : tensor->op->InputTensors()) {
    // check whether it is a tensor having inputs
    if (t->op->InputTensors().size() > 0) {
      auto current_node = ctx_codegen.FindNode(t);
      Traverse(t, current_node, ctx_codegen, ctx_schedule);
    }
  }
}

tvm::Schedule CreateSchedule(const tvm::Array<tvm::Tensor>& outs,
                             NupharCodeGenCtx& ctx_codegen) {
  // Create scheudule object
  tvm::Array<tvm::Operation> out_ops;
  for (auto& t : outs) {
    out_ops.push_back(t->op);
  }

  if (codegen::CodeGenSettings::Instance().HasOption(codegen::CodeGenSettings::kCodeGenDumpSchedule))
    ctx_codegen.GetCodeGenHandle()->schedule_builder->DumpAllSchedulers();

  tvm_codegen::ScheduleContext ctx_schedule(out_ops);

  // Schedule all outputs
  for (const auto& t : outs) {
    const Node* node = ctx_codegen.FindNode(t);
    Traverse(t, node, ctx_codegen, ctx_schedule);
  }

  return ctx_schedule.schedule;
}

}  // namespace nuphar
}  // namespace onnxruntime
