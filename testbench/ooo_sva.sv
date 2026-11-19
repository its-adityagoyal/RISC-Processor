// =============================================================================
// ooo_sva -- SystemVerilog assertions for the out-of-order MiniRISC core
//
// The array-wide invariants (RAT <-> ROB, RS <-> ROB, ROB occupancy) are
// reduced to single bits inside ooo_processor (simulation-only block) and
// asserted here every cycle, together with handshake and liveness properties.
// =============================================================================
`timescale 1ns / 1ps

module ooo_sva #(parameter ROB_ENTRIES = 16, parameter TW = 4) (
  input logic          clk,
  input logic          reset,
  input logic          halted,
  input logic          ret_valid,
  input logic          flush,
  input logic          dispatch,
  input logic          rob_full,
  input logic [TW:0]   count,
  input logic          dbg_rat_ok,
  input logic          dbg_rs_ok,
  input logic          dbg_count_ok,
  input logic          cdb0_valid, cdb1_valid,
  input logic [TW-1:0] cdb0_tag,   cdb1_tag,
  input logic [31:0]   ret_pc, ret_insn,
  input logic          ret_rd_we, ret_mem_we,
  input int            max_idle
);

  int errors = 0;

  // Counted through a function: Verilator 5.020 cannot reference module
  // variables directly inside an assertion action block.
  function automatic void sva_fail(string name);
    errors++;
    if (errors <= 10) $display("[SVA] %s failed at %0t", name, $time);
  endfunction

  `define SVA(name, prop) \
    name: assert property (@(posedge clk) disable iff (reset) prop) \
      else sva_fail(`"name`");

  // Renaming state is always consistent with the reorder buffer.
  `SVA(a_rat_points_to_live_writer,   dbg_rat_ok)
  `SVA(a_rs_waits_on_live_entry,      dbg_rs_ok)
  `SVA(a_rob_count_matches_valid,     dbg_count_ok)
  `SVA(a_rob_count_bounded,           count <= ROB_ENTRIES)

  // Two results in one cycle always belong to different instructions.
  `SVA(a_cdb_tags_distinct, (cdb0_valid && cdb1_valid) |-> (cdb0_tag != cdb1_tag))

  // No allocation into a full ROB; a recovery flush empties the machine.
  `SVA(a_no_dispatch_when_full, rob_full |-> !dispatch)
  `SVA(a_flush_empties_rob,     flush |=> (count == 0))

  // Nothing commits after HALT; committed records are never X.
  `SVA(a_halt_quiet,     halted |-> !ret_valid)
  `SVA(a_retire_known,   ret_valid |-> !$isunknown({ret_pc, ret_insn, ret_rd_we, ret_mem_we}))

  // Liveness: an instruction commits at least every max_idle cycles.
  int idle_cycles = 0;
  always @(posedge clk)
    if (reset || ret_valid || halted) idle_cycles <= 0;
    else                              idle_cycles <= idle_cycles + 1;
  `SVA(a_progress, idle_cycles <= max_idle)

  `undef SVA

endmodule
