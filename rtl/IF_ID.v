`timescale 1ns / 1ps
// IF/ID pipeline register.
// valid marks a real instruction; flushed or reset slots carry valid = 0
// (a bubble) so they never retire or update architectural state.
// meta carries the branch prediction made in IF alongside its instruction.

module IF_ID #(parameter META_W = 1) (
    input clk,
    input reset,
    input flush,
    input stall,

    input              valid_in,
    input [31:0]       instruction_in,
    input [31:0]       pc_in,
    input [META_W-1:0] meta_in,

    output reg              valid_out,
    output reg [31:0]       instruction_out,
    output reg [31:0]       pc_out,
    output reg [META_W-1:0] meta_out
);

always @(posedge clk) begin
    if(reset || flush) begin
        valid_out       <= 1'b0;
        instruction_out <= {6'b111001, 26'd0}; // NOP
        pc_out          <= 32'd0;
        meta_out        <= {META_W{1'b0}};
    end
    else if(!stall) begin
        valid_out       <= valid_in;
        instruction_out <= instruction_in;
        pc_out          <= pc_in;
        meta_out        <= meta_in;
    end
end

endmodule
