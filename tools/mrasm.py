#!/usr/bin/env python3
"""MiniRISC assembler and instruction-set simulator.

Assembler syntax (one statement per line, ';' or '#' starts a comment):

    .text / .data         select section
    .org  N               set the location counter (word address)
    .equ  NAME, value     define a constant
    .word v, v, ...       emit data words (.data only)
    .space N              reserve N zero words (.data only)
    label:                define a label at the current address

    R3   ADD SUB SLT SGT AND OR XOR NOR CMOV   rd, rs, rt
    R2   INC DEC NOT HAM MOVE                  rd, rs
    RSH  SL SRL SRA                            rd, rs, shamt
    I    ADDI SUBI ANDI ORI XORI NORI          rt, rs, imm16
         SLAI SRLI SRAI                        rt, rs, shamt
         LUI                                   rt, imm16
    MEM  LD ST                                 rt, imm16(rs)
    BR   BZ BMI BPL                            rs, label     (PC-relative)
         BR                                    label         (absolute)
         HALT NOP
    pseudo  LI rt, imm32   (ADDI from r0, or LUI+ADDI; assumes r0 == 0)
            MOV rd, rs     (= MOVE)

ISA semantics follow tb_pkg.sv / the ISA_MiniRISC report: every 16-bit
immediate is sign-extended, R-type shifts use shamt, BR is absolute.
"""
from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field

MEM_WORDS = 256
MASK32 = 0xFFFF_FFFF

FUNCT = {
    "ADD": 0b001000, "SUB": 0b001001, "INC": 0b001010, "DEC": 0b001011,
    "SLT": 0b001100, "SGT": 0b001101, "AND": 0b010000, "OR": 0b010001,
    "XOR": 0b010010, "NOR": 0b010011, "NOT": 0b010100, "SL": 0b011000,
    "SRL": 0b011001, "SRA": 0b011010, "HAM": 0b100000, "MOVE": 0b101000,
    "CMOV": 0b101001,
}
OPCODE = {
    "ADDI": 0b001000, "SUBI": 0b001001, "ANDI": 0b010000, "ORI": 0b010001,
    "XORI": 0b010010, "NORI": 0b010011, "SLAI": 0b011000, "SRLI": 0b011001,
    "SRAI": 0b011010, "LUI": 0b100001, "LD": 0b101010, "ST": 0b101011,
    "BR": 0b110000, "BMI": 0b110001, "BPL": 0b110010, "BZ": 0b110011,
    "HALT": 0b111000, "NOP": 0b111001,
}
R3 = {"ADD", "SUB", "SLT", "SGT", "AND", "OR", "XOR", "NOR", "CMOV"}
R2 = {"INC", "DEC", "NOT", "HAM", "MOVE"}
RSH = {"SL", "SRL", "SRA"}
ITYPE = {"ADDI", "SUBI", "ANDI", "ORI", "XORI", "NORI", "SLAI", "SRLI", "SRAI"}
BCOND = {"BZ", "BMI", "BPL"}
NAME_OF_FUNCT = {v: k for k, v in FUNCT.items()}
NAME_OF_OPCODE = {v: k for k, v in OPCODE.items()}


class AsmError(Exception):
    pass


def sext(v: int, bits: int) -> int:
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def s32(v: int) -> int:
    return sext(v, 32)


def enc_r(funct: int, rd: int, rs: int, rt: int, shamt: int = 0) -> int:
    return (rs << 22) | (rt << 18) | (rd << 14) | ((shamt & 31) << 9) | (funct << 3)


def enc_i(op: int, rt: int, rs: int, imm: int) -> int:
    return (op << 26) | (rs << 22) | (rt << 18) | ((imm & 0xFFFF) << 2)


def enc_j(op: int, imm26: int) -> int:
    return (op << 26) | (imm26 & 0x3FF_FFFF)


def mnemonic(insn: int) -> str:
    op = insn >> 26
    if op == 0:
        return NAME_OF_FUNCT.get((insn >> 3) & 63, "R-UNDEF")
    return NAME_OF_OPCODE.get(op, "UNDEF")


