// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#pragma once
#include "onnxruntime/core/providers/cpu/cpu_provider_factory.h"

#ifdef USE_CUDA
#include "onnxruntime/core/providers/cuda/cuda_provider_factory.h"
#endif
#ifdef USE_MKLDNN
#include "onnxruntime/core/providers/mkldnn/mkldnn_provider_factory.h"
#endif
#ifdef USE_NGRAPH
#include "onnxruntime/core/providers/ngraph/ngraph_provider_factory.h"
#endif
#ifdef USE_NUPHAR
#include "onnxruntime/core/providers/nuphar/nuphar_provider_factory.h"
#endif
#if USE_BRAINSLICE
#include "onnxruntime/core/providers/brainslice/brainslice_provider_factory.h"
#endif
#ifdef USE_TENSORRT
#include "onnxruntime/core/providers/tensorrt/tensorrt_provider_factory.h"
#endif
