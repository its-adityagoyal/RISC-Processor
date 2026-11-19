; insertion -- insertion sort (reference sorting program)
; Layout: N signed words at dmem[0..N-1], sorted in place (ascending)
; Convention: r0 == 0

        .text
        ADDI r1, r0, 1           ; i = 1
        ADDI r2, r0, N
        ADDI r8, r0, 1           ; constant 1
        ADDI r9, r0, -1          ; constant -1
outer:
        SLT  r6, r1, r2          ; i < N ?
        BZ   r6, done
        LD   r4, 0(r1)           ; key = a[i]
        ADD  r3, r1, r9          ; j = i - 1
inner:
        SLT  r6, r3, r0          ; j < 0 ?
        SUB  r7, r8, r6
        BZ   r7, insert
        LD   r5, 0(r3)           ; a[j]
        SGT  r6, r5, r4
        BZ   r6, insert          ; a[j] <= key
        ADD  r7, r3, r8
        ST   r5, 0(r7)           ; a[j+1] = a[j]
        ADD  r3, r3, r9          ; j--
        BR   inner
insert:
        ADD  r7, r3, r8
        ST   r4, 0(r7)           ; a[j+1] = key
        ADD  r1, r1, r8          ; i++
        BR   outer
done:
        HALT
