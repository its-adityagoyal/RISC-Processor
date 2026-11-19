; matmult -- integer matrix multiply C = A x B, N = 8
; Derived from Embench-IoT "matmult-int" and PolyBench "gemm".
; MiniRISC has no multiply instruction, so the inner product uses an
; inlined shift-and-add multiply (operands are non-negative).
; Layout: A at dmem[0..63], B at dmem[64..127], C at dmem[128..191]
; Convention: r0 == 0

        .equ N, 8
        .equ A, 0
        .equ B, 64
        .equ C, 128
        .text
        ADDI r1, r0, 0           ; i
i_loop:
        ADDI r2, r0, 0           ; j
j_loop:
        ADDI r12, r0, 0          ; sum
        ADDI r3, r0, 0           ; k
        SLAI r4, r1, 3           ; i * N
        ADDI r5, r2, B           ; &B[0][j]
k_loop:
        ADD  r6, r4, r3
        LD   r10, A(r6)          ; multiplicand A[i][k]
        LD   r11, 0(r5)          ; multiplier   B[k][j]
mul_loop:                        ; sum += r10 * r11 (shift-and-add)
        BZ   r11, mul_done
        ANDI r13, r11, 1
        BZ   r13, mul_skip
        ADD  r12, r12, r10
mul_skip:
        SLAI r10, r10, 1
        SRLI r11, r11, 1
        BR   mul_loop
mul_done:
        ADDI r5, r5, N           ; next row of B
        INC  r3, r3
        SUBI r7, r3, N
        BMI  r7, k_loop
        SLAI r8, r1, 3
        ADD  r8, r8, r2
        ST   r12, C(r8)
        INC  r2, r2
        SUBI r7, r2, N
        BMI  r7, j_loop
        INC  r1, r1
        SUBI r7, r1, N
        BMI  r7, i_loop
        HALT