# --------------------------------------------------------------- assembler
@dataclass
class Image:
    imem: list[int] = field(default_factory=lambda: [OPCODE["HALT"] << 26] * MEM_WORDS)
    dmem: list[int] = field(default_factory=lambda: [0] * MEM_WORDS)
    symbols: dict[str, int] = field(default_factory=dict)
    listing: list[str] = field(default_factory=list)
    text_len: int = 0


def _strip(line: str) -> str:
    return re.split(r"[;#]", line, maxsplit=1)[0].strip()


def _split_ops(rest: str) -> list[str]:
    return [t.strip() for t in rest.split(",")] if rest.strip() else []


class Assembler:
    def __init__(self, src: str, name: str = "<asm>"):
        self.src = src
        self.name = name
        self.sym: dict[str, int] = {}
        self.li_size: dict[int, int] = {}   # line -> words, fixed in pass 1

    # expression: terms joined by + / - ; terms are ints or symbols
    def value(self, expr: str, lineno: int) -> int:
        expr = expr.replace(" ", "")
        if not expr:
            raise AsmError(f"{self.name}:{lineno}: empty expression")
        total, sign, tok = 0, 1, ""
        for ch in expr + "+":
            if ch in "+-" and tok:
                total += sign * self._term(tok, lineno)
                sign, tok = (1 if ch == "+" else -1), ""
            elif ch in "+-":
                sign = -sign if ch == "-" else sign
            else:
                tok += ch
        return total

    def _term(self, tok: str, lineno: int) -> int:
        try:
            return int(tok, 0)
        except ValueError:
            if tok in self.sym:
                return self.sym[tok]
            raise AsmError(f"{self.name}:{lineno}: unknown symbol '{tok}'")

    @staticmethod
    def reg(tok: str, lineno: int, name: str) -> int:
        m = re.fullmatch(r"[rR](\d+)", tok.strip())
        if not m or not 0 <= int(m.group(1)) <= 15:
            raise AsmError(f"{name}:{lineno}: bad register '{tok}'")
        return int(m.group(1))

    def imm16(self, expr: str, lineno: int) -> int:
        v = self.value(expr, lineno)
        if not -0x8000 <= v <= 0xFFFF:
            raise AsmError(f"{self.name}:{lineno}: immediate {v} does not fit in 16 bits")
        return v & 0xFFFF

    @staticmethod
    def _size(mn: str, ops: list[str], value) -> int:
        if mn == "LI":
            try:
                v = value(ops[1])
            except AsmError:
                return 2          # forward reference: assume worst case
            return 1 if -0x8000 <= v <= 0x7FFF else 2
        return 1

    def assemble(self) -> Image:
        lines = self.src.splitlines()
        # ---- pass 1: symbols
        sec, loc = "text", {"text": 0, "data": 0}
        for n, raw in enumerate(lines, 1):
            line = _strip(raw)
            while (m := re.match(r"^([A-Za-z_]\w*):\s*(.*)$", line)):
                if m.group(1) in self.sym:
                    raise AsmError(f"{self.name}:{n}: duplicate label '{m.group(1)}'")
                self.sym[m.group(1)] = loc[sec]
                line = m.group(2)
            if not line:
                continue
            mn, _, rest = line.partition(" ")
            mn = mn.upper()
            ops = _split_ops(rest)
            if mn == ".TEXT": sec = "text"
            elif mn == ".DATA": sec = "data"
            elif mn == ".ORG": loc[sec] = self.value(ops[0], n)
            elif mn == ".EQU": self.sym[ops[0]] = self.value(ops[1], n)
            elif mn == ".WORD": loc[sec] += len(ops)
            elif mn == ".SPACE": loc[sec] += self.value(ops[0], n)
            else:
                size = self._size(mn, ops, lambda e: self.value(e, n))
                if mn == "LI":
                    self.li_size[n] = size
                loc[sec] += size
        # ---- pass 2: encode
        img = Image(symbols=dict(self.sym))
        sec, loc = "text", {"text": 0, "data": 0}
        for n, raw in enumerate(lines, 1):
            line = _strip(raw)
            while (m := re.match(r"^([A-Za-z_]\w*):\s*(.*)$", line)):
                line = m.group(2)
            if not line:
                continue
            mn, _, rest = line.partition(" ")
            mn = mn.upper()
            ops = _split_ops(rest)
            if mn == ".TEXT": sec = "text"; continue
            if mn == ".DATA": sec = "data"; continue
            if mn == ".ORG": loc[sec] = self.value(ops[0], n); continue
            if mn == ".EQU": continue
            if mn in (".WORD", ".SPACE"):
                if sec != "data":
                    raise AsmError(f"{self.name}:{n}: {mn} only allowed in .data")
                vals = [self.value(o, n) for o in ops] if mn == ".WORD" else [0] * self.value(ops[0], n)
                for v in vals:
                    self._put(img.dmem, loc["data"], v & MASK32, n)
                    loc["data"] += 1
                continue
            if sec != "text":
                raise AsmError(f"{self.name}:{n}: instruction in .data")
            for word in self.encode(mn, ops, loc["text"], n):
                self._put(img.imem, loc["text"], word, n)
                img.listing.append(f"{loc['text']:3d}  {word:08x}  {raw.strip()}")
                loc["text"] += 1
            img.text_len = max(img.text_len, loc["text"])
        return img

    def _put(self, mem: list[int], addr: int, word: int, n: int) -> None:
        if not 0 <= addr < MEM_WORDS:
            raise AsmError(f"{self.name}:{n}: address {addr} outside 0..{MEM_WORDS - 1}")
        mem[addr] = word

    def encode(self, mn: str, ops: list[str], pc: int, n: int) -> list[int]:
        def R(t: str) -> int:
            return self.reg(t, n, self.name)

        def need(k: int) -> None:
            if len(ops) != k:
                raise AsmError(f"{self.name}:{n}: {mn} expects {k} operand(s), got {len(ops)}")

        if mn in R3:
            need(3); return [enc_r(FUNCT[mn], R(ops[0]), R(ops[1]), R(ops[2]))]
        if mn in R2:
            need(2); return [enc_r(FUNCT[mn], R(ops[0]), R(ops[1]), 0)]
        if mn == "MOV":
            need(2); return [enc_r(FUNCT["MOVE"], R(ops[0]), R(ops[1]), 0)]
        if mn in RSH:
            need(3)
            sh = self.value(ops[2], n)
            if not 0 <= sh <= 31:
                raise AsmError(f"{self.name}:{n}: shift amount {sh} out of range")
            return [enc_r(FUNCT[mn], R(ops[0]), R(ops[1]), 0, sh)]
        if mn in ITYPE:
            need(3); return [enc_i(OPCODE[mn], R(ops[0]), R(ops[1]), self.imm16(ops[2], n))]
        if mn == "LUI":
            need(2); return [enc_i(OPCODE[mn], R(ops[0]), 0, self.imm16(ops[1], n))]
        if mn in ("LD", "ST"):
            need(2)
            m = re.fullmatch(r"(.*)\(\s*([rR]\d+)\s*\)", ops[1].strip())
            if not m:
                raise AsmError(f"{self.name}:{n}: expected imm(rs), got '{ops[1]}'")
            off = self.imm16(m.group(1) or "0", n)
            return [enc_i(OPCODE[mn], R(ops[0]), R(m.group(2)), off)]
        if mn in BCOND:
            need(2)
            off = self.value(ops[1], n) - pc
            if not -0x8000 <= off <= 0x7FFF:
                raise AsmError(f"{self.name}:{n}: branch offset {off} out of range")
            return [enc_i(OPCODE[mn], 0, R(ops[0]), off)]
        if mn == "BR":
            need(1); return [enc_j(OPCODE["BR"], self.value(ops[0], n))]
        if mn in ("HALT", "NOP"):
            need(0); return [OPCODE[mn] << 26]
        if mn == "LI":
            need(2)
            rt, v = R(ops[0]), self.value(ops[1], n) & MASK32
            sv = s32(v)
            if self.li_size[n] == 1:
                return [enc_i(OPCODE["ADDI"], rt, 0, sv)]
            lo = sext(v & 0xFFFF, 16)
            hi = ((v - lo) >> 16) & 0xFFFF       # compensate for sign-extended lo
            return [enc_i(OPCODE["LUI"], rt, 0, hi), enc_i(OPCODE["ADDI"], rt, rt, lo)]
        raise AsmError(f"{self.name}:{n}: unknown mnemonic '{mn}'")


