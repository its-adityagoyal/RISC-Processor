`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.04.2026 15:51:54
// Design Name: 
// Module Name: ripple_carry_adder
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
module half_adder(input A, input B, output Sum, output Cout);
    assign Sum = A^B;
    assign Cout = A&B;
endmodule

module full_adder(input A, input B, input Cin, output Sum, output Cout);
    wire Cout1, Cout2, Sum1;
    half_adder HA1(A, B, Sum1, Cout1);
    half_adder HA2(Sum1, Cin, Sum, Cout2);
    assign Cout = Cout1|Cout2;
endmodule

module RCA_32bit(input [31:0] A, input [31:0] B, input Cin, output zeroFlag, output overflowFlag, output [31:0] Sum, output Cout);
    wire [31:0] Carry;
    
    full_adder FA0(A[0], B[0], Cin, Sum[0], Carry[0]);
    full_adder FA1(A[1], B[1], Carry[0], Sum[1], Carry[1]);
    full_adder FA2(A[2], B[2], Carry[1], Sum[2], Carry[2]);
    full_adder FA3(A[3], B[3], Carry[2], Sum[3], Carry[3]);
    full_adder FA4(A[4], B[4], Carry[3], Sum[4], Carry[4]);
    full_adder FA5(A[5], B[5], Carry[4], Sum[5], Carry[5]);
    full_adder FA6(A[6], B[6], Carry[5], Sum[6], Carry[6]);
    full_adder FA7(A[7], B[7], Carry[6], Sum[7], Carry[7]);
    full_adder FA8(A[8], B[8], Carry[7], Sum[8], Carry[8]);
    full_adder FA9(A[9], B[9], Carry[8], Sum[9], Carry[9]);
    full_adder FA10(A[10], B[10], Carry[9], Sum[10], Carry[10]);
    full_adder FA11(A[11], B[11], Carry[10], Sum[11], Carry[11]);
    full_adder FA12(A[12], B[12], Carry[11], Sum[12], Carry[12]);
    full_adder FA13(A[13], B[13], Carry[12], Sum[13], Carry[13]);
    full_adder FA14(A[14], B[14], Carry[13], Sum[14], Carry[14]);
    full_adder FA15(A[15], B[15], Carry[14], Sum[15], Carry[15]);
    full_adder FA16(A[16], B[16], Carry[15], Sum[16], Carry[16]);
    full_adder FA17(A[17], B[17], Carry[16], Sum[17], Carry[17]);
    full_adder FA18(A[18], B[18], Carry[17], Sum[18], Carry[18]);
    full_adder FA19(A[19], B[19], Carry[18], Sum[19], Carry[19]);
    full_adder FA20(A[20], B[20], Carry[19], Sum[20], Carry[20]);
    full_adder FA21(A[21], B[21], Carry[20], Sum[21], Carry[21]);
    full_adder FA22(A[22], B[22], Carry[21], Sum[22], Carry[22]);
    full_adder FA23(A[23], B[23], Carry[22], Sum[23], Carry[23]);
    full_adder FA24(A[24], B[24], Carry[23], Sum[24], Carry[24]);
    full_adder FA25(A[25], B[25], Carry[24], Sum[25], Carry[25]);
    full_adder FA26(A[26], B[26], Carry[25], Sum[26], Carry[26]);
    full_adder FA27(A[27], B[27], Carry[26], Sum[27], Carry[27]);
    full_adder FA28(A[28], B[28], Carry[27], Sum[28], Carry[28]);
    full_adder FA29(A[29], B[29], Carry[28], Sum[29], Carry[29]);
    full_adder FA30(A[30], B[30], Carry[29], Sum[30], Carry[30]);
    full_adder FA31(A[31], B[31], Carry[30], Sum[31], Carry[31]);
    
    assign Cout = Carry[31];
    assign zeroFlag = ~(|Sum);
    assign overflowFlag = Cout ^ Carry[30];
endmodule

