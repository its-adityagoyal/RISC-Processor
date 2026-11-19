`timescale 1ns / 1ps
// =============================================================================
// branch_predictor -- BTB + configurable direction predictor
//
// Lookup happens in IF (same cycle as the instruction fetch); update happens
// when the control instruction resolves in EX. The PHT index used for the
// prediction travels down the pipeline and comes back as upd_pht_idx, so the
// update always trains the counter that made the prediction.
//
// MODE  0  none     : always predict not-taken (plain pipeline)
//       1  BTFN     : static -- backward taken, forward not taken (needs a
//                     BTB hit to know the target); BR always taken
//       2  bimodal  : 2-bit saturating counters indexed by PC
//       3  gshare   : 2-bit counters indexed by PC xor global history
//
// BTB: direct-mapped, BTB_ENTRIES entries, allocated when a branch or jump is
// TAKEN. Instruction memory is 256 words, so PC[7:0] identifies an
// instruction: tag = PC[7:idx], target stored as 8 bits. A PC outside 0..255
// never hits. Any wrong prediction (direction, target or an aliased hit on a
// non-branch) is caught in EX and costs the normal 2-cycle redirect, so the
// predictor affects performance only, never correctness.
//
// Global history is updated non-speculatively at resolution (simple, no
// repair logic); with branches resolving two stages after fetch, the history
// seen by a lookup can lag by up to two branches.
// =============================================================================
module branch_predictor #(
    parameter MODE        = 2,
    parameter BTB_ENTRIES = 16,
    parameter PHT_ENTRIES = 64,
    parameter GHR_BITS    = 6,
    parameter BTB_IDX_W   = $clog2(BTB_ENTRIES),
    parameter PHT_IDX_W   = $clog2(PHT_ENTRIES)
)(
    input                      clk,
    input                      reset,
    // lookup (IF)
    input      [31:0]          pc_f,
    output                     pred_taken_f,
    output     [31:0]          pred_target_f,
    output     [PHT_IDX_W-1:0] pht_idx_f,
    // update (EX)
    input                      upd_valid,
    input                      upd_is_cond,
    input                      upd_is_jump,
    input      [31:0]          upd_pc,
    input                      upd_taken,
    input      [31:0]          upd_target,
    input      [PHT_IDX_W-1:0] upd_pht_idx
);
    localparam TAG_W = 8 - BTB_IDX_W;

generate
if (MODE == 0) begin : g_none
    assign pred_taken_f  = 1'b0;
    assign pred_target_f = 32'd0;
    assign pht_idx_f     = {PHT_IDX_W{1'b0}};
end else begin : g_bp
    // ------------------------------------------------------------- storage
    reg              btb_valid  [0:BTB_ENTRIES-1];
    reg [TAG_W-1:0]  btb_tag    [0:BTB_ENTRIES-1];
    reg [7:0]        btb_target [0:BTB_ENTRIES-1];
    reg              btb_jump   [0:BTB_ENTRIES-1];
    reg [1:0]        pht        [0:PHT_ENTRIES-1];
    reg [GHR_BITS-1:0] ghr;

    // -------------------------------------------------------------- lookup
    wire [BTB_IDX_W-1:0] bi  = pc_f[BTB_IDX_W-1:0];
    wire                 hit = btb_valid[bi] && (btb_tag[bi] == pc_f[7:BTB_IDX_W]) && (pc_f[31:8] == 24'd0);
    wire [31:0]          tgt = {24'd0, btb_target[bi]};

    wire [PHT_IDX_W-1:0] ghr_ext = ghr;   // zero-extended / truncated to the index width
    assign pht_idx_f = (MODE == 3) ? (pc_f[PHT_IDX_W-1:0] ^ ghr_ext) : pc_f[PHT_IDX_W-1:0];

    wire dir_taken = (MODE == 1) ? (tgt < pc_f)        // backward => taken
                                 : pht[pht_idx_f][1];  // counter MSB
    assign pred_taken_f  = hit && (btb_jump[bi] || dir_taken);
    assign pred_target_f = tgt;

    // -------------------------------------------------------------- update
    wire [BTB_IDX_W-1:0] ui = upd_pc[BTB_IDX_W-1:0];
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < BTB_ENTRIES; i = i + 1) btb_valid[i] <= 1'b0;
            for (i = 0; i < PHT_ENTRIES; i = i + 1) pht[i] <= 2'b01;   // weakly not-taken
            ghr <= {GHR_BITS{1'b0}};
        end else if (upd_valid && (upd_is_cond || upd_is_jump)) begin
            if (upd_taken && upd_pc[31:8] == 24'd0) begin
                btb_valid[ui]  <= 1'b1;
                btb_tag[ui]    <= upd_pc[7:BTB_IDX_W];
                btb_target[ui] <= upd_target[7:0];
                btb_jump[ui]   <= upd_is_jump;
            end
            if (upd_is_cond) begin
                if (upd_taken  && pht[upd_pht_idx] != 2'b11) pht[upd_pht_idx] <= pht[upd_pht_idx] + 2'b01;
                if (!upd_taken && pht[upd_pht_idx] != 2'b00) pht[upd_pht_idx] <= pht[upd_pht_idx] - 2'b01;
                ghr <= {ghr[GHR_BITS-2:0], upd_taken};
            end
        end
    end
end
endgenerate

endmodule
