`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.05.2026 13:09:18
// Design Name: 
// Module Name: memory
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


module memory(
    input clk,
    input reset,
    input memRead,
    input memWrite,
    input [7:0] address,
    input [31:0] writeData,
    output reg [31:0] readData
);

    reg [31:0] memory [0:255];

    integer i;
    initial begin
        for(i=0;i<256;i=i+1) begin
            memory[i] = 32'h0;
        end
    end

    always @(*) begin
        if(memRead) begin
            readData = memory[address];
        end
        else begin
            readData = 32'd0;
        end
    end
    
    // fix: no writes while reset is asserted. At power-up the pipeline
    // registers hold arbitrary values until the first reset edge, and a
    // spurious memWrite would otherwise corrupt data memory.
    always @(posedge clk) begin
        if(memWrite && !reset) begin
            memory[address] <= writeData;
        end
    end
endmodule

//module memory (
//    input clk,
//    input reset,
//    input memRead,
//    input memWrite,
//    input [7:0] address,
//    input [31:0] writeData,
//    output wire [31:0] readData  // wire, not reg
//);
    
//endmodule
