`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.04.2026 15:35:44
// Design Name: 
// Module Name: MUX
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

module MUX_2to1(input A, input B, input select, output Out);
    assign Out = (select)?B:A;
endmodule

module MUX32_2to1 (input [31:0] A, input [31:0] B, input select, output [31:0] Out);

    MUX_2to1 MUX0(A[0], B[0], select, Out[0]);
    MUX_2to1 MUX1(A[1], B[1], select, Out[1]);
    MUX_2to1 MUX2(A[2], B[2], select, Out[2]);
    MUX_2to1 MUX3(A[3], B[3], select, Out[3]);
    MUX_2to1 MUX4(A[4], B[4], select, Out[4]);
    MUX_2to1 MUX5(A[5], B[5], select, Out[5]);
    MUX_2to1 MUX6(A[6], B[6], select, Out[6]);
    MUX_2to1 MUX7(A[7], B[7], select, Out[7]);
    MUX_2to1 MUX8(A[8], B[8], select, Out[8]);
    MUX_2to1 MUX9(A[9], B[9], select, Out[9]);
    MUX_2to1 MUX10(A[10], B[10], select, Out[10]);
    MUX_2to1 MUX11(A[11], B[11], select, Out[11]);
    MUX_2to1 MUX12(A[12], B[12], select, Out[12]);
    MUX_2to1 MUX13(A[13], B[13], select, Out[13]);
    MUX_2to1 MUX14(A[14], B[14], select, Out[14]);
    MUX_2to1 MUX15(A[15], B[15], select, Out[15]);
    MUX_2to1 MUX16(A[16], B[16], select, Out[16]);
    MUX_2to1 MUX17(A[17], B[17], select, Out[17]);
    MUX_2to1 MUX18(A[18], B[18], select, Out[18]);
    MUX_2to1 MUX19(A[19], B[19], select, Out[19]);
    MUX_2to1 MUX20(A[20], B[20], select, Out[20]);
    MUX_2to1 MUX21(A[21], B[21], select, Out[21]);
    MUX_2to1 MUX22(A[22], B[22], select, Out[22]);
    MUX_2to1 MUX23(A[23], B[23], select, Out[23]);
    MUX_2to1 MUX24(A[24], B[24], select, Out[24]);
    MUX_2to1 MUX25(A[25], B[25], select, Out[25]);
    MUX_2to1 MUX26(A[26], B[26], select, Out[26]);
    MUX_2to1 MUX27(A[27], B[27], select, Out[27]);
    MUX_2to1 MUX28(A[28], B[28], select, Out[28]);
    MUX_2to1 MUX29(A[29], B[29], select, Out[29]);
    MUX_2to1 MUX30(A[30], B[30], select, Out[30]);
    MUX_2to1 MUX31(A[31], B[31], select, Out[31]);
endmodule
