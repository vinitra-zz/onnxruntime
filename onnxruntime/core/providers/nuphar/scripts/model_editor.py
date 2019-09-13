# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

# -*- coding: UTF-8 -*-
import argparse
from enum import Enum
import numpy as np
import onnx
from node_factory import NodeFactory, ensure_opset
from symbolic_shape_infer import SymbolicShapeInference, get_shape_from_type_proto

# trim outputs of LSTM/GRU/RNN if not used or outputed
def trim_unused_outputs(node, graph):
    trimmed = onnx.NodeProto()
    trimmed.CopyFrom(node)
    graph_outputs = [o.name for o in graph.output]
    for o_idx in range(len(node.output)):
        o = node.output[o_idx]
        use = [n for n in graph.node if o in list(n.input) + graph_outputs]
        if not use:
            trimmed.output[o_idx] = ''
    return trimmed

# squeeze init states, and split forward/reverse for bidirectional
def handle_init_state(init_state, nf, num_directions):
    if not init_state:
        return None
    if not nf.get_initializer(init_state) is None:
        return nf.get_initializer(init_state)
    if num_directions == 2:
        split_names = [init_state + '_split_0', init_state + '_split_1']
        nf.make_node('Split', init_state, {'axis':0}, split_names) # [1, batch, hidden]
        return [nf.make_node('Squeeze', s, {'axes':[0]}) for s in split_names]
    else:
        return [nf.make_node('Squeeze', init_state, {'axes':[0]})]

# handle some common attributes between LSTM/GRU/RNN
def handle_common_attributes(node, default_activations):
    direction = NodeFactory.get_attribute(node, 'direction')
    if direction:
        direction = str(direction, 'utf-8')
    else:
        direction = 'forward'
    num_directions = 2 if direction == 'bidirectional' else 1

    activations = NodeFactory.get_attribute(node, 'activations')
    if activations:
        activations = [str(x, 'utf-8').lower().capitalize() for x in activations]
    else:
        activations = default_activations * num_directions

    activation_alpha = NodeFactory.get_attribute(node, 'activation_alpha')
    activation_beta = NodeFactory.get_attribute(node, 'activation_beta')
    clip_threshold = NodeFactory.get_attribute(node, 'clip')
    # TODO: support these activation attributes
    assert not activation_alpha
    assert not activation_beta
    assert not clip_threshold
    return direction, num_directions, activations

# get batch_size, and create batch_node if needed
def handle_batch_size(X, nf, need_batch_node):
    X_vi = nf.get_value_info(X)
    assert X_vi
    dim = get_shape_from_type_proto(X_vi.type)[1]
    if type(dim) == str and need_batch_node:
        # only need to create batch_node for symbolic batch_size
        # otherwise, just use numpy.zeros
        X_shape = nf.make_node('Shape', X)
        node = nf.make_node('Slice', X_shape, {'axes':[0],'starts':[1],'ends':[2]})
    else:
        node = None
    return dim, node

# create default init state with zeros
def default_init_state(X, batch_size, batch_node, hidden_size, nf, postfix=''):
    if batch_node:
        shape = nf.make_node('Concat', [batch_node, np.asarray([hidden_size]).astype(np.int64)], {'axis':0})
        return nf.make_node('ConstantOfShape', shape)
    else:
        assert type(batch_size) == int
        # add default init state to graph input
        initializer_name = X + '_zero_init_state' + postfix
        initializer_shape = (batch_size, hidden_size)
        nf.make_value_info(initializer_name, onnx.TensorProto.FLOAT, initializer_shape, NodeFactory.ValueInfoType.input)
        return nf.make_initializer(np.zeros(initializer_shape, dtype=np.float32), initializer_name)

