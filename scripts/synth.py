#!/usr/bin/env python3
"""Vivado implementation sweep for the MiniRISC designs (run on Windows).

    py scripts\\synth.py                       # all designs
    py scripts\\synth.py --dut pipe --tag v2

For each design: Vivado lint + out-of-context synth/place/route on the
Kintex-7 xc7k70t (scripts/synth.tcl). Pass 1 runs at a relaxed 10 ns; pass 2
re-runs with the clock tightened to 5% below pass 1's achieved period, because
Vivado only optimises as hard as the constraint asks. The better of the two
is reported. Outputs: results/synth/<tag>/<dut>/pass{1,2}/... , lint.rpt and
results/synth/<tag>/summary.csv.

All designs use the same ROM image (bubble32) so the comparison is fair.
"""
from __future__ import annotations

import argparse
import csv
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PROJ = Path(__file__).resolve().parent.parent
# design -> (top module, generic overrides as NAME:VALUE[,NAME:VALUE])
# (':' not '=': cmd.exe splits arguments at '=' when vivado.bat is invoked)
DUTS = {
    "sc":      ("RISCV_processor",     ""),
    "pipe":    ("Pipelined_processor", "BP_MODE:0"),
    "btfn":    ("Pipelined_processor", "BP_MODE:1"),
    "bimodal": ("Pipelined_processor", "BP_MODE:2"),
    "gshare":  ("Pipelined_processor", "BP_MODE:3"),
    "ooo":     ("ooo_processor",       "BP_MODE:0"),
    "ooo_bp":  ("ooo_processor",       "BP_MODE:2"),
}


def vivado_run(vivado: Path, top: str, generics: str, period: float, outdir: Path, imem: Path,
               workdir: Path) -> dict:
    outdir.mkdir(parents=True, exist_ok=True)
    if workdir.exists():          # stale .Xil locks from a crashed run break Vivado
        shutil.rmtree(workdir, ignore_errors=True)
    workdir.mkdir(parents=True, exist_ok=True)
    log = outdir / "vivado.log"
    cmd = [str(vivado), "-mode", "batch", "-nolog", "-nojournal",
           "-source", str(PROJ / "scripts" / "synth.tcl"),
           "-tclargs", top, f"{period:.3f}", outdir.as_posix(), imem.as_posix(), generics or "-"]
    for attempt in range(3):
        with open(log, "w") as f:
            rc = subprocess.run(cmd, cwd=workdir, stdout=f, stderr=subprocess.STDOUT, shell=False).returncode
        text = log.read_text(errors="replace")
        m = re.search(r"^SYNTH (.*)$", text, re.M)
        if rc == 0 and m:
            break
        # transient Windows lock on Vivado's own .Xil scratch dir: clean + retry
        if "Designutils 20-411" in text and attempt < 2:
            shutil.rmtree(workdir, ignore_errors=True)
            workdir.mkdir(parents=True, exist_ok=True)
            continue
        sys.exit(f"Vivado failed for {top} (see {log})")
    # guard against silently dropped overrides (this happened once)
    for g in filter(None, generics.split(",")):
        name, val = g.split(":")
        if not re.search(rf"Parameter {name} bound to: {val}\b", text):
            sys.exit(f"generic {name}={val} was not applied to {top} (see {log})")
    kv = dict(re.findall(r"(\w+)=(\S*)", m.group(1)))
    lint = [l for l in text.splitlines() if "[Synth 37-" in l and ("WARNING" in l or "ERROR" in l)]
    kv["lint"] = lint
    return kv


def collect(tag: str) -> list[dict]:
    """Rebuild the summary from every <dut>/pass{1,2}/summary.txt under the
    tag, so a partial re-run (--dut subset) never drops other designs' rows."""
    base = PROJ / "results" / "synth" / tag
    rows = []
    for dut, (top, _) in DUTS.items():
        passes = []
        for p in ("pass1", "pass2"):
            f = base / dut / p / "summary.txt"
            if f.exists():
                passes.append(dict(re.findall(r"(\w+)=(\S*)", f.read_text())))
        if not passes:
            continue
        best = min(passes, key=lambda r: float(r["tmin"]))
        lint = (base / dut / "lint.rpt")
        lint_lines = [l for l in lint.read_text().splitlines() if l.strip()] if lint.exists() else []
        rows.append({
            "dut": dut, "top": top,
            "pass1_period": passes[0]["period"], "pass1_tmin": passes[0]["tmin"],
            "pass2_period": passes[-1]["period"], "pass2_tmin": passes[-1]["tmin"],
            "tmin_ns": best["tmin"], "fmax_mhz": best["fmax_mhz"], "critical": best["critical"],
            "luts": best["luts"], "ffs": best["ffs"], "lutram": best["lutram"], "bram": best["bram"],
            "lint_warnings": len(lint_lines), "lint_critical": sum("CRITICAL" in l for l in lint_lines),
        })
    out = base / "summary.csv"
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    print(f"summary ({len(rows)} designs): {out}")
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dut", nargs="+", choices=list(DUTS), default=list(DUTS))
    ap.add_argument("--tag", default="latest")
    ap.add_argument("--vivado", default=r"C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat")
    ap.add_argument("--rom", default=str(PROJ / "benchmarks" / "build" / "bubble32.imem.hex"))
    ap.add_argument("--workdir", default=str(Path(tempfile.gettempdir()) / "acsa_synth"))
    ap.add_argument("--collect-only", action="store_true",
                    help="only rebuild summary.csv from existing per-pass results")
    a = ap.parse_args()
    if a.collect_only:
        collect(a.tag)
        return 0
    if " " in a.workdir:
        sys.exit("--workdir must not contain spaces (Vivado -generic limitation)")

    rows = []
    for dut in a.dut:
        top, generics = DUTS[dut]
        base = PROJ / "results" / "synth" / a.tag / dut
        work = Path(a.workdir) / a.tag / dut
        r1 = vivado_run(Path(a.vivado), top, generics, 10.0, base / "pass1", Path(a.rom), work / "pass1")
        p2 = round(float(r1["tmin"]) * 0.95, 3)
        r2 = vivado_run(Path(a.vivado), top, generics, p2, base / "pass2", Path(a.rom), work / "pass2")
        best = r2 if float(r2["tmin"]) < float(r1["tmin"]) else r1
        (base / "lint.rpt").write_text("\n".join(r1["lint"]) + "\n")
        row = {"dut": dut, "top": top,
               "pass1_period": r1["period"], "pass1_tmin": r1["tmin"],
               "pass2_period": r2["period"], "pass2_tmin": r2["tmin"],
               "tmin_ns": best["tmin"], "fmax_mhz": best["fmax_mhz"], "critical": best["critical"],
               "luts": best["luts"], "ffs": best["ffs"], "lutram": best["lutram"], "bram": best["bram"],
               "lint_warnings": len(r1["lint"]),
               "lint_critical": sum("CRITICAL" in l for l in r1["lint"])}
        rows.append(row)
        print(f"{dut:5s} Fmax={row['fmax_mhz']:>6} MHz  Tmin={row['tmin_ns']} ns ({row['critical']})  "
              f"LUT={row['luts']} FF={row['ffs']} LUTRAM={row['lutram']}  "
              f"lint={row['lint_warnings']} ({row['lint_critical']} critical)")
    collect(a.tag)
    return 0


if __name__ == "__main__":
    sys.exit(main())
