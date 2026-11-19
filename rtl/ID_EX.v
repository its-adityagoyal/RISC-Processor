`timescale 1ns / 1ps
// ID/EX pipeline register. A flush inserts a bubble (valid = 0, no writes).

module ID_EX #(parameter META_W = 1) (
    input clk,
    input reset,
    input hold,     // keep contents (pipeline frozen); wins over flush
    input flush,
    // While held, the operand registers re-capture the forwarded operands, so
    // a value forwarded from WB on the first frozen cycle is not lost when
    // the producer leaves WB (MEM/WB fills with bubbles during the freeze).
    input [31:0] hold_data1,
    input [31:0] hold_data2,

    input [META_W-1:0] meta_in,
    output reg [META_W-1:0] meta_out,

    input        valid_in,
    input [31:0] instr_in,
    input [31:0] pc_in,
    input [31:0] read_data1_in,
    input [31:0] read_data2_in,
    input [31:0] imm_in,

    input [5:0] opcode_in,
    input [5:0] funct_in,

    input [3:0] rs_in,
    input [3:0] rt_in,
    input [3:0] dest_reg_in,

    input regWrite_in,
    input memRead_in,
    input memWrite_in,
    input [2:0] brOp_in,
    input isCMOVE_in,

    output reg        valid_out,
    output reg [31:0] instr_out,
    output reg [31:0] pc_out,
    output reg [31:0] read_data1_out,
    output reg [31:0] read_data2_out,
    output reg [31:0] imm_out,

    output reg [5:0] opcode_out,
    output reg [5:0] funct_out,

    output reg [3:0] rs_out,
    output reg [3:0] rt_out,
    output reg [3:0] dest_reg_out,

    output reg regWrite_out,
    output reg memRead_out,
    output reg memWrite_out,
    output reg [2:0] brOp_out,
    output reg isCMOVE_out
);

always @(posedge clk) begin
    if(hold && !reset) begin
        read_data1_out <= hold_data1;
        read_data2_out <= hold_data2;
    end
    else if(reset || flush) begin
        meta_out       <= {META_W{1'b0}};
        valid_out      <= 1'b0;
        instr_out      <= {6'b111001, 26'd0}; // NOP
        pc_out         <= 0;
        read_data1_out <= 0;
        read_data2_out <= 0;
        imm_out        <= 0;
        opcode_out     <= 6'b111001; // NOP
        funct_out      <= 0;
        rs_out         <= 0;
        rt_out         <= 0;
        dest_reg_out   <= 0;
        regWrite_out   <= 0;
        memRead_out    <= 0;
        memWrite_out   <= 0;
        brOp_out       <= 3'b100; // No branch
        isCMOVE_out    <= 0;
    end
    else begin
        meta_out       <= meta_in;
        valid_out      <= valid_in;
        instr_out      <= instr_in;
        pc_out         <= pc_in;
        read_data1_out <= read_data1_in;
        read_data2_out <= read_data2_in;
        imm_out        <= imm_in;
        opcode_out     <= opcode_in;
        funct_out      <= funct_in;
        rs_out         <= rs_in;
        rt_out         <= rt_in;
        dest_reg_out   <= dest_reg_in;
        regWrite_out   <= regWrite_in;
        memRead_out    <= memRead_in;
        memWrite_out   <= memWrite_in;
        brOp_out       <= brOp_in;
        isCMOVE_out    <= isCMOVE_in;
    end
end

endmodule
