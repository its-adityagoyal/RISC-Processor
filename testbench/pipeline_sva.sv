// =============================================================================
// pipeline_sva -- SystemVerilog assertions for the 5-stage MiniRISC pipeline
//
// Instantiated by tb_top with hierarchical connections into the DUT. Each
// property encodes a microarchitectural invariant that must hold on every
// cycle of every program; failures are counted and fail the test.
// =============================================================================
`timescale 1ns / 1ps

module pipeline_sva (
  input logic        clk,
  input logic        reset,
  input logic        halted,
  input logic        valid_D, valid_E, valid_M, valid_W,
  input logic        regWrite_W, memWrite_M,
  input logic        stallF, stallD, lwStall,
  input logic        redirect,       // EX-stage redirect (mispredict / taken without prediction)
  input logic [31:0] target,         // correct next PC on a redirect
  input logic        pred_taken_F,   // IF-stage prediction
  input logic        bp_enabled,
  input logic        advance,        // 0 while a load waits on a slow memory
  input int          max_idle,
  input logic [31:0] PC,
  input logic [31:0] instruction_D, pc_D,
  input logic [1:0]  forwardA, forwardB,
  input logic        ret_valid,
  input logic [31:0] ret_pc, ret_insn, ret_rd_wdata, ret_mem_wdata,
  input logic        ret_rd_we, ret_mem_we,
  input logic [3:0]  ret_rd,
  input logic [7:0]  ret_mem_addr
);

  int errors = 0;

  // Failures are counted through a function: Verilator 5.020 hits an internal
  // error when an assertion action block references a module variable directly.
  function automatic void sva_fail(string name);
    errors++;
    if (errors <= 10) $display("[SVA] %s failed at %0t", name, $time);
  endfunction

  `define SVA(name, prop) \
    name: assert property (@(posedge clk) disable iff (reset) prop) \
      else sva_fail(`"name`");

  // A bubble must never update architectural state.
  `SVA(a_bubble_no_rf_write,  !valid_W |-> !regWrite_W)
  `SVA(a_bubble_no_mem_write, !valid_M |-> !memWrite_M)

  // Stalls must freeze the front end (a redirect takes priority over a stall).
  `SVA(a_stall_holds_pc, (stallF && !redirect && !halted) |=> $stable(PC))

  // With prediction disabled the front end never predicts taken.
  `SVA(a_no_prediction_when_disabled, !bp_enabled |-> !pred_taken_F)
  `SVA(a_stall_holds_D,  (stallD && !redirect) |=> ($stable(instruction_D) && $stable(pc_D)))

  // A load-use stall inserts exactly one bubble into EX.
  `SVA(a_load_use_bubble, (lwStall && advance) |=> !valid_E)

  // While a load waits on memory nothing in front of it moves and nothing retires.
  `SVA(a_mem_wait_freezes, !advance |=> ($stable(PC) && !ret_valid))

  // A taken branch/jump squashes the two younger instructions and redirects.
  `SVA(a_redirect_squash, redirect |=> (!valid_D && !valid_E))
  `SVA(a_redirect_target, redirect |=> (PC == $past(target)))

  // Nothing retires once the core has halted.
  `SVA(a_halt_quiet, halted |-> !ret_valid)

  // No X on control or on a valid retirement.
  `SVA(a_ctrl_known, !$isunknown({forwardA, forwardB, stallF, stallD, redirect,
                                  valid_D, valid_E, valid_M, valid_W}))
  `SVA(a_retire_known, ret_valid |-> !$isunknown({ret_pc, ret_insn, ret_rd_we, ret_mem_we}))

  // Forward progress: something retires at least every max_idle cycles until
  // HALT. (Counter form: portable to simulators without ##[m:n] support.)
  int idle_cycles = 0;
  always @(posedge clk)
    if (reset || ret_valid || halted) idle_cycles <= 0;
    else                              idle_cycles <= idle_cycles + 1;
  `SVA(a_progress, idle_cycles <= max_idle)

  `undef SVA

endmodule
