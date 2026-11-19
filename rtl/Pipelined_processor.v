`timescale 1ns / 1ps
// 5-stage in-order MiniRISC pipeline: IF -> ID -> EX -> MEM -> WB
//   * Forwarding from MEM and WB into EX
//   * One-cycle load-use stall
//   * Branches and jumps resolve in EX; IF predicts with branch_predictor
//     (BP_MODE 0 = always not-taken, no prediction). A misprediction
//     costs a 2-cycle redirect; a correct prediction costs nothing.
//   * Register file writes on the falling edge, so WB -> ID needs no bypass
//
// The ret_* ports are a retirement trace (RVFI-style): one record per
// instruction leaving WB, carrying every architectural side effect.
// Testbenches compare it against the golden ISA model, and it gives synthesis
// real outputs so the datapath is not optimised away.

module Pipelined_processor #(
    parameter IMEM_INIT_FILE = "",  // ROM image for synthesis (see instruction_memory)
    parameter BP_MODE        = 0,   // 0 none, 1 BTFN, 2 bimodal, 3 gshare
    parameter BTB_ENTRIES    = 16,
    parameter PHT_ENTRIES    = 64,
    parameter GHR_BITS       = 6,
    parameter MEM_LATENCY    = 1    // load latency in cycles (blocking: stalls the pipe)
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

    // =======================================================
    //   GLOBAL STATE (HALT HANDLING)
    // =======================================================
    reg state;
    localparam S_RUN  = 1'b0;
    localparam S_IDLE = 1'b1;

    // =======================================================
    //   IF STAGE
    // =======================================================
    (* dont_touch = "true" *) reg [31:0] PC;
    wire [31:0] next_PC;
    wire [31:0] instruction_F;
    wire [31:0] instruction_D;

    instruction_memory #(.INIT_FILE(IMEM_INIT_FILE)) IM(
        .clk(clk),
        .address(PC[7:0]),
        .instruction(instruction_F)
    );

    // PC Update Logic
    wire stallF;
    wire branch_takenE;
    wire jump_takenE;
    wire [31:0] jump_branch_targetE;
    wire        redirect_E;          // EX disagrees with the path that was fetched
    wire [31:0] redirect_pc_E;       // the correct next PC

    // -------------------------------------------------------------------
    //   BRANCH PREDICTION (IF lookup, EX update)
    // -------------------------------------------------------------------
    localparam PHT_IDX_W = $clog2(PHT_ENTRIES);
    localparam META_W    = 1 + 32 + PHT_IDX_W;   // {taken, target, pht index}

    wire                 pred_taken_F;
    wire [31:0]          pred_target_F;
    wire [PHT_IDX_W-1:0] pht_idx_F;
    wire                 bp_upd_cond, bp_upd_jump, bp_upd_taken;
    wire [31:0]          bp_upd_pc;
    wire [PHT_IDX_W-1:0] pht_idx_E;
    wire                 bp_upd_valid;

    branch_predictor #(
        .MODE(BP_MODE), .BTB_ENTRIES(BTB_ENTRIES),
        .PHT_ENTRIES(PHT_ENTRIES), .GHR_BITS(GHR_BITS)
    ) BP (
        .clk(clk), .reset(reset),
        .pc_f(PC), .pred_taken_f(pred_taken_F), .pred_target_f(pred_target_F), .pht_idx_f(pht_idx_F),
        .upd_valid(bp_upd_valid), .upd_is_cond(bp_upd_cond), .upd_is_jump(bp_upd_jump),
        .upd_pc(bp_upd_pc), .upd_taken(bp_upd_taken), .upd_target(jump_branch_targetE),
        .upd_pht_idx(pht_idx_E)
    );
    wire [5:0] opcode_W; // Forward declaration for HALT check
    wire valid_W;

    // HALT handling (fix): once a HALT reaches EX every older instruction has
    // already resolved, so it is certainly on the committed path. From then on
    // the younger instructions in IF/ID are squashed and fetch stops, so
    // nothing after HALT can change architectural state.
    wire valid_E;
    wire [5:0] opcode_E;
    wire halt_E = valid_E && (opcode_E == 6'b111000);
    reg  fetch_stop;
    wire kill_younger = halt_E | fetch_stop;

    // advance = 0 while a load is still waiting on a slow data memory
    // (MEM_LATENCY > 1); the whole pipeline in front of MEM then holds.
    wire advance;

    always @(posedge clk) begin
        if(reset) begin
            PC <= 32'd0;
            state <= S_RUN;
            fetch_stop <= 1'b0;
        end
        else begin
            if (halt_E && advance) fetch_stop <= 1'b1;
            if (state == S_RUN) begin
                if (valid_W && opcode_W == 6'b111000) begin // HALT retired
                    state <= S_IDLE;
                end
                else if (advance && !kill_younger && (redirect_E || !stallF)) begin
                    PC <= next_PC;   // a redirect wins over a stall
                end
            end
        end
    end

    // Redirect from EX first, else follow the IF prediction, else fall through.
    assign next_PC = redirect_E   ? redirect_pc_E :
                     pred_taken_F ? pred_target_F : (PC + 1);

    // =======================================================
    //   IF / ID PIPELINE REGISTER
    // =======================================================
    wire [31:0] pc_D;
    wire valid_D;
    wire stallD;
    wire flushD;
    wire [META_W-1:0] meta_D;

    IF_ID #(.META_W(META_W)) if_id_reg(
        .clk(clk),
        .reset(reset),
        .flush((flushD || redirect_E || kill_younger) && advance),
        .stall(stallD || state == S_IDLE || !advance),
        .valid_in(1'b1),
        .instruction_in(instruction_F),
        .pc_in(PC),
        .meta_in({pred_taken_F, pred_target_F, pht_idx_F}),
        .valid_out(valid_D),
        .instruction_out(instruction_D),
        .pc_out(pc_D),
        .meta_out(meta_D)
    );

    // =======================================================
    //   ID STAGE
    // =======================================================
    wire [5:0] opcode_D = instruction_D[31:26];
    wire [3:0] rs_D     = instruction_D[25:22];
    wire [3:0] rt_D     = instruction_D[21:18];
    wire [3:0] rd_D     = instruction_D[17:14];
    wire [5:0] funct_D  = instruction_D[8:3];
    wire [15:0] immediate16_D = instruction_D[17:2];
    wire [25:0] immediate26_D = instruction_D[25:0];

    wire regWrite_D, memRead_D, memWrite_D, DRselect_D;
    wire [2:0] brOp_D;
    wire regselect_D, isCMOVE_D, immediateselect_D;

    control_unit CU(
        .opcode(opcode_D),
        .funct(funct_D),
        .regWrite(regWrite_D),
        .memRead(memRead_D),
        .memWrite(memWrite_D),
        .DRselect(DRselect_D),
        .brOp(brOp_D),
        .regselect(regselect_D),
        .isCMOVE(isCMOVE_D),
        .immediateselect(immediateselect_D)
    );

    wire [31:0] immediate_extension_D = (immediateselect_D == 1'b0) ?
                                        {{16{immediate16_D[15]}}, immediate16_D} :
                                        {{6{immediate26_D[25]}}, immediate26_D};

    wire [3:0] dest_reg_D = (regselect_D == 1'b0) ? rt_D : rd_D;

    wire [31:0] read_data1_D, read_data2_D;
    wire [3:0] write_reg_W;
    wire [31:0] write_data_W;
    wire regWrite_W;

    register_bank RB(
        .clk(clk),
        .reset(reset),
        .read_reg1(rs_D),
        .read_reg2(rt_D),
        .read_data1(read_data1_D),
        .read_data2(read_data2_D),
        .write_reg(write_reg_W),
        .write_data(write_data_W),
        .write_enable(regWrite_W)
    );

    // =======================================================
    //   ID / EX PIPELINE REGISTER
    // =======================================================
    wire flushE;
    wire [31:0] instr_E;
    wire [31:0] pc_E;
    wire [31:0] read_data1_E, read_data2_E, imm_E;
    wire [5:0] funct_E;
    wire [3:0] rs_E, rt_E, dest_reg_E;
    wire regWrite_E, memRead_E, memWrite_E, isCMOVE_E;
    wire [2:0] brOp_E;

    wire [META_W-1:0] meta_E;
    wire [31:0] forwarded_A, forwarded_B;   // EX operands after forwarding

    ID_EX #(.META_W(META_W)) id_ex_reg(
        .clk(clk),
        .reset(reset),
        .hold(!advance),
        .flush(flushE || kill_younger),
        .hold_data1(forwarded_A),
        .hold_data2(forwarded_B),
        .meta_in(meta_D),
        .meta_out(meta_E),
        .valid_in(valid_D),
        .instr_in(instruction_D),
        .pc_in(pc_D),
        .read_data1_in(read_data1_D),
        .read_data2_in(read_data2_D),
        .imm_in(immediate_extension_D),
        .opcode_in(opcode_D),
        .funct_in(funct_D),
        .rs_in(rs_D),
        .rt_in(rt_D),
        .dest_reg_in(dest_reg_D),
        .regWrite_in(regWrite_D),
        .memRead_in(memRead_D),
        .memWrite_in(memWrite_D),
        .brOp_in(brOp_D),
        .isCMOVE_in(isCMOVE_D),
        .valid_out(valid_E),
        .instr_out(instr_E),
        .pc_out(pc_E),
        .read_data1_out(read_data1_E),
        .read_data2_out(read_data2_E),
        .imm_out(imm_E),
        .opcode_out(opcode_E),
        .funct_out(funct_E),
        .rs_out(rs_E),
        .rt_out(rt_E),
        .dest_reg_out(dest_reg_E),
        .regWrite_out(regWrite_E),
        .memRead_out(memRead_E),
        .memWrite_out(memWrite_E),
        .brOp_out(brOp_E),
        .isCMOVE_out(isCMOVE_E)
    );

    // =======================================================
    //   EX STAGE
    // =======================================================
    wire [1:0] forwardA, forwardB;
    wire [31:0] alu_out_M; // forwarded from M

    // Forwarding Muxes (declared above, used by ID/EX while held)
    assign forwarded_A = (forwardA == 2'b10) ? alu_out_M :
                         (forwardA == 2'b01) ? write_data_W : read_data1_E;

    assign forwarded_B = (forwardB == 2'b10) ? alu_out_M :
                         (forwardB == 2'b01) ? write_data_W : read_data2_E;

    wire DRselect_E = (opcode_E != 6'b000000);

    wire [31:0] alu_A = forwarded_A;
    wire [31:0] alu_B = (DRselect_E == 1'b0) ? forwarded_B : imm_E;
    wire [4:0] ALU_shift_E = (opcode_E == 6'b000000) ? imm_E[11:7] : imm_E[4:0];

    wire [31:0] alu_result_E;
    wire zeroFlag_E, overflowFlag_E;

    ALU_unit ALU(
        .A(alu_A),
        .B(alu_B),
        .opcode(opcode_E),
        .funct(funct_E),
        .shift_amount(ALU_shift_E),
        .zeroFlag(zeroFlag_E),
        .overflowFlag(overflowFlag_E),
        .Out(alu_result_E)
    );

    // CMOVE / MOVE / Address Calculation
    wire [31:0] cmove_result_E = ($signed(forwarded_A) < $signed(forwarded_B)) ? forwarded_A : forwarded_B;
    wire isMOVE_E = (opcode_E == 6'b000000 && funct_E == 6'b101000);
    wire isLD_E = (opcode_E == 6'b101010);
    wire isST_E = (opcode_E == 6'b101011);

    wire [31:0] mem_addr_E = forwarded_A + imm_E;

    wire [31:0] final_ex_result_E = (isLD_E || isST_E) ? mem_addr_E :
                                    (isCMOVE_E) ? cmove_result_E :
                                    (isMOVE_E)  ? forwarded_A :
                                    alu_result_E;

    // Branch evaluation
    wire take_branch_E;
    branch_comparator BC(
        .brOp(brOp_E),
        .data(forwarded_A),
        .take_branch(take_branch_E)
    );

    assign branch_takenE = take_branch_E && (opcode_E == 6'b110001 || opcode_E == 6'b110010 || opcode_E == 6'b110011);
    assign jump_takenE   = take_branch_E && (opcode_E == 6'b110000);

    // Target of the control instruction (absolute for BR, PC-relative otherwise).
    // Computed from the opcode, not the outcome, so the BTB learns the right
    // target for jumps and branches alike.
    wire isJump_E = (opcode_E == 6'b110000);
    assign jump_branch_targetE = isJump_E ? imm_E : (pc_E + imm_E);

    // ---- resolve the prediction made in IF ---------------------------------
    wire                 pred_taken_E  = meta_E[META_W-1];
    wire [31:0]          pred_target_E = meta_E[META_W-2 -: 32];
    assign               pht_idx_E     = meta_E[PHT_IDX_W-1:0];

    wire        isCond_E      = (opcode_E == 6'b110001 || opcode_E == 6'b110010 || opcode_E == 6'b110011);
    wire        actual_taken_E = branch_takenE || jump_takenE;
    wire [31:0] fallthrough_E = pc_E + 1;
    wire [31:0] actual_next_E = actual_taken_E ? jump_branch_targetE : fallthrough_E;

    // Refetch from the architecturally correct PC when the direction was
    // mispredicted (incl. a taken prediction on a non-branch) or a taken
    // prediction carried the wrong target. Only acted on when the pipe moves.
    assign redirect_E    = valid_E && advance &&
                           ((pred_taken_E != actual_taken_E) ||
                            (actual_taken_E && (pred_target_E != jump_branch_targetE)));
    assign redirect_pc_E = actual_next_E;

    assign bp_upd_valid = valid_E && advance;
    assign bp_upd_cond  = isCond_E;
    assign bp_upd_jump  = isJump_E;
    assign bp_upd_taken = actual_taken_E;
    assign bp_upd_pc    = pc_E;

    // =======================================================
    //   EX / MEM PIPELINE REGISTER
    // =======================================================
    wire valid_M;
    wire [31:0] instr_M, pc_M;
    wire [31:0] store_data_M;
    wire [5:0] opcode_M;
    wire [3:0] dest_reg_M;
    wire regWrite_M, memRead_M, memWrite_M;

    EX_MEM ex_mem_reg(
        .clk(clk),
        .reset(reset),
        .hold(!advance),
        .valid_in(valid_E),
        .instr_in(instr_E),
        .pc_in(pc_E),
        .alu_out_in(final_ex_result_E),
        .store_data_in(forwarded_B), // data to store
        .opcode_in(opcode_E),
        .dest_reg_in(dest_reg_E),
        .regWrite_in(regWrite_E),
        .memRead_in(memRead_E),
        .memWrite_in(memWrite_E),
        .valid_out(valid_M),
        .instr_out(instr_M),
        .pc_out(pc_M),
        .alu_out_out(alu_out_M),
        .store_data_out(store_data_M),
        .opcode_out(opcode_M),
        .dest_reg_out(dest_reg_M),
        .regWrite_out(regWrite_M),
        .memRead_out(memRead_M),
        .memWrite_out(memWrite_M)
    );

    // =======================================================
    //   MEM STAGE
    // =======================================================
    wire [7:0] memAddress_M = alu_out_M[7:0];
    wire [31:0] memReadData_M;

    // Slow-memory model: a load spends MEM_LATENCY cycles in MEM. The data
    // array is read every cycle; the value is taken on the last one.
    localparam integer MEM_WAIT_LAST = MEM_LATENCY - 1;
    reg  [4:0] mem_wait;                       // cycles this load has waited
    wire       load_in_M = valid_M && memRead_M;
    wire       mem_stall = (MEM_LATENCY > 1) && load_in_M && (mem_wait != MEM_WAIT_LAST[4:0]);
    assign     advance   = !mem_stall;
    always @(posedge clk) begin
        if (reset || !mem_stall) mem_wait <= 5'd0;
        else                     mem_wait <= mem_wait + 5'd1;
    end

    memory MEM(
        .clk(clk),
        .reset(reset),
        .memRead(memRead_M),
        .memWrite(memWrite_M),
        .address(memAddress_M),
        .writeData(store_data_M),
        .readData(memReadData_M)
    );

    // =======================================================
    //   MEM / WB PIPELINE REGISTER
    // =======================================================
    wire [31:0] instr_W, pc_W;
    wire [31:0] mem_data_W;
    wire [31:0] alu_out_W;
    wire [31:0] store_data_W;
    wire memRead_W, memWrite_W;

    MEM_WB mem_wb_reg(
        .clk(clk),
        .reset(reset),
        .bubble(!advance),
        .valid_in(valid_M),
        .instr_in(instr_M),
        .pc_in(pc_M),
        .mem_data_in(memReadData_M),
        .alu_out_in(alu_out_M),
        .store_data_in(store_data_M),
        .opcode_in(opcode_M),
        .dest_reg_in(dest_reg_M),
        .regWrite_in(regWrite_M),
        .memRead_in(memRead_M),
        .memWrite_in(memWrite_M),
        .valid_out(valid_W),
        .instr_out(instr_W),
        .pc_out(pc_W),
        .mem_data_out(mem_data_W),
        .alu_out_out(alu_out_W),
        .store_data_out(store_data_W),
        .opcode_out(opcode_W),
        .dest_reg_out(write_reg_W),
        .regWrite_out(regWrite_W),
        .memRead_out(memRead_W),
        .memWrite_out(memWrite_W)
    );

    // =======================================================
    //   WB STAGE
    // =======================================================
    assign write_data_W = (memRead_W) ? mem_data_W : alu_out_W;

    // =======================================================
    //   HAZARD AND FORWARDING UNITS
    // =======================================================
    hazard_unit HU(
        .rsD(rs_D),
        .rtD(rt_D),
        .dest_regE(dest_reg_E),
        .memReadE(memRead_E),
        .branch_takenE(redirect_E),   // flush on any redirect (mispredict)
        .jump_takenE(1'b0),
        .stallF(stallF),
        .stallD(stallD),
        .flushD(flushD),
        .flushE(flushE)
    );

    forwarding_unit FU(
        .rsE(rs_E),
        .rtE(rt_E),
        .dest_regM(dest_reg_M),
        .regWriteM(regWrite_M),
        .dest_regW(write_reg_W),
        .regWriteW(regWrite_W),
        .forwardA(forwardA),
        .forwardB(forwardB)
    );

    // =======================================================
    //   RETIREMENT TRACE
    // =======================================================
    assign ret_valid     = valid_W;
    assign ret_pc        = pc_W;
    assign ret_insn      = instr_W;
    assign ret_rd_we     = valid_W & regWrite_W;
    assign ret_rd        = write_reg_W;
    assign ret_rd_wdata  = write_data_W;
    assign ret_mem_we    = valid_W & memWrite_W;
    assign ret_mem_addr  = alu_out_W[7:0];
    assign ret_mem_wdata = store_data_W;
    assign halted        = (state == S_IDLE);

endmodule