# declare seq_len_subgraph if needed
# note rank-1 for seq_len is to differentiate it from rank-2 states
def declare_seq_len_in_subgraph(seq_len, nf_body, prefix, batch_size):
    if seq_len:
        seq_len_subgraph = prefix + '_seq_len_subgraph'
        nf_body.make_value_info(seq_len_subgraph,
                                data_type=onnx.TensorProto.INT32,
                                shape=(batch_size,),
                                usage=NodeFactory.ValueInfoType.input)
    else:
        seq_len_subgraph = None
    return seq_len_subgraph

# hook subgraph outputs, with condition from seq_len_subgraph
def handle_subgraph_outputs(nf_body, seq_len_subgraph, batch_size, hidden_size, subgraph_output_or_default):
    final_subgraph_output = []
    if seq_len_subgraph:
        seq_len_output = nf_body.make_node('Sub', [seq_len_subgraph, np.asarray([1]).astype(np.int32)])
        nf_body.make_value_info(seq_len_output,
                                data_type=onnx.TensorProto.INT32,
                                shape=(batch_size,),
                                usage=NodeFactory.ValueInfoType.output)
        final_subgraph_output.append(seq_len_output)

        # since seq_len is rank-1, need to unsqueeze for Where op on rank-2 states
        condition = nf_body.make_node('Unsqueeze', nf_body.make_node('Greater', [seq_len_subgraph, np.zeros(shape=(), dtype=np.int32)]), {'axes':[1]})
        for valid, default in subgraph_output_or_default:
            final_subgraph_output.append(nf_body.make_node('Where', [condition, valid, default]))
    else:
        final_subgraph_output.append(None)
        for valid, default in subgraph_output_or_default:
            final_subgraph_output.append(nf_body.make_node('Identity', valid))

    for subgraph_o in final_subgraph_output[1:]:
        nf_body.make_value_info(subgraph_o,
                                data_type=onnx.TensorProto.FLOAT,
                                shape=(batch_size, hidden_size),
                                usage=NodeFactory.ValueInfoType.output)

    return final_subgraph_output

# unsqueeze/concat for the final outputs from scans, when the LSTM/GRU/RNN node is bidirectional
def handle_final_scan_outputs(node, nf, scan_outputs, state_outputs, num_directions):
    if num_directions == 2:
        def _bidirectional(outputs, axis, hook_output_name):
            outputs = [nf.make_node('Unsqueeze', x, {'axes':[axis]}) for x in outputs]
            nf.make_node('Concat', outputs, {'axis':axis}, output_names=hook_output_name)

        if node.output[0]:
            _bidirectional(scan_outputs, 1, node.output[0])
        for i_o in range(1, len(node.output)):
            _bidirectional(state_outputs[i_o - 1], 0, node.output[i_o])
    else:
        if node.output[0]:
            nf.make_node('Unsqueeze', scan_outputs[0], {'axes':[1]}, output_names=node.output[0])
        for i_o in range(1, len(node.output)):
            nf.make_node('Unsqueeze', state_outputs[i_o - 1], {'axes':[0]}, output_names=node.output[i_o])

