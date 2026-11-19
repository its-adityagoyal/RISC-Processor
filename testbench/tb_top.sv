// =============================================================================
// tb_top -- self-checking testbench for every MiniRISC microarchitecture
//
//   Compile-time DUT select:  -d DUT_SC  -> single-cycle RISCV_processor
//                             (default)  -> Pipelined_processor
//   Run-time options (plusargs):
//     TEST=<name>   isa_p1..isa_p16 | hazards | orig_bubble5 |
//                   orig_insertion10 | random | hex
//     HEX=<prefix>  with TEST=hex: load <prefix>.imem.hex / .dmem.hex and
//                   check <prefix>.expect ("<addr> <hex>" per line)
//     SEED=<n>      seed for random tests (default 1)
//     MAXCYC=<n>    watchdog (default 200000)
//     TRACE         print every retired instruction
//
// Checks performed every run:
//   1. Lockstep: each retired instruction is compared field-by-field with the
//      golden ISA model (PC, instruction, register write, memory write).
//   2. Final state: all 16 registers and all 256 data-memory words.
//   3. Known-answer checks for directed tests (guards the model itself).
//   4. No retirement after HALT, no X on the retirement port, watchdog.
//   5. SystemVerilog assertions on pipeline internals (pipeline_sva).
// Ends with one machine-readable line:  RESULT: PASS|FAIL key=value ...
// =============================================================================
`timescale 1ns / 1ps

module tb_top;
  import tb_pkg::*;

  // ------------------------------------------------------------------ DUT
  logic clk = 1'b0;
  logic reset = 1'b1;
  always #5 clk = ~clk;

  wire        ret_valid, ret_rd_we, ret_mem_we, halted;
  wire [31:0] ret_pc, ret_insn, ret_rd_wdata, ret_mem_wdata;
  wire [3:0]  ret_rd;
  wire [7:0]  ret_mem_addr;

`ifndef BP_MODE
  `define BP_MODE 0
`endif
`ifndef MEM_LATENCY
  `define MEM_LATENCY 1
`endif
`ifndef OOO_ROB
  `define OOO_ROB 16
`endif
`ifndef OOO_RS
  `define OOO_RS 8
`endif
  localparam string BP_NAME = (`BP_MODE == 0) ? "" : (`BP_MODE == 1) ? "_btfn" :
                              (`BP_MODE == 2) ? "_bimodal" : "_gshare";
`ifdef DUT_SC
  localparam string DUT_NAME = "single_cycle";
  RISCV_processor dut (
`elsif DUT_OOO
  localparam string DUT_NAME = {"out_of_order", BP_NAME};
  ooo_processor #(.BP_MODE(`BP_MODE), .MEM_LATENCY(`MEM_LATENCY),
                  .ROB_ENTRIES(`OOO_ROB), .RS_ENTRIES(`OOO_RS)) dut (
`else
  localparam string DUT_NAME = {"pipelined", BP_NAME};
  Pipelined_processor #(.BP_MODE(`BP_MODE), .MEM_LATENCY(`MEM_LATENCY)) dut (
`endif
    .clk(clk), .reset(reset),
    .ret_valid(ret_valid), .ret_pc(ret_pc), .ret_insn(ret_insn),
    .ret_rd_we(ret_rd_we), .ret_rd(ret_rd), .ret_rd_wdata(ret_rd_wdata),
    .ret_mem_we(ret_mem_we), .ret_mem_addr(ret_mem_addr), .ret_mem_wdata(ret_mem_wdata),
    .halted(halted)
  );

`ifdef DUT_OOO
  ooo_sva #(.ROB_ENTRIES(`OOO_ROB), .TW($clog2(`OOO_ROB))) sva (
    .clk(clk), .reset(reset), .halted(halted), .ret_valid(ret_valid),
    .flush(dut.flush), .dispatch(dut.dispatch), .rob_full(dut.rob_full), .count(dut.count),
    .dbg_rat_ok(dut.dbg_rat_ok), .dbg_rs_ok(dut.dbg_rs_ok), .dbg_count_ok(dut.dbg_count_ok),
    .cdb0_valid(dut.cdb0_valid), .cdb1_valid(dut.cdb1_valid),
    .cdb0_tag(dut.cdb0_tag), .cdb1_tag(dut.cdb1_tag),
    .ret_pc(ret_pc), .ret_insn(ret_insn), .ret_rd_we(ret_rd_we), .ret_mem_we(ret_mem_we),
    .max_idle(24 + 2 * `MEM_LATENCY)
  );
