#!/usr/bin/env python3
"""Compare benchmark performance across designs from one regression tag.

    python3 scripts/compare.py --tag bp [--synth-tag fixed]

Reads results/<tag>/<dut>/perf.csv (and optionally results/synth/<synth-tag>/
summary.csv for Fmax) and writes results/<tag>/comparison.csv plus a printed
table: CPI per benchmark, conditional-branch misprediction rate, and -- when
Fmax is available -- execution time and speedup over the single-cycle core.
"""
from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path

PROJ = Path(__file__).resolve().parent.parent
ORDER = ["sc", "pipe", "btfn", "bimodal", "gshare", "ooo", "ooo_bp"]


def load_csv(p: Path) -> list[dict]:
    with open(p, newline="") as f:
        return list(csv.DictReader(f))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--synth-tag", default=None)
    a = ap.parse_args()

    base = PROJ / "results" / a.tag
    duts = [d for d in ORDER if (base / d / "perf.csv").exists()]
    perf = {d: {r["test"]: r for r in load_csv(base / d / "perf.csv")} for d in duts}
    benches = [t for t in perf[duts[0]] if t.startswith("bench_")]

    fmax = {}
    if a.synth_tag:
        s = PROJ / "results" / "synth" / a.synth_tag / "summary.csv"
        if s.exists():
            fmax = {r["dut"]: float(r["fmax_mhz"]) for r in load_csv(s)}

    rows = []
    print(f"\nCPI (lower is better)")
    print(f"{'benchmark':<18}" + "".join(f"{d:>10}" for d in duts))
    for b in benches:
        line = f"{b[6:]:<18}"
        for d in duts:
            r = perf[d].get(b, {})
            line += f"{float(r['cpi']):>10.3f}" if r.get("cpi") else f"{'-':>10}"
            br = int(r.get("branches") or 0)
            mp = int(r.get("mispredicts") or 0)
            cyc = int(r.get("cycles") or 0)
            row = {"benchmark": b[6:], "dut": d, "cycles": cyc, "retired": r.get("retired"),
                   "cpi": r.get("cpi"), "cond_branches": br, "mispredicts": mp,
                   "mispredict_rate": f"{mp / br:.4f}" if br else "",
                   "fmax_mhz": fmax.get(d, "")}
            if d in fmax and cyc:
                row["exec_time_us"] = f"{cyc / fmax[d]:.3f}"
            rows.append(row)
        print(line)

    geo = {}
    for d in duts:
        cpis = [float(perf[d][b]["cpi"]) for b in benches if perf[d].get(b, {}).get("cpi")]
        geo[d] = math.exp(sum(map(math.log, cpis)) / len(cpis)) if cpis else float("nan")
    print(f"{'geomean':<18}" + "".join(f"{geo[d]:>10.3f}" for d in duts))

    print(f"\nConditional-branch misprediction rate (pipelined designs)")
    print(f"{'benchmark':<18}" + "".join(f"{d:>10}" for d in duts if d != "sc"))
    for b in benches:
        line = f"{b[6:]:<18}"
        for d in duts:
            if d == "sc":
                continue
            r = perf[d][b]
            br, mp = int(r["branches"] or 0), int(r["mispredicts"] or 0)
            line += f"{100.0 * mp / br:>9.1f}%" if br else f"{'-':>10}"
        print(line)

    if fmax and "sc" in duts:
        print(f"\nSpeedup over single-cycle (execution time = cycles / Fmax)")
        print(f"{'benchmark':<18}" + "".join(f"{d:>10}" for d in duts if d in fmax))
        for b in benches:
            t_sc = int(perf["sc"][b]["cycles"]) / fmax["sc"]
            line = f"{b[6:]:<18}"
            for d in duts:
                if d in fmax:
                    line += f"{t_sc / (int(perf[d][b]['cycles']) / fmax[d]):>9.2f}x"
            print(line)
        print("Fmax (MHz)        " + "".join(f"{fmax[d]:>10.1f}" for d in duts if d in fmax))

    out = base / "comparison.csv"
    keys = ["benchmark", "dut", "cycles", "retired", "cpi", "cond_branches", "mispredicts",
            "mispredict_rate", "fmax_mhz", "exec_time_us"]
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    print(f"\n-> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
