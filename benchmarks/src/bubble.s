; bubble -- bubble sort (reference sorting program)
; Layout: N signed words at dmem[0..N-1], sorted in place (ascending)
; Convention: r0 == 0

        .text
        ADDI r1, r0, 0           ; i = 0
        ADDI r2, r0, N-1
outer:
        SLT  r9, r1, r2          ; i < N-1 ?
        BZ   r9, done
        ADDI r3, r0, 0           ; j = 0
        SUB  r4, r2, r1          ; N-1-i
inner:
        SLT  r9, r3, r4          ; j < N-1-i ?
        BZ   r9, next_i
        LD   r6, 0(r3)           ; a[j]
        ADDI r7, r3, 1
        LD   r8, 0(r7)           ; a[j+1]
        SGT  r9, r6, r8
        BZ   r9, no_swap
        ST   r8, 0(r3)
        ST   r6, 0(r7)
no_swap:
        ADDI r3, r3, 1
        BR   inner
next_i:
        ADDI r1, r1, 1
        BR   outer
done:
        HALT