def convert_lstm_to_scan(node, out_main_graph):
    assert node.op_type == 'LSTM'
    nf = NodeFactory(out_main_graph)
    with nf.scoped_prefix(node.output[0]) as scoped_prefix:
        X = node.input[0]
        Wa = nf.get_initializer(node.input[1])
        Ra = nf.get_initializer(node.input[2])
        num_inputs = len(node.input)
        Ba = nf.get_initializer(node.input[3]) if num_inputs > 3 else None
        seq_len = node.input[4] if num_inputs > 4 else None
        InitHa = node.input[5] if num_inputs > 5 else None
        InitCa = node.input[6] if num_inputs > 6 else None
        PB = node.input[7] if num_inputs > 7 else None

        # TODO: support peephole
        assert not PB

        direction, num_directions, activations = handle_common_attributes(node, ['Sigmoid', 'Tanh', 'Tanh'])

        hidden_size = NodeFactory.get_attribute(node, 'hidden_size')
        input_forget = NodeFactory.get_attribute(node, 'input_forget')

        # TODO: implement input_forget = 1
        assert not (input_forget != None and input_forget == 1)

        # split initializer if needed:
        is_same_init = InitHa == InitCa
        InitHa = handle_init_state(InitHa, nf, num_directions)
        if is_same_init:
            InitCa = InitHa
        else:
            InitCa = handle_init_state(InitCa, nf, num_directions)

        batch_size, batch_node = handle_batch_size(X, nf, InitHa is None or InitCa is None)

        scan_outputs = []
        scan_h_outputs = []
        scan_c_outputs = []
        for direction_index in range(num_directions):
            # for each direction
            # X [seq_len, batch_size, input_size]
            # W [4*hidden_size, input_size]
            # R [4*hidden_size, hidden_size]
            # B [8*hidden_size]
            # seq_len [batch_size]
            # init_h [batch_size, hidden_size]
            # init_c [batch_size, hidden_size]
            # PB [3*hidden_size]

            name_prefix = node.output[0] + '_' + str(direction_index) + '_'

            if InitHa is None:
                init_h = default_init_state(X, batch_size, batch_node, hidden_size, nf, '_H')
            else:
                init_h = InitHa[direction_index]

            if InitCa is None:
                init_c =  default_init_state(X, batch_size, batch_node, hidden_size, nf, '_C')
            else:
                init_c = InitCa[direction_index]

            input_size = Wa.shape[len(Wa.shape) - 1]
            Wt = np.transpose(Wa[direction_index])
            Rt = np.transpose(Ra[direction_index])
            B = Ba[direction_index].reshape(2, 4*hidden_size).sum(axis=0) # [4*hidden_size]
            X_proj = nf.make_node('MatMul', [X, Wt]) #[seq_len, batch_size, 4*hidden_size]
            X_proj = nf.make_node('Add', [X_proj, B])
            if num_directions == 1:
                is_backward = 0 if direction == 'forward' else 1
            else:
                is_backward = direction_index

            scan_body = onnx.GraphProto()
            scan_body.name = name_prefix + '_subgraph'

            nf_body = NodeFactory(out_main_graph, scan_body)
            with nf_body.scoped_prefix(name_prefix) as body_scoped_prefix:
                # subgraph inputs
                X_proj_subgraph = X_proj.name + '_subgraph'
                prev_h_subgraph = name_prefix + '_h_subgraph'
                prev_c_subgraph = name_prefix + '_c_subgraph'

                seq_len_subgraph = declare_seq_len_in_subgraph(seq_len, nf_body, X_proj.name, batch_size)

                for subgraph_i in [prev_h_subgraph, prev_c_subgraph]:
                    nf_body.make_value_info(subgraph_i,
                                            data_type=onnx.TensorProto.FLOAT,
                                            shape=(batch_size, hidden_size),
                                            usage=NodeFactory.ValueInfoType.input)

                nf_body.make_value_info(X_proj_subgraph,
                                        data_type=onnx.TensorProto.FLOAT,
                                        shape=(batch_size, 4*hidden_size),
                                        usage=NodeFactory.ValueInfoType.input)
                # subgraph nodes
                # it = f(Xt*(Wi^T) + Ht-1*(Ri^T) + Pi (.) Ct-1 + Wbi + Rbi)
                # ft = f(Xt*(Wf^T) + Ht-1*(Rf^T) + Pf (.) Ct-1 + Wbf + Rbf)
                # ct = g(Xt*(Wc^T) + Ht-1*(Rc^T) + Wbc + Rbc)
                # Ct = ft (.) Ct-1 + it (.) ct
                # ot = f(Xt*(Wo^T) + Ht-1*(Ro^T) + Po (.) Ct + Wbo + Rbo)
                # Ht = ot (.) h(Ct)
                prev_h_proj = nf_body.make_node('MatMul', [prev_h_subgraph, Rt])
                sum_x_proj_h_proj_bias = nf_body.make_node('Add', [X_proj_subgraph, prev_h_proj])
                split_outputs = ['split_i', 'split_o', 'split_f', 'split_c']
                nf_body.make_node('Split', sum_x_proj_h_proj_bias, {"axis":1, "split":[hidden_size]*4}, output_names=split_outputs)
                # manually add shape inference to split outputs
                for split_o in split_outputs:
                    nf_body.make_value_info(split_o,
                                            data_type=onnx.TensorProto.FLOAT,
                                            shape=(batch_size, hidden_size))
                activation_f, activation_g, activation_h = activations[direction_index*3:(direction_index+1)*3]
                it = nf_body.make_node(activation_f, 'split_i')
                ft = nf_body.make_node(activation_f, 'split_f')
                ct = nf_body.make_node(activation_g, 'split_c')
                c_subgraph = nf_body.make_node('Add',
                                               [nf_body.make_node('Mul', [ft, prev_c_subgraph]),
                                                nf_body.make_node('Mul', [it, ct])])
                ot = nf_body.make_node(activation_f, 'split_o')
                h_subgraph = nf_body.make_node('Mul', [ot, nf_body.make_node(activation_h, c_subgraph)])

                subgraph_outputs = handle_subgraph_outputs(nf_body,
                                                           seq_len_subgraph,
                                                           batch_size,
                                                           hidden_size,
                                                           [(h_subgraph, prev_h_subgraph),
                                                            (c_subgraph, prev_c_subgraph)] +
                                                           ([(h_subgraph, np.zeros(shape=(), dtype=np.float32))] if node.output[0] else [])) # skip scan output if node.output[0] is empty

                scan_attribs = {'body':scan_body,
                                'scan_input_directions':[is_backward],
                                'num_scan_inputs':1}
                if node.output[0]:
                    scan_attribs.update({'scan_output_directions':[is_backward]})
                scan = nf.make_node('Scan', ([seq_len] if seq_len else []) + [init_h, init_c, X_proj],
                                    scan_attribs,
                                    output_names=[o.name for o in subgraph_outputs[(0 if seq_len else 1):]])

                scan_h_outputs.append(subgraph_outputs[1])
                scan_c_outputs.append(subgraph_outputs[2])
                if node.output[0]:
                    scan_outputs.append(subgraph_outputs[3])

        handle_final_scan_outputs(node, nf, scan_outputs, [scan_h_outputs, scan_c_outputs], num_directions)

    # remove old initializers
    nf.remove_initializer(node.input[1])
    nf.remove_initializer(node.input[2])
    if num_inputs > 3:
        nf.remove_initializer(node.input[3])
    if num_inputs > 5:
        nf.remove_initializer(node.input[5], allow_empty=True)
    if num_inputs > 6:
        nf.remove_initializer(node.input[6], allow_empty=True)
    return True

