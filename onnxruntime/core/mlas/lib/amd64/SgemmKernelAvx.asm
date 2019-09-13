;++
;
; Copyright (c) Microsoft Corporation. All rights reserved.
;
; Licensed under the MIT License.
;
; Module Name:
;
;   SgemmKernelAvx.asm
;
; Abstract:
;
;   This module implements the kernels for the single precision matrix/matrix
;   multiply operation (SGEMM).
;
;   This implementation uses AVX instructions.
;
;--

        .xlist
INCLUDE mlasi.inc
INCLUDE SgemmKernelCommon.inc
        .list

        EXTERN  MlasMaskMoveAvx:NEAR

;
; Macro Description:
;
;   This macro multiplies and accumulates for a 16xN block of the output matrix.
;
; Arguments:
;
;   RowCount - Supplies the number of rows to process.
;
;   VectorOffset - Supplies the byte offset from matrix B to fetch elements.
;
;   BroadcastOffset - Supplies the byte offset from matrix A to fetch elements.
;
;   PrefetchOffset - Optionally supplies the byte offset from matrix B to
;       prefetch elements.
;
; Implicit Arguments:
;
;   rbx - Supplies the address into the matrix A data plus 2 rows.
;
;   rcx - Supplies the address into the matrix A data.
;
;   rdx - Supplies the address into the matrix B data.
;
;   r10 - Supplies the length in bytes of a row from matrix A.
;
;   ymm8-ymm15 - Supplies the block accumulators.
;

ComputeBlockAvxBy16 MACRO RowCount, VectorOffset, BroadcastOffset, PrefetchOffset

IF RowCount EQ 1
        vbroadcastss ymm3,DWORD PTR [rcx+BroadcastOffset]
        vmulps  ymm4,ymm3,YMMWORD PTR [rdx+VectorOffset]
        vaddps  ymm8,ymm8,ymm4
        vmulps  ymm5,ymm3,YMMWORD PTR [rdx+VectorOffset+32]
        vaddps  ymm9,ymm9,ymm5
ELSE
        vmovaps ymm0,YMMWORD PTR [rdx+VectorOffset]
        vmovaps ymm1,YMMWORD PTR [rdx+VectorOffset+32]
        EmitIfCountGE RowCount, 1, <vbroadcastss ymm3,DWORD PTR [rcx+BroadcastOffset]>
        EmitIfCountGE RowCount, 1, <vmulps ymm4,ymm3,ymm0>
        EmitIfCountGE RowCount, 1, <vaddps ymm8,ymm8,ymm4>
        EmitIfCountGE RowCount, 1, <vmulps ymm5,ymm3,ymm1>
        EmitIfCountGE RowCount, 1, <vaddps ymm9,ymm9,ymm5>
        EmitIfCountGE RowCount, 2, <vbroadcastss ymm3,DWORD PTR [rcx+r10+BroadcastOffset]>
        EmitIfCountGE RowCount, 2, <vmulps ymm6,ymm3,ymm0>
        EmitIfCountGE RowCount, 2, <vaddps ymm10,ymm10,ymm6>
        EmitIfCountGE RowCount, 2, <vmulps ymm7,ymm3,ymm1>
        EmitIfCountGE RowCount, 2, <vaddps ymm11,ymm11,ymm7>
        EmitIfCountGE RowCount, 3, <vbroadcastss ymm3,DWORD PTR [rbx+BroadcastOffset]>
        EmitIfCountGE RowCount, 3, <vmulps ymm4,ymm3,ymm0>
        EmitIfCountGE RowCount, 3, <vaddps ymm12,ymm12,ymm4>
        EmitIfCountGE RowCount, 3, <vmulps ymm5,ymm3,ymm1>
        EmitIfCountGE RowCount, 3, <vaddps ymm13,ymm13,ymm5>
        EmitIfCountGE RowCount, 4, <vbroadcastss ymm3,DWORD PTR [rbx+r10+BroadcastOffset]>
        EmitIfCountGE RowCount, 4, <vmulps ymm6,ymm3,ymm0>
        EmitIfCountGE RowCount, 4, <vaddps ymm14,ymm14,ymm6>
        EmitIfCountGE RowCount, 4, <vmulps ymm7,ymm3,ymm1>
        EmitIfCountGE RowCount, 4, <vaddps ymm15,ymm15,ymm7>
ENDIF

        ENDM

;
; Macro Description:
;
;   This macro multiplies and accumulates for a 8xN block of the output matrix.
;
; Arguments:
;
;   RowCount - Supplies the number of rows to process.
;
;   VectorOffset - Supplies the byte offset from matrix B to fetch elements.
;
;   BroadcastOffset - Supplies the byte offset from matrix A to fetch elements.
;
;   PrefetchOffset - Optionally supplies the byte offset from matrix B to
;       prefetch elements.
;
; Implicit Arguments:
;
;   rbx - Supplies the address into the matrix A data plus 2 rows.
;
;   rcx - Supplies the address into the matrix A data.
;
;   rdx - Supplies the address into the matrix B data.
;
;   r10 - Supplies the length in bytes of a row from matrix A.
;
;   ymm8-ymm15 - Supplies the block accumulators.
;

ComputeBlockAvxBy8 MACRO RowCount, VectorOffset, BroadcastOffset, PrefetchOffset

IF RowCount EQ 1
        vbroadcastss ymm3,DWORD PTR [rcx+BroadcastOffset]
        vmulps  ymm5,ymm3,YMMWORD PTR [rdx+VectorOffset]
        vaddps  ymm9,ymm9,ymm5