def assemble(src: str, name: str = "<asm>") -> Image:
    return Assembler(src, name).assemble()


# --------------------------------------------------------------------- ISS
@dataclass
class RunStats:
    retired: int = 0
    branches: int = 0          # conditional branches
    taken: int = 0
    jumps: int = 0
    per_insn: dict[str, int] = field(default_factory=dict)


class ISS:
    """Instruction-accurate reference model (independent of the SV model)."""

    def __init__(self, img: Image):
        self.imem = list(img.imem)
        self.dmem = list(img.dmem)
        self.regs = [0] * 16
        self.pc = 0
        self.halted = False
        self.stats = RunStats()

    def step(self) -> None:
        w = self.imem[self.pc & 0xFF]
        op, rs, rt, rd = w >> 26, (w >> 22) & 15, (w >> 18) & 15, (w >> 14) & 15
        sh, fn = (w >> 9) & 31, (w >> 3) & 63
        imm = sext((w >> 2) & 0xFFFF, 16) & MASK32
        a, b = self.regs[rs], self.regs[rt]
        npc = (self.pc + 1) & MASK32
        st = self.stats
        mn = mnemonic(w)
        st.retired += 1
        st.per_insn[mn] = st.per_insn.get(mn, 0) + 1
        wr = None
        if op == 0:
            res = {
                "ADD": a + b, "SUB": a - b, "INC": a + 1, "DEC": a - 1,
                "SLT": int(s32(a) < s32(b)), "SGT": int(s32(a) > s32(b)),
                "AND": a & b, "OR": a | b, "XOR": a ^ b, "NOR": ~(a | b), "NOT": ~a,
                "SL": a << sh, "SRL": a >> sh, "SRA": s32(a) >> sh,
                "HAM": bin(a).count("1"), "MOVE": a, "CMOV": a if s32(a) < s32(b) else b,
            }.get(mn)
            if res is None:
                raise RuntimeError(f"undefined R-type funct {fn:06b} at pc {self.pc}")
            wr = (rd, res)
        elif mn in ITYPE or mn == "LUI":
            res = {
                "ADDI": a + imm, "SUBI": a - imm, "ANDI": a & imm, "ORI": a | imm,
                "XORI": a ^ imm, "NORI": ~(a | imm), "SLAI": a << (imm & 31),
                "SRLI": a >> (imm & 31), "SRAI": s32(a) >> (imm & 31),
                "LUI": ((w >> 2) & 0xFFFF) << 16,
            }[mn]
            wr = (rt, res)
        elif mn == "LD":
            wr = (rt, self.dmem[(a + imm) & 0xFF])
        elif mn == "ST":
            self.dmem[(a + imm) & 0xFF] = b
        elif mn == "BR":
            npc = sext(w & 0x3FF_FFFF, 26) & MASK32
            st.jumps += 1
        elif mn in BCOND:
            st.branches += 1
            take = {"BZ": a == 0, "BMI": s32(a) < 0, "BPL": s32(a) > 0}[mn]
            if take:
                st.taken += 1
                npc = (self.pc + imm) & MASK32
        elif mn == "HALT":
            self.halted = True
            npc = self.pc
        elif mn == "NOP":
            pass
        else:
            raise RuntimeError(f"undefined opcode {op:06b} at pc {self.pc}")
        if wr is not None:
            self.regs[wr[0]] = wr[1] & MASK32
        self.pc = npc

    def run(self, max_steps: int = 5_000_000) -> RunStats:
        while not self.halted:
            if self.stats.retired >= max_steps:
                raise RuntimeError(f"no HALT within {max_steps} instructions")
            self.step()
        return self.stats


def write_hex(path: str, words: list[int]) -> None:
    with open(path, "w") as f:
        f.write("".join(f"{w & MASK32:08x}\n" for w in words))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: mrasm.py file.s")
    image = assemble(open(sys.argv[1]).read(), sys.argv[1])
    print("\n".join(image.listing))
    s = ISS(image).run()
    print(f"retired={s.retired} branches={s.branches} taken={s.taken} jumps={s.jumps}")
