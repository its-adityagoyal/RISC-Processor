; sieve -- Sieve of Eratosthenes
; The classic BYTE-magazine sieve benchmark (Gilbreath, 1981).
; Layout: flags at dmem[0..SIZE-1] (1 = composite), prime count at dmem[RES]
; Convention: r0 == 0

        .equ SIZE, 240
        .equ RES, 250
        .text
        ADDI r1, r0, 2           ; i
        ADDI r2, r0, SIZE-1
        ADDI r3, r0, 0           ; prime count
        ADDI r9, r0, 1           ; constant 1
i_loop:
        LD   r4, 0(r1)
        BPL  r4, next_i          ; already marked composite
        INC  r3, r3
        ADD  r5, r1, r1          ; j = 2i
j_loop:
        SUB  r6, r5, r2
        BPL  r6, next_i          ; j >= SIZE
        ST   r9, 0(r5)           ; mark composite
        ADD  r5, r5, r1
        BR   j_loop
next_i:
        INC  r1, r1
        SUB  r6, r1, r2
        BPL  r6, done            ; i >= SIZE
        BR   i_loop
done:
        ST   r3, RES(r0)
        HALT
