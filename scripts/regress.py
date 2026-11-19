#!/usr/bin/env python3
"""Regression runner for the MiniRISC processors.

    python3 scripts/regress.py                         # Verilator (run in WSL/Linux)
    python3 scripts/regress.py --dut pipe --seeds 500 --tag signoff
    py scripts\\regress.py --sim xsim                  # Vivado xsim (Windows)

Per design under test: lint the RTL, build the testbench once, then run
  * 16 directed ISA tests, the hazard test, the two reference sort programs
  * the benchmark suite (benchmarks/build/*.imem.hex, built by build.py)
  * N constrained-random programs
Every run is self-checking (lockstep vs. the golden ISA model, final state,
known answers, assertions). Outputs go to results/<tag>/<dut>/:
  <test>.log  summary.csv  perf.csv  coverage.csv  lint.txt
Exit status is non-zero if anything failed or a coverage bin was missed.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import csv
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

PROJ = Path(__file__).resolve().parent.parent
RTL_DIR = PROJ / "rtl"
TB = [PROJ / "testbench" / f for f in ("tb_pkg.sv", "pipeline_sva.sv", "ooo_sva.sv", "tb_top.sv")]
BENCH_DIR = PROJ / "benchmarks" / "build"
BENCHMARKS = ["crc32", "bitcount", "matmult", "bsearch", "sieve",
              "insertion10", "bubble5", "insertion32", "bubble32"]

# design-under-test -> (top module for lint, extra defines, lint parameter overrides)
DUTS = {
    "sc":      ("RISCV_processor",     ["DUT_SC"],    []),
    "pipe":    ("Pipelined_processor", ["BP_MODE=0"], ["-GBP_MODE=0"]),
    "btfn":    ("Pipelined_processor", ["BP_MODE=1"], ["-GBP_MODE=1"]),
    "bimodal": ("Pipelined_processor", ["BP_MODE=2"], ["-GBP_MODE=2"]),
    "gshare":  ("Pipelined_processor", ["BP_MODE=3"], ["-GBP_MODE=3"]),
    "ooo":     ("ooo_processor",       ["DUT_OOO", "BP_MODE=0"], ["-GBP_MODE=0"]),
    "ooo_bp":  ("ooo_processor",       ["DUT_OOO", "BP_MODE=2"], ["-GBP_MODE=2"]),
    # verification-only corner-case configuration: tiny ROB/RS so that
    # full-structure stalls happen constantly
    "ooo_small": ("ooo_processor", ["DUT_OOO", "BP_MODE=2", "OOO_ROB=4", "OOO_RS=2"],
                  ["-GBP_MODE=2", "-GROB_ENTRIES=4", "-GRS_ENTRIES=2"]),
}
BP_DUTS = {"btfn", "bimodal", "gshare", "ooo_bp", "ooo_small"}
OOO_DUTS = {"ooo", "ooo_bp", "ooo_small"}
SMALL_DUTS = {"ooo_small"}
STRUCTURAL_EVENTS = ["rob_full_stall", "rs_full_stall"]
OOO_EVENTS = ["load_forwarded_from_store", "branch_redirect", "jump_redirect"]
# Reordering only happens when something takes longer than a cycle: with a
# 1-cycle memory every instruction issues the cycle after dispatch, so these
# are unreachable at --mem-latency 1 and required above it.
OOO_LATENCY_EVENTS = ["dual_issue", "issue_past_incomplete_head", "load_blocked_by_store"]
# The 16-entry ROB / 8-entry RS never fill on these workloads; the full-
# structure stall paths are closed on the ooo_small configuration instead.

INSNS = ["ADD", "SUB", "INC", "DEC", "SLT", "SGT", "AND", "OR", "XOR", "NOR", "NOT", "SL",
         "SRL", "SRA", "HAM", "MOVE", "CMOV", "ADDI", "SUBI", "ANDI", "ORI", "XORI", "NORI",
         "SLAI", "SRLI", "SRAI", "LUI", "LD", "ST", "BR", "BMI", "BPL", "BZ", "HALT", "NOP"]
PIPE_EVENTS = ["fwd_A_from_MEM", "fwd_A_from_WB", "fwd_B_from_MEM", "fwd_B_from_WB",
               "load_use_stall", "branch_redirect", "jump_redirect"]
BP_EVENTS = ["taken_predicted_correctly", "taken_predicted_wrongly"]


def tests(seeds: int) -> list[tuple[str, list[str]]]:
    t = [(f"isa_p{i}", [f"+TEST=isa_p{i}"]) for i in range(1, 17)]
    t += [("hazards", ["+TEST=hazards"]),
          ("orig_bubble5", ["+TEST=orig_bubble5"]),
          ("orig_insertion10", ["+TEST=orig_insertion10"])]
    t += [(f"bench_{b}", ["+TEST=hex", f"+HEX={BENCH_DIR / b}"]) for b in BENCHMARKS]
    t += [(f"random_s{s}", ["+TEST=random", f"+SEED={s}"]) for s in range(1, seeds + 1)]
    return t


def run(cmd, cwd=None, log=None, shell=False) -> int:
    with open(log, "w") if log else open(os.devnull, "w") as f:
        return subprocess.run(cmd, cwd=cwd, stdout=f, stderr=subprocess.STDOUT, shell=shell).returncode


# ----------------------------------------------------------------- Verilator
class Verilator:
    name = "verilator"

    def __init__(self, build_root: Path):
        self.build_root = build_root
        # user-space install (official Ubuntu .deb unpacked under ~/tools)
        local = Path.home() / "tools" / "verilator" / "usr"
        if not shutil.which("verilator") and (local / "bin" / "verilator").exists():
            os.environ["VERILATOR_ROOT"] = str(local / "share" / "verilator")
            os.environ["PATH"] = f"{local / 'bin'}{os.pathsep}{os.environ['PATH']}"
        if not shutil.which("verilator"):
            sys.exit("verilator not found (apt install verilator, or unpack the .deb under ~/tools/verilator)")

    def lint(self, dut: str, top: str, out: Path, params: list[str] = ()) -> int:
        rtl = sorted(str(p) for p in RTL_DIR.glob("*.v"))
        waivers = PROJ / "scripts" / "lint_waivers.vlt"
        run(["verilator", "--lint-only", "-Wall", "--top-module", top, *params, str(waivers), *rtl], log=out)
        return sum(1 for line in out.read_text().splitlines() if line.startswith("%Warning"))

    def build(self, dut: str, defines: list[str], log: Path) -> Path:
        mdir = self.build_root / dut
        mdir.mkdir(parents=True, exist_ok=True)
        rtl = sorted(str(p) for p in RTL_DIR.glob("*.v"))
        # single-threaded front end (5.020's -j 0 intermittently aborts with
        # "attempted to destroy locked Thread Pool"), parallel C++ build
        cmd = ["verilator", "--binary", "--timing", "--assert", "--build-jobs", str(os.cpu_count() or 4), "-sv",
               "-Wno-fatal", "-Wno-lint", "-Wno-style", "--x-assign", "unique", "--x-initial", "unique",
               "--top-module", "tb_top", "-Mdir", str(mdir), "-o", "tb",
               *[f"-D{d}" for d in defines], *rtl, *map(str, TB)]
        if run(cmd, log=log) != 0:
            sys.exit(f"verilator build failed for {dut}, see {log}")
        return mdir / "tb"

    def sim(self, exe: Path, args: list[str], log: Path) -> None:
        run([str(exe), "+verilator+rand+reset+2", *args], log=log)


# ---------------------------------------------------------------------- xsim
class Xsim:
    name = "xsim"

    def __init__(self, build_root: Path, vivado: str):
        self.build_root = build_root
        self.viv = Path(vivado)
        os.environ["XILINX_VIVADO"] = vivado
        os.environ["PATH"] = os.pathsep.join([str(self.viv / "lib" / "win64.o"), str(self.viv / "bin"),
                                              os.environ["PATH"]])

    def lint(self, dut: str, top: str, out: Path, params: list[str] = ()) -> int:
        out.write_text("(lint is reported from compile warnings under xsim)\n")
        return 0

    def build(self, dut: str, defines: list[str], log: Path) -> Path:
        bdir = self.build_root / dut
        bdir.mkdir(parents=True, exist_ok=True)
        rtl = " ".join(f'"{p}"' for p in sorted(RTL_DIR.glob("*.v")))
        tb = " ".join(f'"{p}"' for p in TB)
        defs = " ".join(f"-d {d}" for d in defines)
        if run(f'xvlog.bat --nolog -sv {defs} {rtl} {tb}', cwd=bdir, log=log, shell=True) != 0 or \
           run(f'xelab.bat --nolog -debug off -relax tb_top -s tb', cwd=bdir, log=log.with_suffix(".elab.log"),
               shell=True) != 0:
            sys.exit(f"xsim build failed for {dut}, see {log}")
        return bdir

    def sim(self, bdir: Path, args: list[str], log: Path) -> None:
        plus = " ".join(f'--testplusarg "{a[1:]}"' for a in args)
        run(f"xsim.bat tb -R --nolog {plus}", cwd=bdir, log=log, shell=True)


# ------------------------------------------------------------------- report
def parse(log: Path) -> dict:
    text = log.read_text(errors="replace") if log.exists() else ""
    res = [l for l in text.splitlines() if l.startswith("RESULT: ")]
    if not res:
        tail = " | ".join(text.strip().splitlines()[-3:])[:200]
        return {"result": "FAIL", "first_error": f"no RESULT line: {tail}", "cov": {}}
    line = res[-1]
    kv = {m.group(1): m.group(2).strip('"') for m in re.finditer(r'(\w+)=("[^"]*"|\S+)', line)}
    kv["result"] = "PASS" if line.startswith("RESULT: PASS") else "FAIL"
    kv["cov"] = {}
    for m in re.finditer(r"^COV (\w+) (\S+) (\d+)$", text, re.M):
        kv["cov"][f"{m.group(1)} {m.group(2)}"] = int(m.group(3))
    return kv


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sim", choices=["verilator", "xsim"], default="verilator")
    ap.add_argument("--dut", nargs="+", choices=list(DUTS), default=list(DUTS))
    ap.add_argument("--seeds", type=int, default=100)
    ap.add_argument("--mem-latency", type=int, default=1,
                    help="data-memory load latency in cycles (pipelined and OoO cores)")
    ap.add_argument("--tag", default="latest")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--vivado", default=r"C:\AMDDesignTools\2025.2\Vivado")
    ap.add_argument("--build-root", default=None)
    a = ap.parse_args()

    if a.sim == "verilator":
        sim = Verilator(Path(a.build_root or Path.home() / "acsa_build"))
    else:
        sim = Xsim(Path(a.build_root or Path(os.environ.get("TEMP", ".")) / "acsa_build"), a.vivado)
        a.jobs = 1  # xsim runs share one snapshot directory

    missing = [b for b in BENCHMARKS if not (BENCH_DIR / f"{b}.imem.hex").exists()]
    if missing:
        sys.exit(f"benchmarks not built ({', '.join(missing)}): run python3 benchmarks/build.py")

    overall_ok = True
    for dut in a.dut:
        top, defines, params = DUTS[dut]
        if a.mem_latency != 1:
            if dut == "sc":
                print("=== [sc] skipped: the single-cycle core assumes a 1-cycle memory")
                continue
            defines = defines + [f"MEM_LATENCY={a.mem_latency}"]
            params = params + [f"-GMEM_LATENCY={a.mem_latency}"]
        out = PROJ / "results" / a.tag / dut
        out.mkdir(parents=True, exist_ok=True)
        for old in out.glob("*.log"):
            old.unlink()
        nwarn = sim.lint(dut, top, out / "lint.txt", params)
        print(f"=== [{dut}] lint: {nwarn} warning(s) -> {out / 'lint.txt'}")
        print(f"=== [{dut}] building testbench ({sim.name}) ...")
        exe = sim.build(dut, defines, out / "build.log")

        tl = tests(a.seeds)
        with cf.ThreadPoolExecutor(max_workers=a.jobs) as pool:
            futs = {pool.submit(sim.sim, exe, args, out / f"{name}.log"): name for name, args in tl}
            cf.wait(futs)
        rows, cov = [], {}
        for name, _ in tl:
            r = parse(out / f"{name}.log")
            for k, v in r.pop("cov").items():
                cov[k] = cov.get(k, 0) + v
            r.pop("test", None)          # RESULT line's test= is the short name
            rows.append({"test": name, **r})

        fields = ["test", "result", "cycles", "retired", "cpi", "branches", "taken", "jumps",
                  "load_use_stalls", "flushes", "mispredicts", "jump_redirects", "pred_taken_ok",
                  "mismatches", "errors", "first_error"]
        with open(out / "summary.csv", "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
            w.writeheader()
            w.writerows(rows)
        perf = [r for r in rows if r["test"].startswith(("bench_", "orig_"))]
        with open(out / "perf.csv", "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fields[:13], extrasaction="ignore")
            w.writeheader()
            w.writerows(perf)

        required = [f"insn {i}" for i in INSNS] + ["event cond_branch_taken", "event cond_branch_not_taken"]
        if dut in OOO_DUTS:
            required += [f"event {e}" for e in OOO_EVENTS]
            if a.mem_latency > 1:
                required += [f"event {e}" for e in OOO_LATENCY_EVENTS]
            if dut in SMALL_DUTS and a.mem_latency > 1:
                required += [f"event {e}" for e in STRUCTURAL_EVENTS]
        elif dut != "sc":
            required += [f"event {e}" for e in PIPE_EVENTS]
            if a.mem_latency > 1:
                required.append("event mem_latency_stall")
        if dut in BP_DUTS:
            required += [f"event {e}" for e in BP_EVENTS]
        holes = [k for k in required if cov.get(k, 0) == 0]
        with open(out / "coverage.csv", "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["bin", "hits", "required"])
            for k in sorted(set(required) | set(cov)):
                w.writerow([k, cov.get(k, 0), "yes" if k in required else "no"])

        fails = [r for r in rows if r["result"] != "PASS"]
        for r in fails[:15]:
            print(f"    FAIL {r['test']:<20} {r.get('first_error', '')}")
        if len(fails) > 15:
            print(f"    ... and {len(fails) - 15} more")
        print(f"    {'benchmark':<22}{'cycles':>8}{'retired':>9}{'CPI':>8}{'mispred':>9}  ")
        for r in perf:
            print(f"    {r['test']:<22}{r.get('cycles', ''):>8}{r.get('retired', ''):>9}{r.get('cpi', ''):>8}"
                  f"{r.get('mispredicts', ''):>9}  {r['result']}")
        print(f"=== [{dut}] {len(rows) - len(fails)}/{len(rows)} passed | coverage "
              f"{len(required) - len(holes)}/{len(required)} bins" + (f" | holes: {', '.join(holes)}" if holes else ""))
        overall_ok &= not fails and not holes
    return 0 if overall_ok else 1


if __name__ == "__main__":
    sys.exit(main())