`elsif DUT_SC
`else
  pipeline_sva sva (
    .clk(clk), .reset(reset), .halted(halted),
    .valid_D(dut.valid_D), .valid_E(dut.valid_E), .valid_M(dut.valid_M), .valid_W(dut.valid_W),
    .regWrite_W(dut.regWrite_W), .memWrite_M(dut.memWrite_M),
    .stallF(dut.stallF), .stallD(dut.stallD), .lwStall(dut.HU.lwStall),
    .redirect(dut.redirect_E), .target(dut.redirect_pc_E),
    .pred_taken_F(dut.pred_taken_F), .bp_enabled(`BP_MODE != 0),
    .advance(dut.advance), .max_idle(8 + `MEM_LATENCY),
    .PC(dut.PC), .instruction_D(dut.instruction_D), .pc_D(dut.pc_D),
    .forwardA(dut.forwardA), .forwardB(dut.forwardB),
    .ret_valid(ret_valid), .ret_pc(ret_pc), .ret_insn(ret_insn),
    .ret_rd_we(ret_rd_we), .ret_rd(ret_rd), .ret_rd_wdata(ret_rd_wdata),
    .ret_mem_we(ret_mem_we), .ret_mem_addr(ret_mem_addr), .ret_mem_wdata(ret_mem_wdata)
  );
`endif

  // ------------------------------------------------------------ test state
  IsaModel     ref_m;
  Program      prog;
  string       test_name;
  int unsigned seed;
  int          max_cycles;
  bit          trace_on;

  bit          running;
  bit          halt_retired;
  int          cycles;          // from reset release until HALT retires
  int          retired;
  int          mismatches;
  int          errors;          // all non-lockstep check failures
  int          br_total, br_taken, jumps;
  int          load_use_stalls, flush_events;
  int          mispredicts;      // redirects caused by conditional branches
  int          jump_redirects;   // redirects caused by BR
  int          pred_taken_ok;    // taken control transfers predicted correctly (no penalty)
  string       first_error;

  // functional coverage bins (merged across the regression by regress.ps1)
  int cov_insn [string];
  int cov_event[string];

  // short history of retirements for failure context
  commit_t hist[$];

  function automatic void fail(string msg);
    errors++;
    if (first_error == "") first_error = msg;
    if (errors <= 10) $display("  [FAIL] %s", msg);
    else if (errors == 11) $display("  [FAIL] ... further failures suppressed");
  endfunction

  function automatic string fmt(commit_t c);
    return $sformatf("pc=%0d %-6s rd_we=%0b r%0d=0x%08h mem_we=%0b [%0d]=0x%08h",
                     c.pc, mnemonic(c.insn), c.rd_we, c.rd, c.rd_wdata,
                     c.mem_we, c.mem_addr, c.mem_wdata);
  endfunction

  // ---------------------------------------------------- lockstep monitor
  // Sampled on the falling edge: the WB record is stable, and the register
  // file's own falling-edge write is a non-blocking update that lands after
  // this sample, so rd_wdata is never perturbed by its own write.
  always @(negedge clk) begin
    if (running && !reset) begin
      if (!halt_retired) cycles++;

`ifdef DUT_OOO
      if (dut.alu_sel_v && dut.lsu_sel_v)         cov_event["dual_issue"]++;
      if ((dut.alu_sel_v && dut.rs_tag[dut.alu_sel] != dut.head ||
           dut.lsu_sel_v && dut.rs_tag[dut.lsu_sel] != dut.head) &&
          dut.rob_valid[dut.head] && !dut.rob_done[dut.head])
        cov_event["issue_past_incomplete_head"]++;
      if (dut.ld_issue && dut.fwd_hit)            cov_event["load_forwarded_from_store"]++;
      for (int s = 0; s < dut.RS_ENTRIES; s++)
        if (dut.rs_valid[s] && dut.rs_is_ld[s] && dut.rs_rdy1[s] && dut.ld_blocked[s]) begin
          cov_event["load_blocked_by_store"]++;
          break;
        end
      if (dut.d_valid && dut.rob_full)            cov_event["rob_full_stall"]++;
      if (dut.d_valid && dut.d_needs_rs && !dut.rs_free_v) cov_event["rs_full_stall"]++;
      if (dut.flush) begin
        flush_events++;
        if (dut.rob_is_jump[dut.head]) begin cov_event["jump_redirect"]++; jump_redirects++; end
        else                           begin cov_event["branch_redirect"]++; mispredicts++; end
      end
      if (dut.commit && dut.rob_taken[dut.head] && !dut.rob_mispred[dut.head])
        begin cov_event["taken_predicted_correctly"]++; pred_taken_ok++; end
      if (dut.commit && dut.rob_taken[dut.head] && dut.rob_mispred[dut.head])
        cov_event["taken_predicted_wrongly"]++;