ELSE
        vmovaps ymm0,YMMWORD PTR [rdx+VectorOffset]
        EmitIfCountGE RowCount, 1, <vbroadcastss ymm3,DWORD PTR [rcx+BroadcastOffset]>
        EmitIfCountGE RowCount, 1, <vmulps ymm5,ymm3,ymm0>
        EmitIfCountGE RowCount, 1, <vaddps ymm9,ymm9,ymm5>
        EmitIfCountGE RowCount, 2, <vbroadcastss ymm3,DWORD PTR [rcx+r10+BroadcastOffset]>
        EmitIfCountGE RowCount, 2, <vmulps ymm7,ymm3,ymm0>
        EmitIfCountGE RowCount, 2, <vaddps ymm11,ymm11,ymm7>
        EmitIfCountGE RowCount, 3, <vbroadcastss ymm3,DWORD PTR [rbx+BroadcastOffset]>
        EmitIfCountGE RowCount, 3, <vmulps ymm5,ymm3,ymm0>
        EmitIfCountGE RowCount, 3, <vaddps ymm13,ymm13,ymm5>
        EmitIfCountGE RowCount, 4, <vbroadcastss ymm3,DWORD PTR [rbx+r10+BroadcastOffset]>
        EmitIfCountGE RowCount, 4, <vmulps ymm7,ymm3,ymm0>
        EmitIfCountGE RowCount, 4, <vaddps ymm15,ymm15,ymm7>
ENDIF

        ENDM

;
; Macro Description:
;
;   This macro generates code to execute the block compute macro multiple
;   times and advancing the matrix A and matrix B data pointers.
;
; Arguments:
;
;   ComputeBlock - Supplies the macro to compute a single block.
;
;   RowCount - Supplies the number of rows to process.
;
; Implicit Arguments:
;
;   rbx - Supplies the address into the matrix A data plus N rows.
;
;   rcx - Supplies the address into the matrix A data.
;
;   rdx - Supplies the address into the matrix B data.
;
;   r9 - Supplies the number of columns from matrix A and the number of rows
;       from matrix B to iterate over.
;
;   ymm4-ymm15 - Supplies the block accumulators.
;

ComputeBlockAvxLoop MACRO ComputeBlock, RowCount

IF RowCount GT 2
        lea     rbx,[rcx+r10*2]             ; compute matrix A plus 2 rows
ENDIF
        ComputeBlockLoop ComputeBlock, RowCount, <RowCount GT 2>
IF RowCount GT 2
        lea     rbx,[r8+rax*2]              ; compute matrix C plus 2 rows
ENDIF

        ENDM

;
; Macro Description:
;
;   This macro generates code to compute matrix multiplication for a fixed set
;   of rows.
;
; Arguments:
;
;   RowCount - Supplies the number of rows to process.
;
;   Fallthrough - Supplies a non-blank value if the macro may fall through to
;       the ExitKernel label.
;
; Implicit Arguments:
;
;   rax - Supplies the length in bytes of a row from matrix C.
;
;   rcx - Supplies the address of matrix A.
;
;   rdx - Supplies the address of matrix B.
;
;   rsi - Supplies the address of matrix A.
;
;   rbp - Supplies the number of columns from matrix B and matrix C to iterate
;       over.
;
;   r8 - Supplies the address of matrix C.
;
;   r9 - Supplies the number of columns from matrix A and the number of rows
;       from matrix B to iterate over.
;
;   r10 - Supplies the length in bytes of a row from matrix A.
;
;   r15 - Stores the ZeroMode argument from the stack frame.
;

ProcessCountM MACRO RowCount, Fallthrough

        LOCAL   ProcessNextColumnLoop16xN
        LOCAL   Store16xNBlock
        LOCAL   ProcessRemainingCountN
        LOCAL   Store8xNBlock
        LOCAL   OutputMasked16xNBlock
        LOCAL   StoreMasked16xNBlock
        LOCAL   OutputMasked8xNBlock
        LOCAL   StoreMasked8xNBlock

        cmp     rbp,8
        jbe     ProcessRemainingCountN

