; bsearch -- binary search of M keys in a sorted array of N words
; Derived from TACLeBench "binarysearch" and BEEBS "bs".
; Layout: sorted array at dmem[0..N-1], keys at dmem[KEYS..KEYS+M-1],
;         result index (or -1 if absent) at dmem[OUT..OUT+M-1]
; Convention: r0 == 0

        .equ KEYS, 64
        .equ OUT, 128
        .text
        ADDI r1, r0, 0           ; query index q
q_loop:
        LD   r2, KEYS(r1)        ; key
        ADDI r3, r0, 0           ; lo
        ADDI r4, r0, N-1         ; hi
        ADDI r5, r0, -1          ; result = not found
s_loop:
        SUB  r6, r4, r3
        BMI  r6, s_done          ; lo > hi
        ADD  r7, r3, r4
        SRLI r7, r7, 1           ; mid
        LD   r8, 0(r7)
        SUB  r9, r8, r2          ; a[mid] - key
        BZ   r9, found
        BMI  r9, go_right
        DEC  r4, r7              ; hi = mid - 1
        BR   s_loop
go_right:
        INC  r3, r7              ; lo = mid + 1
        BR   s_loop
found:
        MOVE r5, r7
s_done:
        ST   r5, OUT(r1)
        INC  r1, r1
        SUBI r6, r1, M
        BMI  r6, q_loop
        HALT