`elsif DUT_SC
`else
      if (dut.advance) begin
        if (dut.valid_E && (dut.forwardA == 2'b10)) cov_event["fwd_A_from_MEM"]++;
        if (dut.valid_E && (dut.forwardA == 2'b01)) cov_event["fwd_A_from_WB"]++;
        if (dut.valid_E && (dut.forwardB == 2'b10)) cov_event["fwd_B_from_MEM"]++;
        if (dut.valid_E && (dut.forwardB == 2'b01)) cov_event["fwd_B_from_WB"]++;
        if (dut.HU.lwStall)                          begin cov_event["load_use_stall"]++; load_use_stalls++; end
        if (dut.valid_E && dut.pred_taken_E && !dut.redirect_E)
          begin cov_event["taken_predicted_correctly"]++; pred_taken_ok++; end
        if (dut.valid_E && dut.pred_taken_E && dut.redirect_E)
          cov_event["taken_predicted_wrongly"]++;
      end else begin
        cov_event["mem_latency_stall"]++;
      end
      if (dut.redirect_E) begin
        flush_events++;
        if (dut.jump_takenE) begin cov_event["jump_redirect"]++; jump_redirects++; end
        else                 begin cov_event["branch_redirect"]++; mispredicts++; end
      end
`endif

      if (ret_valid) begin
        commit_t got, exp;
        got.pc = ret_pc;           got.insn = ret_insn;
        got.rd_we = ret_rd_we;     got.rd = ret_rd;         got.rd_wdata = ret_rd_wdata;
        got.mem_we = ret_mem_we;   got.mem_addr = ret_mem_addr; got.mem_wdata = ret_mem_wdata;

        if ($isunknown({ret_pc, ret_insn, ret_rd_we, ret_mem_we}) ||
            (ret_rd_we  && $isunknown({ret_rd, ret_rd_wdata})) ||
            (ret_mem_we && $isunknown({ret_mem_addr, ret_mem_wdata})))
          fail($sformatf("X on retirement port at cycle %0d", cycles));

        if (ref_m.halted) begin
          fail($sformatf("instruction retired after HALT: %s", fmt(got)));
        end else begin
          string mn;
          exp = ref_m.step();
          retired++;
          mn = mnemonic(exp.insn);       // no function call inside the ++ index
          cov_insn[mn] = cov_insn[mn] + 1;
          if (is_branch(exp.insn)) begin
            if (exp.insn[31:26] == OP_BR) jumps++;
            else begin
              br_total++;
              if (ref_m.last_taken) br_taken++;
              cov_event[ref_m.last_taken ? "cond_branch_taken" : "cond_branch_not_taken"]++;
            end
          end
          // Compare only fields that are architecturally meaningful.
          if (got.pc != exp.pc || got.insn != exp.insn ||
              got.rd_we != exp.rd_we || got.mem_we != exp.mem_we ||
              (exp.rd_we  && (got.rd != exp.rd || got.rd_wdata != exp.rd_wdata)) ||
              (exp.mem_we && (got.mem_addr != exp.mem_addr || got.mem_wdata != exp.mem_wdata))) begin
            mismatches++;
            if (first_error == "")
              first_error = $sformatf("lockstep mismatch at retire #%0d", retired);
            if (mismatches <= 5) begin
              $display("  [MISMATCH] retire #%0d cycle %0d", retired, cycles);
              $display("     expected: %s", fmt(exp));
              $display("     got     : %s", fmt(got));
              foreach (hist[i]) $display("     history : %s", fmt(hist[i]));
            end
          end
          hist.push_back(got);
          if (hist.size() > 4) void'(hist.pop_front());
          if (trace_on) $display("  [RET] cyc %5d  %s", cycles, fmt(got));
          if (ref_m.halted) halt_retired = 1'b1;
        end
      end
    end
  end

  // ------------------------------------------------- benchmark hex loading
  bit [31:0] hex_imem [MEM_WORDS];
  bit [31:0] hex_dmem [MEM_WORDS];

  function automatic Program load_hex(string prefix);
    Program p;
    int     fd, addr, n;
    bit [31:0] val;
    string  base = prefix;
    // test name = last path component of the prefix
    for (int i = prefix.len() - 1; i >= 0; i--)
      if (prefix[i] == "/" || prefix[i] == "\\") begin base = prefix.substr(i + 1, prefix.len() - 1); break; end
    p = new(base);
    foreach (hex_imem[i]) begin hex_imem[i] = HALT_I; hex_dmem[i] = '0; end
    $readmemh({prefix, ".imem.hex"}, hex_imem);
    $readmemh({prefix, ".dmem.hex"}, hex_dmem);
    p.imem = hex_imem;
    p.dmem = hex_dmem;
    fd = $fopen({prefix, ".expect"}, "r");
    if (fd == 0) $fatal(1, "cannot open %s.expect", prefix);
    while (!$feof(fd)) begin
      n = $fscanf(fd, "%d %h\n", addr, val);
      if (n == 2) p.kat_mem(addr, val, "benchmark result");
    end
    $fclose(fd);
    return p;
  endfunction

  // ------------------------------------------------------------- run test
  initial begin
    string hex_prefix;
    if (!$value$plusargs("TEST=%s", test_name)) test_name = "isa_p1";
    if (!$value$plusargs("SEED=%d", seed))      seed = 1;
    if (!$value$plusargs("MAXCYC=%d", max_cycles)) max_cycles = 200000;
    trace_on = $test$plusargs("TRACE");

    if (test_name == "hex") begin
      if (!$value$plusargs("HEX=%s", hex_prefix)) $fatal(1, "TEST=hex needs +HEX=<prefix>");
      prog = load_hex(hex_prefix);
      test_name = prog.name;
    end else begin
      prog = build_test(test_name, seed);
    end
    ref_m = new();
    ref_m.imem = prog.imem;
    ref_m.dmem = prog.dmem;
    ref_m.reset();

    // Load after the memories' own time-0 initial blocks have run.
    #1;
    for (int i = 0; i < MEM_WORDS; i++) begin
      dut.IM.instruction_mem[i] = prog.imem[i];
      dut.MEM.memory[i]         = prog.dmem[i];
    end

    repeat (3) @(posedge clk);
    #1 reset = 1'b0;
    running = 1'b1;

    // run until HALT retires, a lockstep mismatch, or the watchdog fires
    while (!halt_retired && mismatches == 0 && cycles < max_cycles) @(posedge clk);
    if (!halt_retired && mismatches == 0)
      fail($sformatf("watchdog: no HALT after %0d cycles", max_cycles));

    // let the pipeline drain; any retirement now is an error (monitor flags it)
    repeat (8) @(posedge clk);
    running = 1'b0;
    final_checks();
    report();
    $finish;
  end

  // --------------------------------------------------------- final state
  task automatic final_checks();
    for (int r = 0; r < 16; r++)
      if (dut.RB.registers[r] !== ref_m.regs[r])
        fail($sformatf("final R%0d = 0x%08h, expected 0x%08h", r, dut.RB.registers[r], ref_m.regs[r]));
    for (int a = 0; a < MEM_WORDS; a++)
      if (dut.MEM.memory[a] !== ref_m.dmem[a])
        fail($sformatf("final MEM[%0d] = 0x%08h, expected 0x%08h", a, dut.MEM.memory[a], ref_m.dmem[a]));
    foreach (prog.kats[i]) begin
      kat_t k = prog.kats[i];
      bit [31:0] v = k.is_mem ? dut.MEM.memory[k.idx] : dut.RB.registers[k.idx];
      if (v !== k.value)
        fail($sformatf("known-answer '%s': %s[%0d] = 0x%08h, expected 0x%08h",
                       k.name, k.is_mem ? "MEM" : "R", k.idx, v, k.value));
      // the reference model must agree with the hand-computed answer too
      if ((k.is_mem ? ref_m.dmem[k.idx] : ref_m.regs[k.idx]) !== k.value)
        fail($sformatf("REFERENCE MODEL disagrees with known answer '%s'", k.name));
    end
`ifndef DUT_SC
    if (sva.errors > 0) fail($sformatf("%0d assertion failure(s)", sva.errors));
`endif
    // (single-cycle: no internal assertions; checked by lockstep + final state)
  endtask

  task automatic report();
    string verdict = (mismatches == 0 && errors == 0 && halt_retired) ? "PASS" : "FAIL";
    real cpi = (retired > 0) ? real'(cycles) / real'(retired) : 0.0;
    foreach (cov_insn[k])  $display("COV insn %s %0d", k, cov_insn[k]);
    foreach (cov_event[k]) $display("COV event %s %0d", k, cov_event[k]);
    $display("RESULT: %s dut=%s mem_latency=%0d test=%s seed=%0d cycles=%0d retired=%0d cpi=%.4f branches=%0d taken=%0d jumps=%0d load_use_stalls=%0d flushes=%0d mispredicts=%0d jump_redirects=%0d pred_taken_ok=%0d mismatches=%0d errors=%0d first_error=\"%s\"",
             verdict, DUT_NAME, `MEM_LATENCY, test_name, seed, cycles, retired, cpi,
             br_total, br_taken, jumps, load_use_stalls, flush_events,
             mispredicts, jump_redirects, pred_taken_ok,
             mismatches, errors, first_error);
  endtask

endmodule
