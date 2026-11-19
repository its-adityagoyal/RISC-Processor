`timescale 1ns / 1ps
// EX/MEM pipeline register.

module EX_MEM(
    input clk,
    input reset,
    input hold,     // keep contents while a load waits on memory

    input        valid_in,
    input [31:0] instr_in,
    input [31:0] pc_in,
    input [31:0] alu_out_in,
    input [31:0] store_data_in,

    input [5:0] opcode_in,
    input [3:0] dest_reg_in,

    input regWrite_in,
    input memRead_in,
    input memWrite_in,

    output reg        valid_out,
    output reg [31:0] instr_out,
    output reg [31:0] pc_out,
    output reg [31:0] alu_out_out,
    output reg [31:0] store_data_out,

    output reg [5:0] opcode_out,
    output reg [3:0] dest_reg_out,

    output reg regWrite_out,
    output reg memRead_out,
    output reg memWrite_out
);

always @(posedge clk) begin
    if(reset) begin
        valid_out      <= 0;
        instr_out      <= {6'b111001, 26'd0}; // NOP
        pc_out         <= 0;
        alu_out_out    <= 0;
        store_data_out <= 0;
        opcode_out     <= 6'b111001; // NOP
        dest_reg_out   <= 0;
        regWrite_out   <= 0;
        memRead_out    <= 0;
        memWrite_out   <= 0;
    end
    else if(!hold) begin
        valid_out      <= valid_in;
        instr_out      <= instr_in;
        pc_out         <= pc_in;
        alu_out_out    <= alu_out_in;
        store_data_out <= store_data_in;
        opcode_out     <= opcode_in;
        dest_reg_out   <= dest_reg_in;
        regWrite_out   <= regWrite_in;
        memRead_out    <= memRead_in;
        memWrite_out   <= memWrite_in;
    end
end

endmodule