ProcessNextColumnLoop16xN:
        EmitIfCountGE RowCount, 1, <vxorps xmm8,xmm8,xmm8>
        EmitIfCountGE RowCount, 1, <vxorps xmm9,xmm9,xmm9>
        EmitIfCountGE RowCount, 2, <vxorps xmm10,xmm10,xmm10>
        EmitIfCountGE RowCount, 2, <vxorps xmm11,xmm11,xmm11>
        EmitIfCountGE RowCount, 3, <vxorps xmm12,xmm12,xmm12>
        EmitIfCountGE RowCount, 3, <vxorps xmm13,xmm13,xmm13>
        EmitIfCountGE RowCount, 4, <vxorps xmm14,xmm14,xmm14>
        EmitIfCountGE RowCount, 4, <vxorps xmm15,xmm15,xmm15>
        ComputeBlockAvxLoop ComputeBlockAvxBy16, RowCount
        EmitIfCountGE RowCount, 1, <vmulps ymm8,ymm8,ymm2>
        EmitIfCountGE RowCount, 1, <vmulps ymm9,ymm9,ymm2>
        EmitIfCountGE RowCount, 2, <vmulps ymm10,ymm10,ymm2>
        EmitIfCountGE RowCount, 2, <vmulps ymm11,ymm11,ymm2>
        EmitIfCountGE RowCount, 3, <vmulps ymm12,ymm12,ymm2>
        EmitIfCountGE RowCount, 3, <vmulps ymm13,ymm13,ymm2>
        EmitIfCountGE RowCount, 4, <vmulps ymm14,ymm14,ymm2>
        EmitIfCountGE RowCount, 4, <vmulps ymm15,ymm15,ymm2>
        sub     rbp,16
        jb      OutputMasked16xNBlock
        test    r15b,r15b                   ; ZeroMode?
        jnz     Store16xNBlock
        EmitIfCountGE RowCount, 1, <vaddps ymm8,ymm8,YMMWORD PTR [r8]>
        EmitIfCountGE RowCount, 1, <vaddps ymm9,ymm9,YMMWORD PTR [r8+32]>
        EmitIfCountGE RowCount, 2, <vaddps ymm10,ymm10,YMMWORD PTR [r8+rax]>
        EmitIfCountGE RowCount, 2, <vaddps ymm11,ymm11,YMMWORD PTR [r8+rax+32]>
        EmitIfCountGE RowCount, 3, <vaddps ymm12,ymm12,YMMWORD PTR [rbx]>
        EmitIfCountGE RowCount, 3, <vaddps ymm13,ymm13,YMMWORD PTR [rbx+32]>
        EmitIfCountGE RowCount, 4, <vaddps ymm14,ymm14,YMMWORD PTR [rbx+rax]>
        EmitIfCountGE RowCount, 4, <vaddps ymm15,ymm15,YMMWORD PTR [rbx+rax+32]>

Store16xNBlock:
        EmitIfCountGE RowCount, 1, <vmovups YMMWORD PTR [r8],ymm8>
        EmitIfCountGE RowCount, 1, <vmovups YMMWORD PTR [r8+32],ymm9>
        EmitIfCountGE RowCount, 2, <vmovups YMMWORD PTR [r8+rax],ymm10>
        EmitIfCountGE RowCount, 2, <vmovups YMMWORD PTR [r8+rax+32],ymm11>
        EmitIfCountGE RowCount, 3, <vmovups YMMWORD PTR [rbx],ymm12>
        EmitIfCountGE RowCount, 3, <vmovups YMMWORD PTR [rbx+32],ymm13>
        EmitIfCountGE RowCount, 4, <vmovups YMMWORD PTR [rbx+rax],ymm14>
        EmitIfCountGE RowCount, 4, <vmovups YMMWORD PTR [rbx+rax+32],ymm15>
        add     r8,16*4                     ; advance matrix C by 16 columns
        mov     rcx,rsi                     ; reload matrix A
        cmp     rbp,8
        ja      ProcessNextColumnLoop16xN
        test    rbp,rbp
        jz      ExitKernel

ProcessRemainingCountN:
        EmitIfCountGE RowCount, 1, <vxorps xmm9,xmm9,xmm9>
        EmitIfCountGE RowCount, 2, <vxorps xmm11,xmm11,xmm11>
        EmitIfCountGE RowCount, 3, <vxorps xmm13,xmm13,xmm13>
        EmitIfCountGE RowCount, 4, <vxorps xmm15,xmm15,xmm15>
        ComputeBlockAvxLoop ComputeBlockAvxBy8, RowCount
        EmitIfCountGE RowCount, 1, <vmulps ymm9,ymm9,ymm2>
        EmitIfCountGE RowCount, 2, <vmulps ymm11,ymm11,ymm2>
        EmitIfCountGE RowCount, 3, <vmulps ymm13,ymm13,ymm2>
        EmitIfCountGE RowCount, 4, <vmulps ymm15,ymm15,ymm2>
        cmp     rbp,8
        jb      OutputMasked8xNBlock
        test    r15b,r15b                   ; ZeroMode?
        jnz     Store8xNBlock
        EmitIfCountGE RowCount, 1, <vaddps ymm9,ymm9,YMMWORD PTR [r8]>
        EmitIfCountGE RowCount, 2, <vaddps ymm11,ymm11,YMMWORD PTR [r8+rax]>
        EmitIfCountGE RowCount, 3, <vaddps ymm13,ymm13,YMMWORD PTR [rbx]>
        EmitIfCountGE RowCount, 4, <vaddps ymm15,ymm15,YMMWORD PTR [rbx+rax]>

Store8xNBlock:
        EmitIfCountGE RowCount, 1, <vmovups YMMWORD PTR [r8],ymm9>
        EmitIfCountGE RowCount, 2, <vmovups YMMWORD PTR [r8+rax],ymm11>
        EmitIfCountGE RowCount, 3, <vmovups YMMWORD PTR [rbx],ymm13>
        EmitIfCountGE RowCount, 4, <vmovups YMMWORD PTR [rbx+rax],ymm15>
        jmp     ExitKernel

OutputMasked16xNBlock:
        test    r15b,r15b                   ; ZeroMode?
        jnz     StoreMasked16xNBlock
        EmitIfCountGE RowCount, 1, <vaddps ymm8,ymm8,YMMWORD PTR [r8]>
        EmitIfCountGE RowCount, 2, <vaddps ymm10,ymm10,YMMWORD PTR [r8+rax]>
        EmitIfCountGE RowCount, 3, <vaddps ymm12,ymm12,YMMWORD PTR [rbx]>
        EmitIfCountGE RowCount, 4, <vaddps ymm14,ymm14,YMMWORD PTR [rbx+rax]>

