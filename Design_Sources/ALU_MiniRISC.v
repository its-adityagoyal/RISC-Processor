`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.04.2026 12:04:47
// Design Name: 
// Module Name: ALU_MiniRISC
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


module ALU_MiniRISC(input [31:0] A, input [31:0] B, input [5:0] opcode, input [5:0] funct, input [4:0] shift_amount, output reg zeroFlag, output reg overflowFlag, output reg [31:0] Out);
    //Preparing for Rtype instructions
    wire [2:0] Rtype_unit = (opcode == 6'b000000)? funct[5:3]: opcode[5:3];
    wire [2:0] Rtype_func = (opcode == 6'b000000)? funct[2:0]: opcode[2:0];
    wire [4:0] Rtype_shamt = (opcode == 6'b000000)? {4'b0000, B[0]}: shift_amount;
    
    //Calculating all arithmetic, logical, shifter and miscellaneous unit outputs
    wire [31:0] Out_arithmetic, Out_logical, Out_shifter, Out_miscellaneous;
    wire Cout, arithmetic_overflowFlag, arithmetic_zeroFlag;
    arithmetic_unit AU(A, B, Rtype_func, arithmetic_zeroFlag, arithmetic_overflowFlag, Out_arithmetic, Cout);
    logical_unit LU(A, B, Rtype_func, Out_logical);
    shifter_unit SU(A, Rtype_shamt, Rtype_func, Out_shifter);
    miscellaneous_unit MU(A, Rtype_func, Out_miscellaneous);
    
    localparam ARITHMETIC_UNIT = 3'b001;
    localparam LOGICAL_UNIT = 3'b010;
    localparam SHIFTER_UNIT = 3'b011;
    localparam MISCELLANEOUS_UNIT = 3'b100;
    
    always @(*) begin
        case (Rtype_unit)
             ARITHMETIC_UNIT: begin
                Out = Out_arithmetic;
                overflowFlag = arithmetic_overflowFlag;
                zeroFlag = arithmetic_zeroFlag;
             end
             LOGICAL_UNIT : begin 
                Out = Out_logical;
                overflowFlag =0;
                zeroFlag = (Out==0);
             end
             SHIFTER_UNIT: begin
                Out =  Out_shifter;
                overflowFlag =0;
                zeroFlag = (Out==0);
             end
             MISCELLANEOUS_UNIT: begin
                Out = Out_miscellaneous;
                overflowFlag =0;
                zeroFlag = (Out==0);
             end
             default: begin
                Out = 0;
                overflowFlag =0;
                zeroFlag = (Out==0);
             end
        endcase
    end
endmodule
