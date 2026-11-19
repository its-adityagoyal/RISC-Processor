#!/usr/bin/env python3
"""Build the MiniRISC benchmark suite.

For every benchmark this script
  1. generates the input data (fixed seed, reproducible),
  2. computes the expected output NATIVELY in Python (binascii.crc32, bisect,
     sorted(), ...) -- independent of any MiniRISC model,
  3. assembles the kernel (benchmarks/src/<kernel>.s) with the data appended,
  4. runs the Python ISS and checks its final memory against (2),
  5. writes build/<name>.imem.hex, .dmem.hex, .expect, .lst
     and build/summary.csv (dynamic instruction mix and branch statistics).

The .expect file lists "<addr> <hex>" pairs that the RTL testbench checks.
"""
from __future__ import annotations

import binascii
import bisect
import csv
import random
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "tools"))
from mrasm import ISS, MASK32, assemble, write_hex  # noqa: E402

SRC = HERE / "src"
OUT = HERE / "build"
SEED = 2026


def data_section(words: dict[int, int]) -> str:
    lines = ["", "        .data"]
    for addr in sorted(words):
        lines.append(f"        .org {addr}")
        lines.append(f"        .word {words[addr] & MASK32:#x}")
    return "\n".join(lines) + "\n"


def bench_crc32(rng: random.Random):
    n = 32
    words = [rng.getrandbits(32) for _ in range(n)]
    raw = b"".join(struct.pack("<I", w) for w in words)
    expect = {255: binascii.crc32(raw) & MASK32}
    return "crc32", {"N": n}, dict(enumerate(words)), expect


def bench_bitcount(rng: random.Random):
    n = 48
    words = [rng.getrandbits(32) for _ in range(n)]
    total = sum(bin(w).count("1") for w in words)
    return "bitcount", {"N": n}, dict(enumerate(words)), {250: total, 251: total, 252: total}


def bench_matmult(rng: random.Random):
    n = 8
    a = [[rng.randrange(100) for _ in range(n)] for _ in range(n)]
    b = [[rng.randrange(100) for _ in range(n)] for _ in range(n)]
    data = {}
    for i in range(n):
        for j in range(n):
            data[i * n + j] = a[i][j]
            data[64 + i * n + j] = b[i][j]
    expect = {128 + i * n + j: sum(a[i][k] * b[k][j] for k in range(n)) & MASK32
              for i in range(n) for j in range(n)}
    return "matmult", {}, data, expect


def bench_bsearch(rng: random.Random):
    n, m = 64, 32
    arr = sorted(rng.sample(range(1, 5000), n))
    present = rng.sample(arr, m // 2)
    absent = []
    while len(absent) < m // 2:
        v = rng.randrange(0, 5100)
        if v not in arr:
            absent.append(v)
    keys = present + absent
    rng.shuffle(keys)
    data = dict(enumerate(arr))
    data.update({64 + i: k for i, k in enumerate(keys)})
    expect = {}
    for i, k in enumerate(keys):
        p = bisect.bisect_left(arr, k)
        expect[128 + i] = (p if p < n and arr[p] == k else -1) & MASK32
    return "bsearch", {"N": n, "M": m}, data, expect


def bench_sieve(rng: random.Random):
    size = 240
    flags = [0] * size
    for i in range(2, size):
        if not flags[i]:
            for j in range(2 * i, size, i):
                flags[j] = 1
    primes = sum(1 for i in range(2, size) if not flags[i])
    expect = {i: flags[i] for i in range(size)}
    expect[250] = primes
    return "sieve", {}, {}, expect


def bench_sort(kernel: str, n: int, rng: random.Random | None, orig: bool = False):
    if orig:   # fixed reference inputs (descending)
        vals = [25 - 5 * i for i in range(n)] if kernel == "bubble" else [100 - 10 * i for i in range(n)]
    else:
        vals = [rng.randint(-1000, 1000) for _ in range(n)]
    expect = {i: v & MASK32 for i, v in enumerate(sorted(vals))}
    return kernel, {"N": n}, dict(enumerate(vals)), expect


def main() -> int:
    OUT.mkdir(exist_ok=True)
    rng = random.Random(SEED)
    suite = [
        ("crc32",       bench_crc32(rng)),
        ("bitcount",    bench_bitcount(rng)),
        ("matmult",     bench_matmult(rng)),
        ("bsearch",     bench_bsearch(rng)),
        ("sieve",       bench_sieve(rng)),
        ("insertion10", bench_sort("insertion", 10, None, orig=True)),
        ("bubble5",     bench_sort("bubble", 5, None, orig=True)),
        ("insertion32", bench_sort("insertion", 32, rng)),
        ("bubble32",    bench_sort("bubble", 32, rng)),
    ]
    rows, ok = [], True
    for name, (kernel, equs, data, expect) in suite:
        src = "".join(f"        .equ {k}, {v}\n" for k, v in equs.items())
        src += (SRC / f"{kernel}.s").read_text() + data_section(data)
        img = assemble(src, f"{kernel}.s")
        iss = ISS(img)
        st = iss.run()
        bad = [(a, iss.dmem[a], v) for a, v in expect.items() if iss.dmem[a] != (v & MASK32)]
        status = "ok" if not bad else f"FAIL ({len(bad)} words, first: [{bad[0][0]}]={bad[0][1]:#x} want {bad[0][2]:#x})"
        ok &= not bad
        write_hex(OUT / f"{name}.imem.hex", img.imem)
        write_hex(OUT / f"{name}.dmem.hex", img.dmem)
        (OUT / f"{name}.lst").write_text("\n".join(img.listing) + "\n")
        (OUT / f"{name}.expect").write_text(
            "".join(f"{a} {v & MASK32:08x}\n" for a, v in sorted(expect.items())))
        taken_pct = 100.0 * st.taken / st.branches if st.branches else 0.0
        rows.append({"benchmark": name, "kernel": kernel, "static_insns": img.text_len,
                     "dynamic_insns": st.retired, "cond_branches": st.branches,
                     "taken": st.taken, "taken_pct": f"{taken_pct:.1f}", "jumps": st.jumps,
                     "loads": st.per_insn.get("LD", 0), "stores": st.per_insn.get("ST", 0),
                     "iss_check": status})
        print(f"{name:12s} static={img.text_len:3d} dynamic={st.retired:6d} "
              f"branches={st.branches:5d} taken={taken_pct:5.1f}% jumps={st.jumps:5d}  {status}")
    with open(OUT / "summary.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