StoreMasked16xNBlock:
        EmitIfCountGE RowCount, 1, <vmovups YMMWORD PTR [r8],ymm8>
        EmitIfCountGE RowCount, 2, <vmovups YMMWORD PTR [r8+rax],ymm10>
        EmitIfCountGE RowCount, 3, <vmovups YMMWORD PTR [rbx],ymm12>
        EmitIfCountGE RowCount, 4, <vmovups YMMWORD PTR [rbx+rax],ymm14>
        add     r8,8*4                      ; advance matrix C by 8 columns
IF RowCount GT 2
        add     rbx,8*4                     ; advance matrix C plus 2 rows by 8 columns
ENDIF
        add     rbp,8                       ; correct for over-subtract above

OutputMasked8xNBlock:
        mov     DWORD PTR SgemmKernelFrame.CountN[rsp],ebp
        vbroadcastss xmm0,DWORD PTR SgemmKernelFrame.CountN[rsp]
        vpcmpgtd xmm1,xmm0,XMMWORD PTR [MlasMaskMoveAvx+16]
        vpcmpgtd xmm0,xmm0,XMMWORD PTR [MlasMaskMoveAvx]
        vinsertf128 ymm0,ymm0,xmm1,1
        test    r15b,r15b                   ; ZeroMode?
        jnz     StoreMasked8xNBlock
        EmitIfCountGE RowCount, 1, <vmaskmovps ymm8,ymm0,YMMWORD PTR [r8]>
        EmitIfCountGE RowCount, 2, <vmaskmovps ymm10,ymm0,YMMWORD PTR [r8+rax]>
        EmitIfCountGE RowCount, 3, <vmaskmovps ymm12,ymm0,YMMWORD PTR [rbx]>
        EmitIfCountGE RowCount, 4, <vmaskmovps ymm14,ymm0,YMMWORD PTR [rbx+rax]>
        EmitIfCountGE RowCount, 1, <vaddps ymm9,ymm9,ymm8>
        EmitIfCountGE RowCount, 2, <vaddps ymm11,ymm11,ymm10>
        EmitIfCountGE RowCount, 3, <vaddps ymm13,ymm13,ymm12>
        EmitIfCountGE RowCount, 4, <vaddps ymm15,ymm15,ymm14>

StoreMasked8xNBlock:
        EmitIfCountGE RowCount, 1, <vmaskmovps YMMWORD PTR [r8],ymm0,ymm9>
        EmitIfCountGE RowCount, 2, <vmaskmovps YMMWORD PTR [r8+rax],ymm0,ymm11>
        EmitIfCountGE RowCount, 3, <vmaskmovps YMMWORD PTR [rbx],ymm0,ymm13>
        EmitIfCountGE RowCount, 4, <vmaskmovps YMMWORD PTR [rbx+rax],ymm0,ymm15>
IFB <Fallthrough>
        jmp     ExitKernel
ENDIF

        ENDM

;++
;
; Routine Description:
;
;   This routine is an inner kernel to compute matrix multiplication for a
;   set of rows.
;
; Arguments:
;
;   A (rcx) - Supplies the address of matrix A.
;
;   B (rdx) - Supplies the address of matrix B. The matrix data has been packed
;       using MlasSgemmCopyPackB or MlasSgemmTransposePackB.
;
;   C (r8) - Supplies the address of matrix C.
;
;   CountK (r9) - Supplies the number of columns from matrix A and the number
;       of rows from matrix B to iterate over.
;
;   CountM - Supplies the maximum number of rows that can be processed for
;       matrix A and matrix C. The actual number of rows handled for this
;       invocation depends on the kernel implementation.
;
;   CountN - Supplies the number of columns from matrix B and matrix C to iterate
;       over.
;
;   lda - Supplies the first dimension of matrix A.
;
;   ldc - Supplies the first dimension of matrix C.
;
;   Alpha - Supplies the scalar alpha multiplier (see SGEMM definition).
;
;   ZeroMode - Supplies true if the output matrix must be zero initialized,
;       else false if the output matrix is accumulated into.
;
; Return Value:
;
;   Returns the number of rows handled.
;
;--

        NESTED_ENTRY MlasGemmFloatKernelAvx, _TEXT

        SgemmKernelAvxEntry

        vbroadcastss ymm2,DWORD PTR SgemmKernelFrame.Alpha[rsp]

;
; Process 4 rows of the matrices.
;

        cmp     r11,4
        jb      ProcessCountMLessThan4
        mov     r11d,4                      ; return 4 rows handled
        ProcessCountM 4, Fallthrough

;
; Restore non-volatile registers and return.
;

ExitKernel:
        vzeroupper
        SgemmKernelAvxExit

;
; Process 2 rows of the matrices.
;

ProcessCountMLessThan4:
        cmp     r11,2
        jb      ProcessCountMLessThan2
        mov     r11d,2                      ; return 2 rows handled
        ProcessCountM 2

;
; Process 1 row of the matrices.
;

ProcessCountMLessThan2:
        ProcessCountM 1

        NESTED_END MlasGemmFloatKernelAvx, _TEXT

