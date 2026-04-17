`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.04.2026 17:28:37
// Design Name: 
// Module Name: ALU_MiniRISC_TB
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


module ALU_MiniRISC_TB;
   reg [31:0] A, B;
   reg [5:0] opcode, funct;
   reg [4:0] shamt;
   wire zeroFlag, overflowFlag;
   wire [31:0] Out;
   
   ALU_MiniRISC uut(A, B, opcode, funct, shamt, zeroFlag, overflowFlag, Out);
   
   // Tasks for readability
    task check_op;
        input [31:0] exp_result;
        input exp_zero;
        input exp_overflow;
        begin
            #5;
            if ((Out === exp_result) && (zeroFlag === exp_zero) && (overflowFlag === exp_overflow)) begin
                $display("PASS | Time=%0t | opcode=%b funct=%b | A=%h, B=%h, shamt=%0d | result=%h (expected %h) | zero=%b (expected %b) | overflow=%b (expected %b)",
                         $time, opcode, funct, A, B, shamt, Out, exp_result, zeroFlag, exp_zero, overflowFlag, exp_overflow);
            end else begin
                $display("FAIL | Time=%0t | opcode=%b funct=%b | A=%h, B=%h, shamt=%0d | result=%h (expected %h) | zero=%b (expected %b) | overflow=%b (expected %b)",
                         $time, opcode, funct, A, B, shamt, Out, exp_result, zeroFlag, exp_zero, overflowFlag, exp_overflow);
            end
        end
    endtask
    
   initial begin
        $display("****** Starting ALU Testbench ******");

        // R-TYPE INSTRUCTIONS
        // ADD
        opcode = 6'b000000; funct = 6'b001000; A = 32'd10; B = 32'd20; shamt = 5'bxxxxx; #10 check_op(32'd30, 0, 0);
        // SUB
        opcode = 6'b000000; funct = 6'b001001; A = 32'd50; B = 32'd20; shamt = 5'bxxxxx; #10 check_op(32'd30, 0, 0);
        // AND
        opcode = 6'b000000; funct = 6'b010000; A = 32'hF0F0F0F0; B = 32'h0FF00FF0; shamt = 5'bxxxxx; #10 check_op(32'h00F000F0, 0, 0);
        // OR
        opcode = 6'b000000; funct = 6'b010001; A = 32'h0000FFFF; B = 32'hFFFF0000; shamt = 5'bxxxxx; #10 check_op(32'hFFFFFFFF, 0, 0);
        // XOR
        opcode = 6'b000000; funct = 6'b010010; A = 32'hAAAA5555; B = 32'h5555AAAA; shamt = 5'bxxxxx; #10 check_op(32'hFFFFFFFF, 0, 0);
        // NOR
        opcode = 6'b000000; funct = 6'b010011; A = 32'h0000FFFF; B = 32'hFFFF0000; shamt = 5'bxxxxx; #10 check_op(32'h00000000, 1, 0);
        // NOT
        opcode = 6'b000000; funct = 6'b010100; A = 32'hFFFFFFFF; B = 0; shamt = 5'bxxxxx; #10 check_op(32'h00000000, 1, 0);
        // SLA
        opcode = 6'b000000; funct = 6'b011000; A = 32'h00000001; B = 32'h00000001; shamt = 2; #10 check_op(32'h00000002, 0, 0);
        // SRL
        opcode = 6'b000000; funct = 6'b011001; A = 32'h00000008; B = 32'h00000001; shamt = 2; #10 check_op(32'h00000004, 0, 0);
        // SRA
        opcode = 6'b000000; funct = 6'b011010; A = -32'sd8; B = 32'h00000001; shamt = 2; #10 check_op(-32'sd4, 0, 0);
        // INC
        opcode = 6'b000000; funct = 6'b001010; A = 32'd15; B = {32{1'bx}}; shamt = 5'bxxxxx; #10 check_op(32'd16, 0, 0);
        // DEC
        opcode = 6'b000000; funct = 6'b001011; A = 32'd15; B = {32{1'bx}}; shamt = 5'bxxxxx; #10 check_op(32'd14, 0, 0);
        // SLT
        opcode = 6'b000000; funct = 6'b001100; A = 32'd5; B = 32'd10; shamt = 5'bxxxxx; #10 check_op(32'd1, 0, 0);
        // SGT
        opcode = 6'b000000; funct = 6'b001101; A = 32'd20; B = 32'd10; shamt = 5'bxxxxx;#10 check_op(32'd1, 0, 0);
        // HAM (popcount)
        opcode = 6'b000000; funct = 6'b100000; A = 32'h0000000F; B = {32{1'bx}}; shamt = 5'bxxxxx; #10 check_op(32'd4, 0, 0);

        // I-TYPE INSTRUCTIONS
        // ADDI
        opcode = 6'b001000; funct = 6'bxxxxxx; A = 32'd10; B = 32'd5; shamt = 5'bxxxxx; #10 check_op(32'd15, 0, 0);
        // SUBI
        opcode = 6'b001001; funct = 6'bxxxxxx; A = 32'd20; B = 32'd5; shamt = 5'bxxxxx; #10 check_op(32'd15, 0, 0);
        // ANDI
        opcode = 6'b010000; funct = 6'bxxxxxx; A = 32'hF0F0F0F0; B = 32'h0F0F0F0F; shamt = 5'bxxxxx; #10 check_op(32'h00000000, 1, 0);
        // ORI
        opcode = 6'b010001; funct = 6'bxxxxxx; A = 32'hF0000000; B = 32'h0F0F0F0F; shamt = 5'bxxxxx; #10 check_op(32'hFF0F0F0F, 0, 0);
        // XORI
        opcode = 6'b010010; funct = 6'bxxxxxx; A = 32'hAAAA5555; B = 32'hFFFF0000; shamt = 5'bxxxxx; #10 check_op(32'h55555555, 0, 0);
        // SLAI
        opcode = 6'b011000; funct = 6'bxxxxxx; A = 32'h00000001; B = {32{1'bx}}; shamt = 3; #10 check_op(32'h00000008, 0, 0);
        // SRLI
        opcode = 6'b011001; funct = 6'bxxxxxx; A = 32'h00000008; B = {32{1'bx}}; shamt = 3; #10 check_op(32'h00000001, 0, 0);
        // SRAI
        opcode = 6'b011010; funct = 6'bxxxxxx; A = -32'sd8; B = {32{1'bx}}; shamt = 3; #10 check_op(-32'sd1, 0, 0);
        // LUI (I-type)
        opcode = 6'b100001; funct = 6'bxxxxxx; A = 32'h0000ABCD; B = {32{1'bx}}; shamt = 5'bxxxxx; #10 check_op(32'hABCD0000, 0, 0);

        // EDGE CASES
        // ADD overflow
        opcode = 6'b000000; funct = 6'b001000; A = 32'h7FFFFFFF; B = 32'd1; shamt = 5'bxxxxx; #10 check_op(32'h80000000, 0, 1);
        // SUB overflow
        opcode = 6'b000000; funct = 6'b001001; A = 32'h80000000; B = 32'd1; shamt = 5'bxxxxx; #10 check_op(32'h7FFFFFFF, 0, 1);
        // Zero result
        opcode = 6'b000000; funct = 6'b001001; A = 32'd100; B = 32'd100; shamt = 5'bxxxxx; #10 check_op(32'd0, 1, 0);
        // Large shift SRLI
        opcode = 6'b011001; funct = 6'bxxxxxx; A = 32'h80000000; B = {32{1'bx}}; shamt = 31; #10 check_op(32'h00000001, 0, 0);
        // Large shift SRAI
        opcode = 6'b011010; funct = 6'bxxxxxx; A = -32'sd1; B = {32{1'bx}}; shamt = 31; #10 check_op(32'hFFFFFFFF, 0, 0);
        // ANDI all-ones
        opcode = 6'b010000; funct = 6'bxxxxxx; A = 32'h12345678; B = 32'hFFFFFFFF; shamt = 5'bxxxxx; #10 check_op(32'h12345678, 0, 0);
        // XORI self-zero
        opcode = 6'b010010; funct = 6'bxxxxxx; A = 32'hABCD1234; B = 32'hABCD1234; shamt = 5'bxxxxx; #10 check_op(32'h0, 1, 0);

        $display("****** Testbench Complete ******");
        $finish;
    end

endmodule
