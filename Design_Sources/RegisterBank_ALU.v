`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.04.2026 00:00:14
// Design Name: 
// Module Name: RegisterBank_ALU
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


module RegisterBank_ALU(input clk, input reset, input [31:0] instruction, input write_enable, output [31:0] Out, output zeroFlag, output overflowFlag);
    wire [5:0] opcode = instruction [31:26];
    wire [3:0] rs = instruction [25:22];
    wire [3:0] rt = instruction [21:18];
    wire [3:0] rd = instruction [17:14];
    wire [4:0] shift_amount = instruction [13:9];
    wire [5:0] funct = instruction [8:3];
    wire [15:0] immediate = instruction [17:2];
    wire [25:0] jump_address = instruction [25:0];
    
    wire [31:0] read_data1, read_data2, write_data;
    reg [3:0] write_reg;
    register_bank RB(clk, reset, rs, rt, read_data1, read_data2, write_reg, write_data, write_enable);
    
    wire [31:0] immediate_extension = {{16{immediate[15]}}, immediate};
    
    reg [31:0] A, B;
    reg [5:0] ALU_funct;
    reg [4:0] ALU_shift;
    always @(*) begin
        if(opcode == 6'b000000) begin
            if(funct[5:3] == 3'b001 | funct[5:3]== 3'b010 | funct[5:3]== 3'b011) begin
                A = read_data1;
                B = read_data2;
                write_reg = rd;
                ALU_funct = funct;
                ALU_shift = shift_amount;
            end 
            else if(funct[5:3] == 3'b100) begin   //For HAM, B do not matter
                A = read_data1;
                B = {32{1'bx}};
                write_reg = rd;
                ALU_funct = funct;
                ALU_shift = 5'bxxxxx;
            end
            else if(funct == 6'b101000) begin   //MOVE (opcode remains same but change the funct to ADD)
                A = read_data1;
                B = 0;
                write_reg = rt;
                ALU_funct = 6'b001000;
                ALU_shift = 5'bxxxxx;
            end
            else if(funct == 6'b101001) begin   //CMOVE (opcode remains same but change the funct to ADD)
                if(read_data1 < read_data2) begin
                    A = read_data1;
                end
                else begin
                    A = read_data2;
                end
                B = 0;
                write_reg = rd;
                ALU_funct = 6'b001000;
                ALU_shift = 5'bxxxxx;
            end
        end
        else begin
            if(opcode[5:3] == 3'b011) begin
                A = read_data1;
                B = {32{1'bx}}; 
                ALU_shift = immediate [4:0]; //It must contain the shift_amount
                write_reg = rt;
                ALU_funct = 6'bxxxxxx;
            end
            else if(opcode[5:3] == 3'b100) begin  //LUI
                A = {16'd0, immediate}; 
                B = {32{1'bx}};
                write_reg = rt;
                ALU_funct = 6'bxxxxxx;
                ALU_shift = 5'bxxxxx;
            end
            else begin
                A = read_data1;
                B = immediate_extension;
                write_reg = rt;
                ALU_funct = 6'bxxxxxx;
                ALU_shift = 5'bxxxxx;
            end
        end
    end
    
    ALU_MiniRISC uut(A, B, opcode, ALU_funct, ALU_shift, zeroFlag, overflowFlag, write_data);
    assign Out = write_data;
endmodule
