`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.04.2026 23:42:13
// Design Name: 
// Module Name: arithmetic_unit
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


module arithmetic_unit(input [31:0] A, input [31:0] B, input [2:0] operationcode, output zeroFlag, output overflowFlag, output [31:0] Out, output Cout);
    //Generate In2 (second input of RCA, not B)
    wire [31:0] w;
    wire [31:0] In2;
    
    //Choose In2 based on normal add/subtract or INC/DEC
    MUX32_2to1 MUX1(B, 32'b1, operationcode[1], w);
    
    //If Cin = 0 then In2 = w (addition) or else ~w (subtraction)
    wire Cin = operationcode[0] | operationcode[2];
    MUX32_2to1 MUX2(w, (~w), Cin, In2);      
    
    //Now do RCA with A and In2 with Cin
    wire [31:0] Out_RCA;
    RCA_32bit RCA1(A,In2, Cin, zeroFlag, overflowFlag, Out_RCA , Cout);
    
    //Choose wither between slt or sgt
    wire slt = Out_RCA[31] ^ overflowFlag;
    wire sgt = (~slt)&(~zeroFlag);
    wire [31:0] Out_slt_sgt;
    MUX32_2to1 MUX3({31'b0, slt}, {31'b0, sgt}, operationcode[0], Out_slt_sgt);
    
    //Now choose between output of RCA or slt/sgt
    MUX32_2to1 MUX4(Out_RCA, Out_slt_sgt, operationcode[2], Out);
    
    
endmodule
