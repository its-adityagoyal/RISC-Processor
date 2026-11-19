; crc32 -- bitwise CRC-32 (reflected, poly 0xEDB88320)
; Derived from Embench-IoT "crc32" and MiBench telecomm/CRC32.
; No table: a 256-entry table would fill the whole 256-word data memory.
; Input : N words at dmem[0..N-1], each word = 4 bytes, little-endian
; Output: dmem[RES] = crc32(bytes)      (checked against Python binascii.crc32)
; Convention: r0 == 0 (never written)

        .equ RES, 255
        .text
        LI   r1, 0xFFFFFFFF      ; crc = ~0
        LI   r2, 0xEDB88320      ; polynomial
        ADDI r3, r0, 0           ; word index
        ADDI r4, r0, N           ; word count (N defined by the build script)
word_loop:
        LD   r5, 0(r3)
        ADDI r6, r0, 4           ; bytes left in this word
byte_loop:
        ANDI r7, r5, 255
        XOR  r1, r1, r7
        SRLI r5, r5, 8
        ADDI r8, r0, 8           ; bits left
bit_loop:
        ANDI r9, r1, 1
        SRLI r1, r1, 1
        BZ   r9, no_xor          ; data-dependent: ~50% taken
        XOR  r1, r1, r2
no_xor:
        SUBI r8, r8, 1
        BPL  r8, bit_loop
        SUBI r6, r6, 1
        BPL  r6, byte_loop
        ADDI r3, r3, 1
        SUB  r10, r4, r3
        BPL  r10, word_loop
        NOT  r1, r1
        ST   r1, RES(r0)
        HALT