;++
;
; Routine Description:
;
;   This routine is an inner kernel to compute matrix multiplication for a
;   set of rows. This handles the special case of M=1.
;
;   The elements in matrix B are not transposed.
;
; Arguments:
;
;   A (rcx) - Supplies the address of matrix A.
;
;   B (rdx) - Supplies the address of matrix B.
;
;   C (r8) - Supplies the address of matrix C.
;
;   CountK (r9) - Supplies the number of columns from matrix A and the number
;       of rows from matrix B to iterate over.
;
;   CountN - Supplies the number of columns from matrix B and matrix C to iterate
;       over.
;
;   ldb - Supplies the first dimension of matrix B.
;
;   Beta - Supplies the scalar beta multiplier (see SGEMM definition).
;
; Return Value:
;
;   None.
;
;--

        NESTED_ENTRY MlasSgemmKernelM1Avx, _TEXT

        rex_push_reg rbp
        push_reg rbx
        push_reg rsi
        alloc_stack (SgemmKernelM1Frame.SavedRsi)
        save_xmm128_avx xmm6,SgemmKernelM1Frame.SavedXmm6
        save_xmm128_avx xmm7,SgemmKernelM1Frame.SavedXmm7
        save_xmm128_avx xmm8,SgemmKernelM1Frame.SavedXmm8

        END_PROLOGUE

        mov     rbx,SgemmKernelM1Frame.ldb[rsp]
        shl     rbx,2                       ; convert ldb to bytes
        mov     r10,r8
        mov     r11,rdx
        mov     rbp,SgemmKernelM1Frame.CountN[rsp]

;
; Compute the initial results mask for zeroing or accumulate mode.
;

        vxorps  xmm0,xmm0,xmm0
        vcmpeqss xmm0,xmm0,DWORD PTR SgemmKernelM1Frame.Beta[rsp]
        vshufps xmm0,xmm0,xmm0,0
        vinsertf128 ymm0,ymm0,xmm0,1

;
; Compute the conditional load/store mask for an unaligned CountN.
;

        mov     eax,ebp
        and     eax,7
        vmovd   xmm7,eax
        vshufps xmm7,xmm7,xmm7,0
        vpcmpgtd xmm6,xmm7,XMMWORD PTR [MlasMaskMoveAvx+16]
        vpcmpgtd xmm7,xmm7,XMMWORD PTR [MlasMaskMoveAvx]
        vinsertf128 ymm7,ymm7,xmm6,1

;
; Process 4 rows of the matrices in a loop.
;

        sub     r9,4
        jb      ProcessRemainingCountK

ProcessRowLoop4:
        vbroadcastss ymm2,DWORD PTR [rcx]
        mov     rax,rbp                     ; reload CountN
        vbroadcastss ymm3,DWORD PTR [rcx+4]
        mov     rdx,r11                     ; reload matrix B
        vbroadcastss ymm4,DWORD PTR [rcx+8]
        mov     r8,r10                      ; reload matrix C
        vbroadcastss ymm5,DWORD PTR [rcx+12]
        add     rcx,4*4                     ; advance matrix A by 4 columns
        lea     r11,[rdx+rbx*4]             ; advance matrix B by 4 rows
        sub     rax,16
        jb      ProcessRemainingCountN4

ProcessColumnLoop4:
        lea     rsi,[rdx+rbx*2]             ; compute matrix B plus 2 rows
        vmulps  ymm1,ymm2,YMMWORD PTR [rdx]
        vmulps  ymm6,ymm2,YMMWORD PTR [rdx+32]
        vmulps  ymm8,ymm3,YMMWORD PTR [rdx+rbx]
        vaddps  ymm1,ymm1,ymm8
        vmulps  ymm8,ymm3,YMMWORD PTR [rdx+rbx+32]
        vaddps  ymm6,ymm6,ymm8
        vmulps  ymm8,ymm4,YMMWORD PTR [rsi]
        vaddps  ymm1,ymm1,ymm8
        vmulps  ymm8,ymm4,YMMWORD PTR [rsi+32]
        vaddps  ymm6,ymm6,ymm8
        vmulps  ymm8,ymm5,YMMWORD PTR [rsi+rbx]
        vaddps  ymm1,ymm1,ymm8
        vmulps  ymm8,ymm5,YMMWORD PTR [rsi+rbx+32]
        vaddps  ymm6,ymm6,ymm8
        vandnps ymm8,ymm0,YMMWORD PTR [r8]
        vaddps  ymm1,ymm1,ymm8
        vandnps ymm8,ymm0,YMMWORD PTR [r8+32]
        vaddps  ymm6,ymm6,ymm8
        vmovups YMMWORD PTR [r8],ymm1
        vmovups YMMWORD PTR [r8+32],ymm6
        add     rdx,16*4                    ; advance matrix B by 16 columns
        add     r8,16*4                     ; advance matrix C by 16 columns
        sub     rax,16
        jae     ProcessColumnLoop4

ProcessRemainingCountN4:
        test    al,15                       ; test for unaligned columns
        jz      ProcessedRemainingCountN4
        test    al,8                        ; CountN >= 8?
        jz      ProcessRemainingCountNSmall4
        lea     rsi,[rdx+rbx*2]             ; compute matrix B plus 2 rows
        vmulps  ymm1,ymm2,YMMWORD PTR [rdx]
        vmulps  ymm8,ymm3,YMMWORD PTR [rdx+rbx]
        vaddps  ymm1,ymm1,ymm8
        vmulps  ymm8,ymm4,YMMWORD PTR [rsi]
        vaddps  ymm1,ymm1,ymm8
        vmulps  ymm8,ymm5,YMMWORD PTR [rsi+rbx]
        vaddps  ymm1,ymm1,ymm8
        vandnps ymm8,ymm0,YMMWORD PTR [r8]
        vaddps  ymm1,ymm1,ymm8
        vmovups YMMWORD PTR [r8],ymm1
        add     rdx,8*4                     ; advance matrix B by 8 columns
        add     r8,8*4                      ; advance matrix C by 8 columns
        test    al,7
        jz      ProcessedRemainingCountN4