def convert_gru_to_scan(node, out_main_graph):
    assert node.op_type == 'GRU'
    nf = NodeFactory(out_main_graph)
    with nf.scoped_prefix(node.output[0]) as scoped_prefix:
        X = node.input[0]
        Wa = nf.get_initializer(node.input[1])
        Ra = nf.get_initializer(node.input[2])
        num_inputs = len(node.input)
        Ba = nf.get_initializer(node.input[3]) if num_inputs > 3 else None
        seq_len = node.input[4] if num_inputs > 4 else None
        InitHa = node.input[5] if num_inputs > 5 else None

        direction, num_directions, activations = handle_common_attributes(node, ['Sigmoid', 'Tanh'])

        hidden_size = NodeFactory.get_attribute(node, 'hidden_size')
        linear_before_reset = NodeFactory.get_attribute(node, 'linear_before_reset')
        InitHa = handle_init_state(InitHa, nf, num_directions)

        batch_size, batch_node = handle_batch_size(X, nf, InitHa is None)
        if InitHa is None:
            zero_init_state = default_init_state(X, batch_size, batch_node, hidden_size, nf)

        scan_outputs = []
        scan_h_outputs = []
        for direction_index in range(num_directions):
            # for each direction
            # X [seq_len, batch_size, input_size]
            # W [3*hidden_size, input_size]
            # R [3*hidden_size, hidden_size]
            # B [6*hidden_size]
            # seq_len [batch_size]
            # init_h [batch_size, hidden_size]

            name_prefix = node.output[0] + '_' + str(direction_index) + '_'

            if InitHa is None:
                init_h = zero_init_state
            else:
                init_h = InitHa[direction_index]

            input_size = Wa.shape[len(Wa.shape) - 1]
            W_t = np.transpose(Wa[direction_index]) # [input_size, 3*hidden_size]
            R_t = np.transpose(Ra[direction_index]) # [hidden_size, 3*hidden_size]
            Rzr_t, Rh_t = np.hsplit(R_t, [2*hidden_size]) # [hidden_size, 2*hidden_size] and [hidden_size, hidden_size]
            Bzr, Bh = np.hsplit(Ba[direction_index].reshape(2, 3*hidden_size), [2*hidden_size])
            Bzr = Bzr.sum(axis=0) # [2*hidden_size]
            Wbh = Bh[0]
            Rbh = Bh[1]
            X_proj = nf.make_node('Add', [nf.make_node('MatMul', [X, W_t]), np.concatenate((Bzr, Wbh))]) #[seq_len, batch_size, 3*hidden_size]
            if num_directions == 1:
                is_backward = 0 if direction == 'forward' else 1
            else:
                is_backward = direction_index

            scan_body = onnx.GraphProto()
            scan_body.name = name_prefix + '_subgraph'

            nf_body = NodeFactory(out_main_graph, scan_body)
            with nf_body.scoped_prefix(name_prefix) as body_scoped_prefix:
                # subgraph inputs
                X_proj_subgraph = X_proj.name + '_subgraph'
                prev_h_subgraph = name_prefix + '_h_subgraph'

                seq_len_subgraph = declare_seq_len_in_subgraph(seq_len, nf_body, X_proj.name, batch_size)

                nf_body.make_value_info(prev_h_subgraph,
                                        data_type=onnx.TensorProto.FLOAT,
                                        shape=(batch_size, hidden_size),
                                        usage=NodeFactory.ValueInfoType.input)

                nf_body.make_value_info(X_proj_subgraph,
                                        data_type=onnx.TensorProto.FLOAT,
                                        shape=(batch_size, 3*hidden_size),
                                        usage=NodeFactory.ValueInfoType.input)

                # subgraph nodes
                # zt = f(Xt*(Wz^T) + Ht-1*(Rz^T) + Wbz + Rbz)
                # rt = f(Xt*(Wr^T) + Ht-1*(Rr^T) + Wbr + Rbr)
                # ht = g(Xt*(Wh^T) + (rt (.) Ht-1)*(Rh^T) + Rbh + Wbh) # default, when linear_before_reset = 0
                # ht = g(Xt*(Wh^T) + (rt (.) (Ht-1*(Rh^T) + Rbh)) + Wbh) # when linear_before_reset != 0
                # Ht = (1 - zt) (.) ht + zt (.) Ht-1

                split_X_outputs = ['split_Xzr', 'split_Xh']
                nf_body.make_node('Split', X_proj_subgraph, {"axis":1, "split":[2*hidden_size, hidden_size]}, output_names=split_X_outputs)
                nf_body.make_value_info('split_Xzr',
                                        data_type=onnx.TensorProto.FLOAT,
                                        shape=(batch_size, 2*hidden_size))
                nf_body.make_value_info('split_Xh',
                                        data_type=onnx.TensorProto.FLOAT,
                                        shape=(batch_size, hidden_size))

                activation_f, activation_g = activations[direction_index*2:(direction_index+1)*2]

                if linear_before_reset:
                    prev_h_proj = nf_body.make_node('Add', [nf_body.make_node('MatMul', [prev_h_subgraph, R_t]), np.concatenate((np.zeros(2*hidden_size).astype(np.float32), Rbh))])
                    split_prev_h_outputs = ['split_Hzr', 'split_Hh']
                    nf_body.make_node('Split', prev_h_proj, {"axis":1, "split":[2*hidden_size, hidden_size]}, output_names=split_prev_h_outputs)
                    nf_body.make_value_info('split_Hzr',
                                            data_type=onnx.TensorProto.FLOAT,
                                            shape=(batch_size, 2*hidden_size))
                    nf_body.make_value_info('split_Hh',
                                            data_type=onnx.TensorProto.FLOAT,
                                            shape=(batch_size, hidden_size))
                    ztrt = nf_body.make_node(activation_f, nf_body.make_node('Add', ['split_Hzr', 'split_Xzr']))
                    split_ztrt_outputs = ['split_zt', 'split_rt']
                    nf_body.make_node('Split', ztrt, {"axis":1, "split":[hidden_size, hidden_size]}, output_names=split_ztrt_outputs)
                    nf_body.make_value_info('split_zt',
                                            data_type=onnx.TensorProto.FLOAT,
                                            shape=(batch_size, hidden_size))
                    nf_body.make_value_info('split_rt',
                                            data_type=onnx.TensorProto.FLOAT,
                                            shape=(batch_size, hidden_size))
                    ht = nf_body.make_node(activation_g, nf_body.make_node('Add', [nf_body.make_node('Mul', ['split_rt', 'split_Hh']), 'split_Xh']))
                else:
                    ztrt = nf_body.make_node(activation_f, nf_body.make_node('Add', [nf_body.make_node('MatMul', [prev_h_subgraph, Rzr_t]), 'split_Xzr']))
                    split_ztrt_outputs = ['split_zt', 'split_rt']
                    nf_body.make_node('Split', ztrt, {"axis":1, "split":[hidden_size, hidden_size]}, output_names=split_ztrt_outputs)
                    nf_body.make_value_info('split_zt',
                                            data_type=onnx.TensorProto.FLOAT,
                                            shape=(batch_size, hidden_size))
                    nf_body.make_value_info('split_rt',
                                            data_type=onnx.TensorProto.FLOAT,
                                            shape=(batch_size, hidden_size))
                    ht = nf_body.make_node(activation_g, nf_body.make_node('Add', [nf_body.make_node('MatMul', [nf_body.make_node('Mul', [prev_h_subgraph, 'split_rt']), Rh_t]), 'split_Xh']))

                Ht = nf_body.make_node('Add', [nf_body.make_node('Mul', [nf_body.make_node('Sub', [np.asarray([1]).astype(np.float32),
                                                                                                   'split_zt']),
                                                                         ht]),
                                               nf_body.make_node('Mul', ['split_zt', prev_h_subgraph])])

                subgraph_outputs = handle_subgraph_outputs(nf_body,
                                                           seq_len_subgraph,
                                                           batch_size,
                                                           hidden_size,
                                                           [(Ht, prev_h_subgraph)] +
                                                           ([(Ht, np.zeros(shape=(), dtype=np.float32))] if node.output[0] else []))

                scan_attribs = {'body':scan_body,
                                'scan_input_directions':[is_backward],
                                'num_scan_inputs':1}
                if node.output[0]:
                    scan_attribs.update({'scan_output_directions':[is_backward]})
                scan = nf.make_node('Scan', ([seq_len] if seq_len else []) + [init_h, X_proj],
                                    scan_attribs,
                                    output_names=[o.name for o in subgraph_outputs[(0 if seq_len else 1):]])

                scan_h_outputs.append(subgraph_outputs[1])
                if node.output[0]:
                    scan_outputs.append(subgraph_outputs[2])

        handle_final_scan_outputs(node, nf, scan_outputs, [scan_h_outputs], num_directions)

    # remove old initializers
    nf.remove_initializer(node.input[1])
    nf.remove_initializer(node.input[2])
    if num_inputs > 3:
        nf.remove_initializer(node.input[3])
    if num_inputs > 5:
        nf.remove_initializer(node.input[5], allow_empty=True)
    return True

