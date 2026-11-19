`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.05.2026 02:25:47
// Design Name: 
// Module Name: branch_comparator
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


module branch_comparator(
    input [2:0] brOp,
    input [31:0] data,
    output take_branch
    );
    
    assign take_branch = (brOp == 3'b000)?1'b1:
                         (brOp == 3'b001)? ($signed(data) < $signed(32'b0)):
                         (brOp == 3'b010)? ($signed(data) > $signed(32'b0)):
                         (brOp == 3'b011)? (data == 32'd0):1'b0;
endmodule