ProcessRemainingCountNSmall4:
        lea     rsi,[rdx+rbx*2]             ; compute matrix B plus 2 rows
        vmaskmovps ymm6,ymm7,YMMWORD PTR [rdx]
        vmulps  ymm1,ymm2,ymm6
        vmaskmovps ymm6,ymm7,YMMWORD PTR [rdx+rbx]
        vmulps  ymm8,ymm3,ymm6
        vaddps  ymm1,ymm1,ymm8
        vmaskmovps ymm6,ymm7,YMMWORD PTR [rsi]
        vmulps  ymm8,ymm4,ymm6
        vaddps  ymm1,ymm1,ymm8
        vmaskmovps ymm6,ymm7,YMMWORD PTR [rsi+rbx]
        vmulps  ymm8,ymm5,ymm6
        vaddps  ymm1,ymm1,ymm8
        vmaskmovps ymm6,ymm7,YMMWORD PTR [r8]
        vandnps ymm6,ymm0,ymm6
        vaddps  ymm1,ymm1,ymm6
        vmaskmovps YMMWORD PTR [r8],ymm7,ymm1

ProcessedRemainingCountN4:
        vxorps  xmm0,xmm0,xmm0              ; switch to accumulate mode
        sub     r9,4
        jae     ProcessRowLoop4

ProcessRemainingCountK:
        test    r9d,2
        jnz     ProcessRowLoop2
        test    r9d,1
        jnz     ProcessRowLoop1

ExitKernel:
        vzeroupper
        vmovaps xmm6,SgemmKernelM1Frame.SavedXmm6[rsp]
        vmovaps xmm7,SgemmKernelM1Frame.SavedXmm7[rsp]
        vmovaps xmm8,SgemmKernelM1Frame.SavedXmm8[rsp]
        add     rsp,(SgemmKernelM1Frame.SavedRsi)

        BEGIN_EPILOGUE

        pop     rsi
        pop     rbx
        pop     rbp
        ret

;
; Process 2 rows of the matrices.
;

ProcessRowLoop2:
        vbroadcastss ymm2,DWORD PTR [rcx]
        mov     rax,rbp                     ; reload CountN
        vbroadcastss ymm3,DWORD PTR [rcx+4]
        mov     rdx,r11                     ; reload matrix B
        mov     r8,r10                      ; reload matrix C
        add     rcx,2*4                     ; advance matrix A by 2 columns
        lea     r11,[rdx+rbx*2]             ; advance matrix B by 2 rows
        sub     rax,8
        jb      ProcessRemainingCountN2

ProcessColumnLoop2:
        vmulps  ymm1,ymm2,YMMWORD PTR [rdx]
        vmulps  ymm8,ymm3,YMMWORD PTR [rdx+rbx]
        vaddps  ymm1,ymm1,ymm8
        vandnps ymm6,ymm0,YMMWORD PTR [r8]
        vaddps  ymm1,ymm1,ymm6
        vmovups YMMWORD PTR [r8],ymm1
        add     rdx,8*4                     ; advance matrix B by 8 columns
        add     r8,8*4                      ; advance matrix C by 8 columns
        sub     rax,8
        jae     ProcessColumnLoop2

ProcessRemainingCountN2:
        test    al,7                        ; test for unaligned columns
        jz      ProcessedRemainingCountN2
        vmaskmovps ymm6,ymm7,YMMWORD PTR [rdx]
        vmulps  ymm1,ymm2,ymm6
        vmaskmovps ymm6,ymm7,YMMWORD PTR [rdx+rbx]
        vmulps  ymm8,ymm3,ymm6
        vaddps  ymm1,ymm1,ymm8
        vmaskmovps ymm6,ymm7,YMMWORD PTR [r8]
        vandnps ymm6,ymm0,ymm6
        vaddps  ymm1,ymm1,ymm6
        vmaskmovps YMMWORD PTR [r8],ymm7,ymm1

ProcessedRemainingCountN2:
        test    r9d,1
        jz      ExitKernel
        vxorps  xmm0,xmm0,xmm0              ; switch to accumulate mode

;
; Process 1 row of the matrices.
;

ProcessRowLoop1:
        vbroadcastss ymm2,DWORD PTR [rcx]
        mov     rax,rbp                     ; reload CountN
        mov     rdx,r11                     ; reload matrix B
        mov     r8,r10                      ; reload matrix C
        sub     rax,8
        jb      ProcessRemainingCountN1

ProcessColumnLoop1:
        vmulps  ymm1,ymm2,YMMWORD PTR [rdx]
        vandnps ymm6,ymm0,YMMWORD PTR [r8]
        vaddps  ymm1,ymm1,ymm6
        vmovups YMMWORD PTR [r8],ymm1
        add     rdx,8*4                     ; advance matrix B by 8 columns
        add     r8,8*4                      ; advance matrix C by 8 columns
        sub     rax,8
        jae     ProcessColumnLoop1

ProcessRemainingCountN1:
        test    al,7                        ; test for unaligned columns
        jz      ExitKernel
        vmaskmovps ymm6,ymm7,YMMWORD PTR [rdx]
        vmulps  ymm1,ymm2,ymm6
        vmaskmovps ymm6,ymm7,YMMWORD PTR [r8]
        vandnps ymm6,ymm0,ymm6
        vaddps  ymm1,ymm1,ymm6
        vmaskmovps YMMWORD PTR [r8],ymm7,ymm1
        jmp     ExitKernel

        NESTED_END MlasSgemmKernelM1Avx, _TEXT

