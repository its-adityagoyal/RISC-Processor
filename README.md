# MiniRISC: From In-Order to Out-of-Order Execution

Course project for **Advanced Computer System Architecture** (Autumn 2026-27),
Department of E&ECE, IIT Kharagpur.

We defined MiniRISC, a 32-bit RISC instruction set, and built four processors
for it in Verilog. All four run the same programs and are checked by the same
testbench, so they can be compared directly on cycles per instruction (CPI),
clock frequency, hardware size and total run time.

| Design | What it is |
|---|---|
| Single-cycle | One instruction per clock cycle |
| 5-stage pipeline | IF, ID, EX, MEM, WB with forwarding, load-use stall and branch flush |
| Pipeline + branch prediction | 16-entry BTB with four direction predictors: none, BTFN, bimodal (2-bit counters) and gshare |
| Out-of-order | Tomasulo's algorithm with a 16-entry reorder buffer, 8-entry reservation station, register renaming, store-to-load forwarding and commit-time branch recovery |

## Repository layout

```
rtl/          Verilog sources of all processors and their building blocks
testbench/    SystemVerilog testbench, golden ISA model, assertions
benchmarks/   benchmark kernels in MiniRISC assembly and the build script
tools/        mrasm.py: assembler and instruction-set simulator
scripts/      regression, comparison and Vivado synthesis scripts
results/      regression summaries and Vivado reports used in our report
```

Main RTL files:

| File | Contents |
|---|---|
| `rtl/RISCV_processor.v` | Single-cycle processor |
| `rtl/Pipelined_processor.v` | 5-stage pipeline (parameters `BP_MODE`, `MEM_LATENCY`) |
| `rtl/branch_predictor.v` | BTB and the four direction predictors |
| `rtl/ooo_processor.v` | Out-of-order processor |
| `rtl/ALU.v` and the `*_unit.v` files | ALU: arithmetic, logical, shifter, HAM and LUI units |
| `rtl/control_unit.v` | Hardwired control unit |
| `rtl/forwarding_unit.v`, `rtl/hazard_unit.v` | Pipeline hazard handling |
| `rtl/IF_ID.v` ... `rtl/MEM_WB.v` | Pipeline registers |

## The instruction set

- 16 registers of 32 bits, 256-word instruction memory, 256-word data memory
- Four formats: R type, I type, J type and program control
- Arithmetic, logical, shift, `HAM` (count of 1 bits), `MOVE`, `CMOV` (signed
  minimum), `LUI`, `LD`, `ST`, branches `BMI`, `BPL`, `BZ` (PC-relative), jump
  `BR` (absolute), `HALT` and `NOP`
- All 16-bit immediates are sign-extended

## Running it

Requirements:

- Python 3.10 or newer
- [Verilator](https://verilator.org) 5.020 for simulation (we used it on Ubuntu under WSL)
- AMD Vivado 2025.2 for synthesis (optional)

```bash
# 1. assemble the benchmarks and compute their expected results
python3 benchmarks/build.py

# 2. run the full regression on every design (100 random programs each)
python3 scripts/regress.py --tag mytest --seeds 100

# 3. same, with data-memory loads taking 4 cycles
python3 scripts/regress.py --tag mytest_lat4 --mem-latency 4 --dut pipe bimodal ooo ooo_bp ooo_small

# 4. print the CPI comparison (add --synth-tag final to include clock speed)
python3 scripts/compare.py --tag mytest
```

Synthesis, place and route (Windows, needs Vivado; pass `--vivado` if it is
installed somewhere else):

```
py -3 scripts\synth.py --tag mysynth --dut pipe bimodal ooo_bp
```

Design names used by the scripts:

| Name | Design |
|---|---|
| `sc` | Single-cycle |
| `pipe` | Pipeline, no prediction |
| `btfn`, `bimodal`, `gshare` | Pipeline with that predictor |
| `ooo` | Out-of-order, no prediction |
| `ooo_bp` | Out-of-order with bimodal prediction |
| `ooo_small` | Out-of-order with a 4-entry ROB and 2-entry RS, used only for testing |

## How the designs are verified

- Every processor reports each instruction it completes (PC, register written,
  value, memory store), in the style of the RISC-V Formal Interface.
- A golden model written straight from the ISA runs the same program, and the
  two are compared after every instruction. Registers and memory are compared
  again at the end.
- Tests: 16 directed programs, a hazard program, constrained-random programs
  and the benchmarks.
- SystemVerilog assertions check internal rules every cycle, and functional
  coverage confirms every instruction and hazard case was hit.
- Verilator `-Wall` lint is clean.

In total 11,968 simulation runs pass, including a sign-off with 1000 random
programs.

## Results

Average CPI over nine benchmarks (crc32, bitcount, matmult, bsearch, sieve and
four sorting runs). `MEM_LATENCY` is the number of cycles a load takes.

| MEM_LATENCY | Single-cycle | Pipeline | BTFN | Bimodal | gshare | OoO | OoO + bimodal |
|---|---|---|---|---|---|---|---|
| 1 | 1.000 | 1.404 | 1.159 | 1.147 | 1.158 | 1.511 | 1.128 |
| 8 | - | 1.952 | - | 1.677 | - | 1.916 | 1.281 |

Vivado results after place and route (Kintex-7 `xc7k70t`):

| Design | Max. clock (MHz) | LUTs |
|---|---|---|
| Single-cycle | 57.4 | 1064 |
| Pipeline | 112.8 | 1297 |
| Pipeline + BTFN | 111.0 | 1321 |
| Pipeline + bimodal | 109.3 | 1562 |
| Pipeline + gshare | 104.3 | 1576 |
| Out-of-order | 35.8 | 7035 |
| Out-of-order + bimodal | 37.2 | 7312 |

What we found:

- Pipelining roughly doubles the clock frequency.
- Bimodal prediction removes 64% of the pipeline's extra cycles, for very
  little hardware. The pipeline with bimodal prediction is the fastest design
  in real time.
- The out-of-order core hides slow memory well (24% fewer cycles than the
  in-order pipeline at an 8-cycle load latency), but only with branch
  prediction. Its clock is about three times slower, so it loses in real time.
