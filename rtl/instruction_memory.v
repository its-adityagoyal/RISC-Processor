`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.05.2026 16:36:17
// Design Name: 
// Module Name: instruction_memory
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// INIT_FILE: optional $readmemh image. Synthesis needs real ROM contents,
// otherwise the never-written memory is a constant and the datapath is
// optimised away. Simulation leaves it empty and loads programs directly.
module instruction_memory #(parameter INIT_FILE = "")
    (input clk, input [7:0] address, output reg [31:0] instruction);
    reg [31:0] instruction_mem [0:255];

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, instruction_mem);
    end

    always @(*) begin
        instruction = instruction_mem[address];
    end
endmodule

//module instruction_memory (
//    input clk,
//    input [7:0] address,
//    output wire [31:0] instruction  // wire, not reg
//);
    
//endmodule