def convert_rnn_to_scan(node, out_main_graph):
    assert node.op_type == 'RNN'
    nf = NodeFactory(out_main_graph)
    with nf.scoped_prefix(node.output[0]) as scoped_prefix:
        X = node.input[0]
        Wa = nf.get_initializer(node.input[1])
        Ra = nf.get_initializer(node.input[2])
        num_inputs = len(node.input)
        Ba = nf.get_initializer(node.input[3]) if num_inputs > 3 else None
        seq_len = node.input[4] if num_inputs > 4 else None
        InitHa = node.input[5] if num_inputs > 5 else None

        direction, num_directions, activations = handle_common_attributes(node, ['Tanh'])

        hidden_size = NodeFactory.get_attribute(node, 'hidden_size')

        InitHa = handle_init_state(InitHa, nf, num_directions)

        batch_size, batch_node = handle_batch_size(X, nf, InitHa is None)
        if InitHa is None:
            zero_init_state = default_init_state(X, batch_size, batch_node, hidden_size, nf)

        scan_outputs = []
        scan_h_outputs = []
        for direction_index in range(num_directions):
            # for each direction
            # X [seq_len, batch_size, input_size]
            # W [hidden_size, input_size]
            # R [hidden_size, hidden_size]
            # B [2*hidden_size]
            # seq_len [batch_size]
            # init_h [batch_size, hidden_size]

            name_prefix = node.output[0] + '_' + str(direction_index) + '_'

            if InitHa is None:
                init_h = zero_init_state
            else:
                init_h = InitHa[direction_index]

            input_size = Wa.shape[len(Wa.shape) - 1]
            W_t = np.transpose(Wa[direction_index]) # [input_size, hidden_size]
            R_t = np.transpose(Ra[direction_index]) # [hidden_size, hidden_size]
            B = Ba[direction_index].reshape(2, hidden_size).sum(axis=0) # [hidden_size]
            X_proj = nf.make_node('Add', [nf.make_node('MatMul', [X, W_t]), B]) #[seq_len, batch_size, hidden_size]
            if num_directions == 1:
                is_backward = 0 if direction == 'forward' else 1
            else:
                is_backward = direction_index

            scan_body = onnx.GraphProto()
            scan_body.name = name_prefix + '_subgraph'

            nf_body = NodeFactory(out_main_graph, scan_body)
            with nf_body.scoped_prefix(name_prefix) as body_scoped_prefix:
                # subgraph inputs
                X_proj_subgraph = X_proj.name + '_subgraph'
                prev_h_subgraph = name_prefix + '_h_subgraph'

                seq_len_subgraph = declare_seq_len_in_subgraph(seq_len, nf_body, X_proj.name, batch_size)

                nf_body.make_value_info(prev_h_subgraph,
                                        data_type=onnx.TensorProto.FLOAT,
                                        shape=(batch_size, hidden_size),
                                        usage=NodeFactory.ValueInfoType.input)

                nf_body.make_value_info(X_proj_subgraph,
                                        data_type=onnx.TensorProto.FLOAT,
                                        shape=(batch_size, hidden_size),
                                        usage=NodeFactory.ValueInfoType.input)
                # subgraph nodes
                # Ht = f(Xt*(W^T) + Ht-1*(R^T) + Wb + Rb)

                activation_f = activations[direction_index]
                Ht = nf_body.make_node(activation_f, nf_body.make_node('Add', [nf_body.make_node('MatMul', [prev_h_subgraph, R_t]), X_proj_subgraph]))

                subgraph_outputs = handle_subgraph_outputs(nf_body,
                                                           seq_len_subgraph,
                                                           batch_size,
                                                           hidden_size,
                                                           [(Ht, prev_h_subgraph)] +
                                                           ([(Ht, np.zeros(shape=(), dtype=np.float32))] if node.output[0] else []))

                scan_attribs = {'body':scan_body,
                                'scan_input_directions':[is_backward],
                                'num_scan_inputs':1}
                if node.output[0]:
                    scan_attribs.update({'scan_output_directions':[is_backward]})
                scan = nf.make_node('Scan', ([seq_len] if seq_len else []) + [init_h, X_proj],
                                    scan_attribs,
                                    output_names=[o.name for o in subgraph_outputs[(0 if seq_len else 1):]])

                scan_h_outputs.append(subgraph_outputs[1])
                if node.output[0]:
                    scan_outputs.append(subgraph_outputs[2])

        handle_final_scan_outputs(node, nf, scan_outputs, [scan_h_outputs], num_directions)

    # remove old initializers
    nf.remove_initializer(node.input[1])
    nf.remove_initializer(node.input[2])
    if num_inputs > 3:
        nf.remove_initializer(node.input[3])
    if num_inputs > 5:
        nf.remove_initializer(node.input[5])
    return True

