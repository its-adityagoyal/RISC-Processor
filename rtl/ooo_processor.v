`timescale 1ns / 1ps
// =============================================================================
// ooo_processor -- out-of-order MiniRISC core (Tomasulo + reorder buffer)
//
//   IF       PC, instruction memory, branch_predictor lookup
//   D        decode, rename (RAT), allocate ROB + reservation station,
//            capture ready operands (ARF / ROB / result buses)
//   ISSUE+EX two functional units issue out of order, oldest ready first:
//              FU0  ALU, MOVE/CMOV, LUI, branches and jumps   (1 cycle)
//              FU1  loads and stores (address + memory access)
//   CDB      two result buses wake up waiting operands and mark ROB entries
//   COMMIT   one instruction per cycle, in program order, from the ROB head:
//            architectural register write, store to memory, predictor
//            training; a mispredicted control instruction flushes everything
//            younger and redirects fetch (commit-time recovery)
//
// Memory ordering: a load issues only when every older store already has its
// address; it then takes the value of the youngest older store to the same
// address (store-to-load forwarding) or reads memory. Stores write memory
// only at commit, so wrong-path stores never change state.
//
// MEM_LATENCY models a slower data memory: a load's value reaches its result
// bus MEM_LATENCY cycles after it issues (fixed-latency, pipelined unit).
// Independent instructions keep issuing meanwhile -- the point of OoO.
//
// Retires through the same RVFI-style ret_* port as the in-order cores, so
// the same lockstep testbench verifies it.
// =============================================================================
module ooo_processor #(
    parameter IMEM_INIT_FILE = "",
    parameter BP_MODE        = 2,     // 0 none, 1 BTFN, 2 bimodal, 3 gshare
    parameter BTB_ENTRIES    = 16,
    parameter PHT_ENTRIES    = 64,
    parameter GHR_BITS       = 6,
    parameter ROB_ENTRIES    = 16,    // power of two
    parameter RS_ENTRIES     = 8,
    parameter MEM_LATENCY    = 1      // >= 1
)(
    input clk,
    input reset,

    output        ret_valid,
    output [31:0] ret_pc,
    output [31:0] ret_insn,
    output        ret_rd_we,
    output [3:0]  ret_rd,
    output [31:0] ret_rd_wdata,
    output        ret_mem_we,
    output [7:0]  ret_mem_addr,
    output [31:0] ret_mem_wdata,
    output        halted
);
    localparam TW        = $clog2(ROB_ENTRIES);
    localparam SW        = $clog2(RS_ENTRIES);
    localparam PHT_IDX_W = $clog2(PHT_ENTRIES);

    localparam [5:0] OP_R   = 6'b000000, OP_LUI = 6'b100001, OP_LD  = 6'b101010,
                     OP_ST  = 6'b101011, OP_BR  = 6'b110000, OP_BMI = 6'b110001,
                     OP_BPL = 6'b110010, OP_BZ  = 6'b110011, OP_HALT = 6'b111000;
    localparam [5:0] F_ADD = 6'b001000, F_SUB = 6'b001001, F_SLT = 6'b001100,
                     F_SGT = 6'b001101, F_AND = 6'b010000, F_OR  = 6'b010001,
                     F_XOR = 6'b010010, F_NOR = 6'b010011, F_MOVE = 6'b101000,
                     F_CMOV = 6'b101001;

    // =========================================================================
    //   STATE
    // =========================================================================
    reg  [31:0] PC;
    reg         halted_r;          // HALT has committed
    reg         dispatch_halt;     // a HALT was dispatched: stop fetching

    // F/D register
    reg                 d_valid;
    reg  [31:0]         d_insn, d_pc, d_pred_target;
    reg                 d_pred_taken;
    reg [PHT_IDX_W-1:0] d_pht_idx;

    // register alias table
    reg          rat_busy [0:15];
    reg [TW-1:0] rat_tag  [0:15];

    // reorder buffer
    reg                 rob_valid    [0:ROB_ENTRIES-1];
    reg                 rob_done     [0:ROB_ENTRIES-1];
    reg [31:0]          rob_pc       [0:ROB_ENTRIES-1];
    reg [31:0]          rob_insn     [0:ROB_ENTRIES-1];
    reg                 rob_rd_we    [0:ROB_ENTRIES-1];
    reg [3:0]           rob_rd       [0:ROB_ENTRIES-1];
    reg [31:0]          rob_value    [0:ROB_ENTRIES-1];
    reg                 rob_is_store [0:ROB_ENTRIES-1];
    reg [7:0]           rob_st_addr  [0:ROB_ENTRIES-1];
    reg [31:0]          rob_st_data  [0:ROB_ENTRIES-1];
    reg                 rob_is_halt  [0:ROB_ENTRIES-1];
    reg                 rob_is_cond  [0:ROB_ENTRIES-1];
    reg                 rob_is_jump  [0:ROB_ENTRIES-1];
    reg                 rob_mispred  [0:ROB_ENTRIES-1];
    reg [31:0]          rob_next_pc  [0:ROB_ENTRIES-1];
    reg                 rob_taken    [0:ROB_ENTRIES-1];
    reg [31:0]          rob_target   [0:ROB_ENTRIES-1];
    reg [PHT_IDX_W-1:0] rob_pht_idx  [0:ROB_ENTRIES-1];
    reg [TW-1:0]        head, tail;
    reg [TW:0]          count;

    // reservation stations (unified)
    reg          rs_valid     [0:RS_ENTRIES-1];
    reg [TW-1:0] rs_tag       [0:RS_ENTRIES-1];
    reg [31:0]   rs_insn      [0:RS_ENTRIES-1];
    reg [31:0]   rs_pc        [0:RS_ENTRIES-1];
    reg [31:0]   rs_pred_next [0:RS_ENTRIES-1];
    reg          rs_is_mem    [0:RS_ENTRIES-1];
    reg          rs_is_ld     [0:RS_ENTRIES-1];
    reg          rs_rdy1      [0:RS_ENTRIES-1];
    reg [TW-1:0] rs_q1        [0:RS_ENTRIES-1];
    reg [31:0]   rs_v1        [0:RS_ENTRIES-1];
    reg          rs_rdy2      [0:RS_ENTRIES-1];
    reg [TW-1:0] rs_q2        [0:RS_ENTRIES-1];
    reg [31:0]   rs_v2        [0:RS_ENTRIES-1];

    function [TW-1:0] age;            // position relative to the ROB head
        input [TW-1:0] t;
        age = t - head;
    endfunction

    // =========================================================================
    //   FETCH
    // =========================================================================
    wire [31:0] insn_F;
    instruction_memory #(.INIT_FILE(IMEM_INIT_FILE)) IM(
        .clk(clk), .address(PC[7:0]), .instruction(insn_F)
    );

    wire                 pred_taken_F;
    wire [31:0]          pred_target_F;
    wire [PHT_IDX_W-1:0] pht_idx_F;

    // commit-side signals used by the predictor (defined in COMMIT below)
    wire                 commit;
    wire [TW-1:0]        h = head;

    branch_predictor #(
        .MODE(BP_MODE), .BTB_ENTRIES(BTB_ENTRIES),
        .PHT_ENTRIES(PHT_ENTRIES), .GHR_BITS(GHR_BITS)
    ) BP (
        .clk(clk), .reset(reset),
        .pc_f(PC), .pred_taken_f(pred_taken_F), .pred_target_f(pred_target_F), .pht_idx_f(pht_idx_F),
        .upd_valid(commit), .upd_is_cond(rob_is_cond[h]), .upd_is_jump(rob_is_jump[h]),
        .upd_pc(rob_pc[h]), .upd_taken(rob_taken[h]), .upd_target(rob_target[h]),
        .upd_pht_idx(rob_pht_idx[h])
    );

    // =========================================================================
    //   DECODE (D stage)
    // =========================================================================
    wire [5:0]  d_op = d_insn[31:26];
    wire [3:0]  d_rs = d_insn[25:22];
    wire [3:0]  d_rt = d_insn[21:18];
    wire [3:0]  d_rdf = d_insn[17:14];
    wire [5:0]  d_fn = d_insn[8:3];

    wire d_is_r     = (d_op == OP_R);
    wire d_is_alu_i = (d_op == 6'b001000) || (d_op == 6'b001001) || (d_op == 6'b010000) ||
                      (d_op == 6'b010001) || (d_op == 6'b010010) || (d_op == 6'b010011) ||
                      (d_op == 6'b011000) || (d_op == 6'b011001) || (d_op == 6'b011010) ||
                      (d_op == OP_LUI);
    wire d_is_ld    = (d_op == OP_LD);
    wire d_is_st    = (d_op == OP_ST);
    wire d_is_cond  = (d_op == OP_BMI) || (d_op == OP_BPL) || (d_op == OP_BZ);
    wire d_is_jump  = (d_op == OP_BR);
    wire d_is_halt  = (d_op == OP_HALT);
    // NOP, HALT and undefined opcodes (only ever on a wrong path) need no execution
    wire d_needs_rs = d_is_r || d_is_alu_i || d_is_ld || d_is_st || d_is_cond || d_is_jump;

    wire       d_rd_we = d_is_r || d_is_alu_i || d_is_ld;
    wire [3:0] d_dest  = d_is_r ? d_rdf : d_rt;
    wire d_uses_rs = d_is_r || (d_is_alu_i && d_op != OP_LUI) || d_is_ld || d_is_st || d_is_cond;
    wire d_uses_rt = d_is_st || (d_is_r && (d_fn == F_ADD || d_fn == F_SUB || d_fn == F_SLT ||
                     d_fn == F_SGT || d_fn == F_AND || d_fn == F_OR || d_fn == F_XOR ||
                     d_fn == F_NOR || d_fn == F_CMOV));
    wire [31:0] d_pred_next = d_pred_taken ? d_pred_target : (d_pc + 1);

    // architectural register file (committed state); read at dispatch
    wire [31:0] arf_rs, arf_rt;
    wire [3:0]  commit_rd;
    wire [31:0] commit_value;
    wire        commit_rd_we;
    register_bank RB(
        .clk(clk), .reset(reset),
        .read_reg1(d_rs), .read_reg2(d_rt),
        .read_data1(arf_rs), .read_data2(arf_rt),
        .write_reg(commit_rd), .write_data(commit_value), .write_enable(commit_rd_we)
    );

    // result buses (driven by the functional units below)
    wire          cdb0_valid, cdb1_valid;
    wire [TW-1:0] cdb0_tag,   cdb1_tag;
    wire [31:0]   cdb0_value, cdb1_value;

    // Operand capture: ARF if not renamed, else a finished ROB entry, else a
    // result bus broadcasting this cycle, else wait on the tag.
    reg          op1_rdy, op2_rdy;
    reg [31:0]   op1_val, op2_val;
    reg [TW-1:0] op1_tag, op2_tag;
    always @(*) begin
        op1_tag = rat_tag[d_rs];
        op2_tag = rat_tag[d_rt];
        // source 1
        if (!d_uses_rs)                                     begin op1_rdy = 1'b1; op1_val = 32'd0; end
        else if (!rat_busy[d_rs])                           begin op1_rdy = 1'b1; op1_val = arf_rs; end
        else if (rob_done[op1_tag])                         begin op1_rdy = 1'b1; op1_val = rob_value[op1_tag]; end
        else if (cdb0_valid && cdb0_tag == op1_tag)         begin op1_rdy = 1'b1; op1_val = cdb0_value; end
        else if (cdb1_valid && cdb1_tag == op1_tag)         begin op1_rdy = 1'b1; op1_val = cdb1_value; end
        else                                                begin op1_rdy = 1'b0; op1_val = 32'd0; end
        // source 2
        if (!d_uses_rt)                                     begin op2_rdy = 1'b1; op2_val = 32'd0; end
        else if (!rat_busy[d_rt])                           begin op2_rdy = 1'b1; op2_val = arf_rt; end
        else if (rob_done[op2_tag])                         begin op2_rdy = 1'b1; op2_val = rob_value[op2_tag]; end
        else if (cdb0_valid && cdb0_tag == op2_tag)         begin op2_rdy = 1'b1; op2_val = cdb0_value; end
        else if (cdb1_valid && cdb1_tag == op2_tag)         begin op2_rdy = 1'b1; op2_val = cdb1_value; end
        else                                                begin op2_rdy = 1'b0; op2_val = 32'd0; end
    end

    // free reservation-station slot (lowest index)
    reg          rs_free_v;
    reg [SW-1:0] rs_free;
    always @(*) begin : free_slot
        integer i;
        rs_free_v = 1'b0;
        rs_free   = {SW{1'b0}};
        for (i = RS_ENTRIES - 1; i >= 0; i = i - 1)
            if (!rs_valid[i]) begin rs_free_v = 1'b1; rs_free = i[SW-1:0]; end
    end

    wire flush;                      // commit of a mispredicted control instruction
    localparam integer ROB_N = ROB_ENTRIES;
    wire rob_full = (count == ROB_N[TW:0]);
    wire dispatch = d_valid && !flush && !halted_r &&
                    !rob_full && (!d_needs_rs || rs_free_v);
    wire stall_F  = d_valid && !dispatch;

    // =========================================================================
    //   ISSUE SELECT (oldest ready first)
    // =========================================================================
    // a store whose address/data are not known yet blocks younger loads
    reg st_pending [0:ROB_ENTRIES-1];
    always @(*) begin : st_pend
        integer j;
        for (j = 0; j < ROB_ENTRIES; j = j + 1)
            st_pending[j] = rob_valid[j] && rob_is_store[j] && !rob_done[j];
    end

    reg ld_blocked [0:RS_ENTRIES-1];
    always @(*) begin : ld_block
        integer i, j;
        for (i = 0; i < RS_ENTRIES; i = i + 1) begin
            ld_blocked[i] = 1'b0;
            for (j = 0; j < ROB_ENTRIES; j = j + 1)
                if (st_pending[j] && (age(j[TW-1:0]) < age(rs_tag[i]))) ld_blocked[i] = 1'b1;
        end
    end

    reg          alu_sel_v, lsu_sel_v;
    reg [SW-1:0] alu_sel,   lsu_sel;
    reg [TW-1:0] alu_age,   lsu_age;
    always @(*) begin : select
        integer i;
        alu_sel_v = 1'b0; alu_sel = {SW{1'b0}}; alu_age = {TW{1'b1}};
        lsu_sel_v = 1'b0; lsu_sel = {SW{1'b0}}; lsu_age = {TW{1'b1}};
        for (i = 0; i < RS_ENTRIES; i = i + 1) begin
            if (rs_valid[i] && !rs_is_mem[i] && rs_rdy1[i] && rs_rdy2[i] &&
                (!alu_sel_v || age(rs_tag[i]) < alu_age)) begin
                alu_sel_v = 1'b1; alu_sel = i[SW-1:0]; alu_age = age(rs_tag[i]);
            end
            if (rs_valid[i] && rs_is_mem[i] && rs_rdy1[i] &&
                (rs_is_ld[i] ? !ld_blocked[i] : rs_rdy2[i]) &&
                (!lsu_sel_v || age(rs_tag[i]) < lsu_age)) begin
                lsu_sel_v = 1'b1; lsu_sel = i[SW-1:0]; lsu_age = age(rs_tag[i]);
            end
        end
    end

    // =========================================================================
    //   FU0: ALU / branch
    // =========================================================================
    wire [31:0] a_insn = rs_insn[alu_sel];
    wire [31:0] a_pc   = rs_pc[alu_sel];
    wire [31:0] a_v1   = rs_v1[alu_sel];
    wire [31:0] a_v2   = rs_v2[alu_sel];
    wire [5:0]  a_op   = a_insn[31:26];
    wire [5:0]  a_fn   = a_insn[8:3];
    wire [31:0] a_imm  = {{16{a_insn[17]}}, a_insn[17:2]};
    wire [31:0] a_imm26 = {{6{a_insn[25]}}, a_insn[25:0]};

    wire [31:0] alu_out;
    wire        alu_zero, alu_ovf;
    ALU_unit ALU(
        .A(a_v1), .B((a_op == OP_R) ? a_v2 : a_imm), .opcode(a_op), .funct(a_fn),
        .shift_amount((a_op == OP_R) ? a_insn[13:9] : a_imm[4:0]),
        .zeroFlag(alu_zero), .overflowFlag(alu_ovf), .Out(alu_out)
    );
    wire a_is_move = (a_op == OP_R) && (a_fn == F_MOVE);
    wire a_is_cmov = (a_op == OP_R) && (a_fn == F_CMOV);
    wire [31:0] a_result = a_is_cmov ? (($signed(a_v1) < $signed(a_v2)) ? a_v1 : a_v2) :
                           a_is_move ? a_v1 : alu_out;

    wire a_is_jump = (a_op == OP_BR);
    wire a_is_cond = (a_op == OP_BMI) || (a_op == OP_BPL) || (a_op == OP_BZ);
    wire [2:0] a_brop = a_is_jump ? 3'b000 : (a_op == OP_BMI) ? 3'b001 :
                        (a_op == OP_BPL) ? 3'b010 : (a_op == OP_BZ) ? 3'b011 : 3'b100;
    wire a_take;
    branch_comparator BC(.brOp(a_brop), .data(a_v1), .take_branch(a_take));
    wire [31:0] a_target  = a_is_jump ? a_imm26 : (a_pc + a_imm);
    wire [31:0] a_next    = a_take ? a_target : (a_pc + 1);
    wire        a_mispred = (a_next != rs_pred_next[alu_sel]);

    assign cdb0_valid = alu_sel_v;
    assign cdb0_tag   = rs_tag[alu_sel];
    assign cdb0_value = a_result;

    // =========================================================================
    //   FU1: load / store
    // =========================================================================
    // memories are 256 words: only address bits [7:0] matter (sum mod 256)
    wire [7:0]  m_addr = rs_v1[lsu_sel][7:0] + rs_insn[lsu_sel][9:2];
    wire        m_is_ld = rs_is_ld[lsu_sel];
    wire [TW-1:0] m_tag = rs_tag[lsu_sel];

    // youngest older store to the same address (all older stores are done)
    reg          fwd_hit;
    reg [31:0]   fwd_data;
    reg [TW-1:0] fwd_age;
    always @(*) begin : forward
        integer j;
        fwd_hit = 1'b0; fwd_data = 32'd0; fwd_age = {TW{1'b0}};
        for (j = 0; j < ROB_ENTRIES; j = j + 1)
            if (rob_valid[j] && rob_is_store[j] && rob_done[j] &&
                age(j[TW-1:0]) < age(m_tag) && rob_st_addr[j] == m_addr &&
                (!fwd_hit || age(j[TW-1:0]) > fwd_age)) begin
                fwd_hit = 1'b1; fwd_data = rob_st_data[j]; fwd_age = age(j[TW-1:0]);
            end
    end

    // data memory: read port for loads, write port for committing stores
    wire [31:0] dmem_rdata;
    wire        commit_store;
    wire [7:0]  commit_st_addr;
    wire [31:0] commit_st_data;
    ooo_dmem MEM(
        .clk(clk), .reset(reset),
        .raddr(m_addr), .rdata(dmem_rdata),
        .we(commit_store), .waddr(commit_st_addr), .wdata(commit_st_data)
    );

    wire        ld_issue = lsu_sel_v && m_is_ld;
    wire        st_issue = lsu_sel_v && !m_is_ld;
    wire [31:0] ld_value = fwd_hit ? fwd_data : dmem_rdata;

    // fixed-latency load pipeline: value appears on CDB1 MEM_LATENCY cycles
    // after issue (same cycle when MEM_LATENCY == 1)
generate
if (MEM_LATENCY == 1) begin : g_lat1
    assign cdb1_valid = ld_issue;
    assign cdb1_tag   = m_tag;
    assign cdb1_value = ld_value;
end else begin : g_latn
    reg          lp_v   [1:MEM_LATENCY-1];
    reg [TW-1:0] lp_tag [1:MEM_LATENCY-1];
    reg [31:0]   lp_val [1:MEM_LATENCY-1];
    integer k;
    always @(posedge clk) begin
        if (reset || flush) begin
            for (k = 1; k < MEM_LATENCY; k = k + 1) lp_v[k] <= 1'b0;
        end else begin
            lp_v[1] <= ld_issue; lp_tag[1] <= m_tag; lp_val[1] <= ld_value;
            for (k = 2; k < MEM_LATENCY; k = k + 1) begin
                lp_v[k] <= lp_v[k-1]; lp_tag[k] <= lp_tag[k-1]; lp_val[k] <= lp_val[k-1];
            end
        end
    end
    assign cdb1_valid = lp_v[MEM_LATENCY-1];
    assign cdb1_tag   = lp_tag[MEM_LATENCY-1];
    assign cdb1_value = lp_val[MEM_LATENCY-1];
end
endgenerate

    // =========================================================================
    //   COMMIT
    // =========================================================================
    assign commit         = !halted_r && rob_valid[h] && rob_done[h];
    assign flush          = commit && rob_mispred[h] && !rob_is_halt[h];
    assign commit_rd_we   = commit && rob_rd_we[h];
    assign commit_rd      = rob_rd[h];
    assign commit_value   = rob_value[h];
    assign commit_store   = commit && rob_is_store[h];
    assign commit_st_addr = rob_st_addr[h];
    assign commit_st_data = rob_st_data[h];

    assign ret_valid     = commit;
    assign ret_pc        = rob_pc[h];
    assign ret_insn      = rob_insn[h];
    assign ret_rd_we     = commit_rd_we;
    assign ret_rd        = rob_rd[h];
    assign ret_rd_wdata  = rob_value[h];
    assign ret_mem_we    = commit_store;
    assign ret_mem_addr  = rob_st_addr[h];
    assign ret_mem_wdata = rob_st_data[h];
    assign halted        = halted_r;

    // =========================================================================
    //   SEQUENTIAL UPDATE
    // =========================================================================
    always @(posedge clk) begin : seq
        integer i;
        if (reset) begin
            PC            <= 32'd0;
            halted_r      <= 1'b0;
            dispatch_halt <= 1'b0;
            d_valid       <= 1'b0;
            head <= {TW{1'b0}}; tail <= {TW{1'b0}}; count <= {(TW+1){1'b0}};
            for (i = 0; i < 16; i = i + 1)          rat_busy[i]  <= 1'b0;
            for (i = 0; i < ROB_ENTRIES; i = i + 1) rob_valid[i] <= 1'b0;
            for (i = 0; i < RS_ENTRIES; i = i + 1)  rs_valid[i]  <= 1'b0;
        end else if (flush) begin
            // commit-time recovery: the committing instruction's own effects
            // (register/store/predictor) still happen via the commit_* wires
            PC            <= rob_next_pc[h];
            dispatch_halt <= 1'b0;
            d_valid       <= 1'b0;
            head <= {TW{1'b0}}; tail <= {TW{1'b0}}; count <= {(TW+1){1'b0}};
            for (i = 0; i < 16; i = i + 1)          rat_busy[i]  <= 1'b0;
            for (i = 0; i < ROB_ENTRIES; i = i + 1) rob_valid[i] <= 1'b0;
            for (i = 0; i < RS_ENTRIES; i = i + 1)  rs_valid[i]  <= 1'b0;
        end else begin
            // ---------------- fetch -> F/D
            if (!stall_F) begin
                if (dispatch_halt || (dispatch && d_is_halt) || halted_r) begin
                    d_valid <= 1'b0;                   // nothing past a HALT
                end else begin
                    d_valid       <= 1'b1;
                    d_insn        <= insn_F;
                    d_pc          <= PC;
                    d_pred_taken  <= pred_taken_F;
                    d_pred_target <= pred_target_F;
                    d_pht_idx     <= pht_idx_F;
                    PC            <= pred_taken_F ? pred_target_F : (PC + 1);
                end
            end
            if (dispatch && d_is_halt) dispatch_halt <= 1'b1;

            // ---------------- commit
            if (commit) begin
                rob_valid[h] <= 1'b0;
                head <= head + 1'b1;
                if (rob_is_halt[h]) halted_r <= 1'b1;
                if (rob_rd_we[h] && rat_busy[rob_rd[h]] && rat_tag[rob_rd[h]] == h)
                    rat_busy[rob_rd[h]] <= 1'b0;        // overridden below by a same-cycle rename
            end
            count <= count + {{TW{1'b0}}, dispatch} - {{TW{1'b0}}, commit};

            // ---------------- results
            if (cdb0_valid) begin
                rob_done[cdb0_tag]  <= 1'b1;
                rob_value[cdb0_tag] <= cdb0_value;
                if (a_is_cond || a_is_jump) begin
                    rob_mispred[cdb0_tag] <= a_mispred;
                    rob_next_pc[cdb0_tag] <= a_next;
                    rob_taken[cdb0_tag]   <= a_take;
                    rob_target[cdb0_tag]  <= a_target;
                end
            end
            if (cdb1_valid) begin
                rob_done[cdb1_tag]  <= 1'b1;
                rob_value[cdb1_tag] <= cdb1_value;
            end
            if (st_issue) begin
                rob_done[m_tag]    <= 1'b1;
                rob_st_addr[m_tag] <= m_addr;
                rob_st_data[m_tag] <= rs_v2[lsu_sel];
            end

            // ---------------- reservation stations: issue + wake-up
            if (alu_sel_v) rs_valid[alu_sel] <= 1'b0;
            if (lsu_sel_v) rs_valid[lsu_sel] <= 1'b0;
            for (i = 0; i < RS_ENTRIES; i = i + 1) begin
                if (rs_valid[i] && !rs_rdy1[i]) begin
                    if (cdb0_valid && cdb0_tag == rs_q1[i])      begin rs_rdy1[i] <= 1'b1; rs_v1[i] <= cdb0_value; end
                    else if (cdb1_valid && cdb1_tag == rs_q1[i]) begin rs_rdy1[i] <= 1'b1; rs_v1[i] <= cdb1_value; end
                end
                if (rs_valid[i] && !rs_rdy2[i]) begin
                    if (cdb0_valid && cdb0_tag == rs_q2[i])      begin rs_rdy2[i] <= 1'b1; rs_v2[i] <= cdb0_value; end
                    else if (cdb1_valid && cdb1_tag == rs_q2[i]) begin rs_rdy2[i] <= 1'b1; rs_v2[i] <= cdb1_value; end
                end
            end

            // ---------------- dispatch: rename + allocate
            if (dispatch) begin
                tail <= tail + 1'b1;
                rob_valid[tail]    <= 1'b1;
                rob_done[tail]     <= !d_needs_rs;              // NOP / HALT complete at once
                rob_pc[tail]       <= d_pc;
                rob_insn[tail]     <= d_insn;
                rob_rd_we[tail]    <= d_rd_we;
                rob_rd[tail]       <= d_dest;
                rob_value[tail]    <= 32'd0;
                rob_is_store[tail] <= d_is_st;
                rob_is_halt[tail]  <= d_is_halt;
                rob_is_cond[tail]  <= d_is_cond;
                rob_is_jump[tail]  <= d_is_jump;
                rob_pht_idx[tail]  <= d_pht_idx;
                rob_taken[tail]    <= 1'b0;
                rob_target[tail]   <= 32'd0;
                // non-control instructions: a taken prediction is a mispredict
                rob_mispred[tail]  <= d_pred_taken && !(d_is_cond || d_is_jump);
                rob_next_pc[tail]  <= d_pc + 1;
                if (d_rd_we) begin
                    rat_busy[d_dest] <= 1'b1;
                    rat_tag[d_dest]  <= tail;
                end
                if (d_needs_rs) begin
                    rs_valid[rs_free]     <= 1'b1;
                    rs_tag[rs_free]       <= tail;
                    rs_insn[rs_free]      <= d_insn;
                    rs_pc[rs_free]        <= d_pc;
                    rs_pred_next[rs_free] <= d_pred_next;
                    rs_is_mem[rs_free]    <= d_is_ld || d_is_st;
                    rs_is_ld[rs_free]     <= d_is_ld;
                    rs_rdy1[rs_free]      <= op1_rdy;
                    rs_q1[rs_free]        <= op1_tag;
                    rs_v1[rs_free]        <= op1_val;
                    rs_rdy2[rs_free]      <= op2_rdy;
                    rs_q2[rs_free]        <= op2_tag;
                    rs_v2[rs_free]        <= op2_val;
                end
            end
        end
    end

`ifndef SYNTHESIS
    // =========================================================================
    //   INVARIANTS (checked by testbench/ooo_sva.sv)
    // =========================================================================
    reg dbg_rat_ok, dbg_rs_ok, dbg_count_ok;
    always @(*) begin : invariants
        integer i, j;
        dbg_rat_ok = 1'b1;
        for (i = 0; i < 16; i = i + 1)
            if (rat_busy[i] && !(rob_valid[rat_tag[i]] && rob_rd_we[rat_tag[i]] && rob_rd[rat_tag[i]] == i[3:0]))
                dbg_rat_ok = 1'b0;
        dbg_rs_ok = 1'b1;
        for (i = 0; i < RS_ENTRIES; i = i + 1)
            if (rs_valid[i] && !(rob_valid[rs_tag[i]] && !rob_done[rs_tag[i]]))
                dbg_rs_ok = 1'b0;
        dbg_count_ok = 1'b1;
        j = 0;
        for (i = 0; i < ROB_ENTRIES; i = i + 1) if (rob_valid[i]) j = j + 1;
        if (j[TW:0] != count) dbg_count_ok = 1'b0;
    end
`endif

endmodule

// Data memory with separate read (loads, at issue) and write (stores, at
// commit) ports. The array is named 'memory' like memory.v so testbenches
// can preload and inspect it the same way.
module ooo_dmem(
    input             clk,
    input             reset,
    input      [7:0]  raddr,
    output     [31:0] rdata,
    input             we,
    input      [7:0]  waddr,
    input      [31:0] wdata
);
    reg [31:0] memory [0:255];
    integer i;
    initial for (i = 0; i < 256; i = i + 1) memory[i] = 32'h0;
    assign rdata = memory[raddr];
    always @(posedge clk)
        if (we && !reset) memory[waddr] <= wdata;
endmodule