;++
;
; Routine Description:
;
;   This routine is an inner kernel to compute matrix multiplication for a
;   set of rows. This handles the special case of M=1.
;
;   The elements in matrix B are transposed.
;
; Arguments:
;
;   A (rcx) - Supplies the address of matrix A.
;
;   B (rdx) - Supplies the address of matrix B. The elements are transposed.
;
;   C (r8) - Supplies the address of matrix C.
;
;   CountK (r9) - Supplies the number of columns from matrix A and the number
;       of columns from matrix B to iterate over.
;
;   CountN - Supplies the number of rows from matrix B and the number of columns
;       from matrix C to iterate over.
;
;   ldb - Supplies the first dimension of matrix B.
;
;   Beta - Supplies the scalar beta multiplier (see SGEMM definition).
;
; Return Value:
;
;   None.
;
;--

        NESTED_ENTRY MlasSgemmKernelM1TransposeBAvx, _TEXT

        rex_push_reg rbp
        push_reg rbx
        push_reg rsi
        alloc_stack (SgemmKernelM1Frame.SavedRsi)
        save_xmm128_avx xmm6,SgemmKernelM1Frame.SavedXmm6
        save_xmm128_avx xmm7,SgemmKernelM1Frame.SavedXmm7

        END_PROLOGUE

        mov     rbx,SgemmKernelM1Frame.ldb[rsp]
        shl     rbx,2                       ; convert ldb to bytes
        mov     r10,rcx
        mov     r11,rdx
        mov     rbp,SgemmKernelM1Frame.CountN[rsp]

;
; Compute the results mask for zeroing or accumulate mode.
;

        vxorps  xmm0,xmm0,xmm0
        vcmpeqss xmm0,xmm0,DWORD PTR SgemmKernelM1Frame.Beta[rsp]
        vshufps xmm0,xmm0,xmm0,0

;
; Compute the conditional load/store mask for an unaligned CountK.
;

        mov     eax,r9d
        and     eax,7
        vmovd   xmm7,eax
        vshufps xmm7,xmm7,xmm7,0
        vpcmpgtd xmm6,xmm7,XMMWORD PTR [MlasMaskMoveAvx+16]
        vpcmpgtd xmm7,xmm7,XMMWORD PTR [MlasMaskMoveAvx]
        vinsertf128 ymm7,ymm7,xmm6,1

;
; Process 4 rows of the matrices in a loop.
;

        sub     rbp,4
        jb      ProcessRemainingCountN

ProcessRowLoop4:
        vxorps  xmm2,xmm2,xmm2              ; clear row accumulators
        vxorps  xmm3,xmm3,xmm3
        vxorps  xmm4,xmm4,xmm4
        vxorps  xmm5,xmm5,xmm5
        mov     rcx,r10                     ; reload matrix A
        mov     rdx,r11                     ; reload matrix B
        mov     rax,r9                      ; reload CountK
        lea     r11,[rdx+rbx*4]             ; advance matrix B by 4 rows
        sub     rax,8
        jb      ProcessRemainingCountK4

ProcessColumnLoop4:
        lea     rsi,[rdx+rbx*2]             ; compute matrix B plus 2 rows
        vmovups ymm1,YMMWORD PTR [rcx]
        vmulps  ymm6,ymm1,YMMWORD PTR [rdx]
        vaddps  ymm2,ymm2,ymm6
        vmulps  ymm6,ymm1,YMMWORD PTR [rdx+rbx]
        vaddps  ymm3,ymm3,ymm6
        vmulps  ymm6,ymm1,YMMWORD PTR [rsi]
        vaddps  ymm4,ymm4,ymm6
        vmulps  ymm6,ymm1,YMMWORD PTR [rsi+rbx]
        vaddps  ymm5,ymm5,ymm6
        add     rcx,8*4                     ; advance matrix A by 8 columns
        add     rdx,8*4                     ; advance matrix B by 8 columns
        sub     rax,8
        jae     ProcessColumnLoop4

ProcessRemainingCountK4:
        test    al,7                        ; test for unaligned columns
        jz      Output4x1Block
        lea     rsi,[rdx+rbx*2]             ; compute matrix B plus 2 rows
        vmaskmovps ymm1,ymm7,YMMWORD PTR [rcx]
        vmaskmovps ymm6,ymm7,YMMWORD PTR [rdx]
        vmulps  ymm6,ymm1,ymm6
        vaddps  ymm2,ymm2,ymm6
        vmaskmovps ymm6,ymm7,YMMWORD PTR [rdx+rbx]
        vmulps  ymm6,ymm1,ymm6
        vaddps  ymm3,ymm3,ymm6
        vmaskmovps ymm6,ymm7,YMMWORD PTR [rsi]
        vmulps  ymm6,ymm1,ymm6
        vaddps  ymm4,ymm4,ymm6
        vmaskmovps ymm6,ymm7,YMMWORD PTR [rsi+rbx]
        vmulps  ymm6,ymm1,ymm6
        vaddps  ymm5,ymm5,ymm6

;
; Reduce and output the row accumulators.
;

