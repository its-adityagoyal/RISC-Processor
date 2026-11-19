; bitcount -- population count three ways
; Derived from MiBench automotive/bitcount (Kernighan "sparse ones" and
; shift-and-test methods), plus the MiniRISC HAM instruction for reference.
; Input : N words at dmem[0..N-1]
; Output: dmem[RES]   = total via Kernighan  (x &= x-1)
;         dmem[RES+1] = total via shift-and-test
;         dmem[RES+2] = total via HAM
; Convention: r0 == 0

        .equ RES, 250
        .text
        ADDI r1, r0, 0           ; i
        ADDI r2, r0, N
        ADDI r3, r0, 0           ; Kernighan total
        ADDI r4, r0, 0           ; shifter total
        ADDI r12, r0, 0          ; HAM total
loop:
        LD   r5, 0(r1)
        MOVE r6, r5
k_loop:                          ; while (x) { x &= x - 1; cnt++; }
        BZ   r6, k_done
        DEC  r7, r6
        AND  r6, r6, r7
        INC  r3, r3
        BR   k_loop
k_done:
        MOVE r6, r5
s_loop:                          ; while (x) { cnt += x & 1; x >>= 1; }
        BZ   r6, s_done
        ANDI r7, r6, 1
        ADD  r4, r4, r7
        SRLI r6, r6, 1
        BR   s_loop
s_done:
        HAM  r8, r5
        ADD  r12, r12, r8
        INC  r1, r1
        SUB  r9, r2, r1
        BPL  r9, loop
        ST   r3, RES(r0)
        ST   r4, RES+1(r0)
        ST   r12, RES+2(r0)
        HALT