def convert_to_scan_model(input_model, output_model):
    in_mp = onnx.load(input_model)
    out_mp = onnx.ModelProto()
    out_mp.CopyFrom(in_mp)
    out_mp.ir_version = 5 # update ir version to avoid requirement of initializer in graph input
    ensure_opset(out_mp, 9) # bump up to ONNX opset 9, which is required for Scan
    out_mp.graph.ClearField('node')
    for in_n in in_mp.graph.node:
        if in_n.op_type in ['LSTM', 'GRU', 'RNN']:
            in_n = trim_unused_outputs(in_n, in_mp.graph)
        if in_n.op_type == 'LSTM':
            if convert_lstm_to_scan(in_n, out_mp.graph):
                continue
        if in_n.op_type == 'GRU':
            if convert_gru_to_scan(in_n, out_mp.graph):
                continue
        if in_n.op_type == 'RNN':
            if convert_rnn_to_scan(in_n, out_mp.graph):
                continue
        out_n = out_mp.graph.node.add()
        out_n.CopyFrom(in_n)

    onnx.save(out_mp, output_model)

# Old models (ir_version < 4) is required to initializers in graph inputs
# This is optional for ir_version >= 4
def remove_initializers_from_inputs(input_model, output_model, remain_inputs=[]):
    mp = onnx.load(input_model)

    def _append_initializer_from_graph(graph):
        initializers = [i.name for i in graph.initializer]
        for node in graph.node:
            if node.op_type == 'Scan': # currently only handle Scan
                subgraph = NodeFactory.get_attribute(node, 'body')
                initializers += _append_initializer_from_graph(subgraph)
        return initializers

    all_initializer_names = [n for n in _append_initializer_from_graph(mp.graph) if n not in remain_inputs]
    new_inputs = [vi for vi in mp.graph.input if not vi.name in all_initializer_names]
    mp.graph.ClearField('input')
    mp.graph.input.extend(new_inputs)
    onnx.save(mp, output_model)

def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', help='The modification mode',
                        choices=['to_scan',
                                 'remove_initializers_from_inputs'])
    parser.add_argument('--input', help='The input model file', default=None)
    parser.add_argument('--output', help='The output model file', default=None)
    return parser.parse_args()

if __name__ == '__main__':
    args = parse_arguments()
    print('input model: ' + args.input)
    print('output model ' + args.output)
    if args.mode == 'to_scan':
        print('Convert LSTM/GRU/RNN to Scan...')
        convert_to_scan_model(args.input, args.output)
    elif args.mode == 'remove_initializers_from_inputs':
        print('Remove all initializers from input for model with IR version >= 4...')
        remove_initializers_from_inputs(args.input, args.output)
    else:
        raise NotImplementedError('Unknown mode')
    print('Running symbolic shape inference on output model')
    SymbolicShapeInference.infer_shapes(args.output, args.output, auto_merge=True)
    print('Done!')