Output4x1Block:
        vunpcklps ymm6,ymm2,ymm3            ; transpose row accumulators
        vunpckhps ymm1,ymm2,ymm3
        vunpcklps ymm2,ymm4,ymm5
        vunpckhps ymm3,ymm4,ymm5
        vunpcklpd ymm4,ymm6,ymm2
        vunpckhpd ymm5,ymm6,ymm2
        vaddps  ymm4,ymm4,ymm5
        vunpcklpd ymm6,ymm1,ymm3
        vunpckhpd ymm2,ymm1,ymm3
        vaddps  ymm4,ymm4,ymm6
        vaddps  ymm4,ymm4,ymm2
        vextractf128 xmm5,ymm4,1
        vaddps  xmm4,xmm4,xmm5
        vandnps xmm6,xmm0,XMMWORD PTR [r8]
        vaddps  xmm4,xmm4,xmm6
        vmovups XMMWORD PTR [r8],xmm4
        add     r8,4*4                      ; advance matrix C by 4 columns
        sub     rbp,4
        jae     ProcessRowLoop4

ProcessRemainingCountN:
        test    ebp,2
        jnz     ProcessRowLoop2
        test    ebp,1
        jnz     ProcessRowLoop1

ExitKernel:
        vzeroupper
        vmovaps xmm6,SgemmKernelM1Frame.SavedXmm6[rsp]
        vmovaps xmm7,SgemmKernelM1Frame.SavedXmm7[rsp]
        add     rsp,(SgemmKernelM1Frame.SavedRsi)

        BEGIN_EPILOGUE

        pop     rsi
        pop     rbx
        pop     rbp
        ret

;
; Process 2 rows of the matrices.
;

ProcessRowLoop2:
        vxorps  xmm2,xmm2,xmm2              ; clear row accumulators
        vxorps  xmm3,xmm3,xmm3
        mov     rcx,r10                     ; reload matrix A
        mov     rdx,r11                     ; reload matrix B
        mov     rax,r9                      ; reload CountK
        lea     r11,[rdx+rbx*2]             ; advance matrix B by 2 rows
        sub     rax,8
        jb      ProcessRemainingCountK2

ProcessColumnLoop2:
        vmovups ymm1,YMMWORD PTR [rcx]
        vmulps  ymm6,ymm1,YMMWORD PTR [rdx]
        vaddps  ymm2,ymm2,ymm6
        vmulps  ymm6,ymm1,YMMWORD PTR [rdx+rbx]
        vaddps  ymm3,ymm3,ymm6
        add     rcx,8*4                     ; advance matrix A by 8 columns
        add     rdx,8*4                     ; advance matrix B by 8 columns
        sub     rax,8
        jae     ProcessColumnLoop2

ProcessRemainingCountK2:
        test    al,7                        ; test for unaligned columns
        jz      Output2x1Block
        vmaskmovps ymm1,ymm7,YMMWORD PTR [rcx]
        vmaskmovps ymm6,ymm7,YMMWORD PTR [rdx]
        vmulps  ymm6,ymm1,ymm6
        vaddps  ymm2,ymm2,ymm6
        vmaskmovps ymm6,ymm7,YMMWORD PTR [rdx+rbx]
        vmulps  ymm6,ymm1,ymm6
        vaddps  ymm3,ymm3,ymm6

;
; Reduce and output the row accumulators.
;

Output2x1Block:
        vunpcklps ymm4,ymm2,ymm3            ; reduce row accumulators
        vunpckhps ymm2,ymm2,ymm3
        vaddps  ymm2,ymm2,ymm4
        vextractf128 xmm4,ymm2,1
        vaddps  xmm2,xmm2,xmm4
        vmovhlps xmm4,xmm2,xmm2
        vaddps  xmm2,xmm2,xmm4
        vmovsd  xmm3,QWORD PTR [r8]
        vandnps xmm3,xmm0,xmm3
        vaddps  xmm2,xmm2,xmm3
        vmovsd  QWORD PTR [r8],xmm2
        add     r8,2*4                      ; advance matrix C by 2 columns
        test    ebp,1
        jz      ExitKernel

;
; Process 1 row of the matrices.
;

ProcessRowLoop1:
        vxorps  xmm2,xmm2,xmm2              ; clear row accumulators
        mov     rcx,r10                     ; reload matrix A
        mov     rdx,r11                     ; reload matrix B
        mov     rax,r9                      ; reload CountK
        sub     rax,8
        jb      ProcessRemainingCountK1

ProcessColumnLoop1:
        vmovups ymm1,YMMWORD PTR [rcx]
        vmulps  ymm6,ymm1,YMMWORD PTR [rdx]
        vaddps  ymm2,ymm2,ymm6
        add     rcx,8*4                     ; advance matrix A by 8 columns
        add     rdx,8*4                     ; advance matrix B by 8 columns
        sub     rax,8
        jae     ProcessColumnLoop1

ProcessRemainingCountK1:
        test    al,7                        ; test for unaligned columns
        jz      Output1x1Block
        vmaskmovps ymm1,ymm7,YMMWORD PTR [rcx]
        vmaskmovps ymm6,ymm7,YMMWORD PTR [rdx]
        vmulps  ymm6,ymm1,ymm6
        vaddps  ymm2,ymm2,ymm6

;
; Reduce and output the row accumulators.
;

Output1x1Block:
        vhaddps ymm2,ymm2,ymm2              ; reduce row accumulators
        vhaddps ymm2,ymm2,ymm2
        vextractf128 xmm4,ymm2,1
        vaddss  xmm2,xmm2,xmm4
        vmovss  xmm3,DWORD PTR [r8]
        vandnps xmm3,xmm0,xmm3
        vaddss  xmm2,xmm2,xmm3
        vmovss  DWORD PTR [r8],xmm2
        jmp     ExitKernel

        NESTED_END MlasSgemmKernelM1TransposeBAvx, _TEXT

        END
