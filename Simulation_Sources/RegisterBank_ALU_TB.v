`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.04.2026 03:05:09
// Design Name: 
// Module Name: RegisterBank_ALU_TB
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


`timescale 1ns / 1ps

// Assignment: MiniRISC Register File ALU
// Name: Antariksh Das (23CS10086) and Siddhant Singh (23CS10085)
// Department: Computer Science and Engineering

// This is the test bench of the top module that implements all R type instructions and all I type instructions except LD, ST and branch instructions

module tb_RegisterBank_ALU_CompleteTopModule;

// Inputs
reg clock;
reg reset;
reg button;
reg [31:0] instruction;
reg [3:0] rs, rt, rd;
reg [15:0] immediate;

// Outputs
wire [31:0] result;
wire zeroFlag;
wire overflowFlag;

// Instantiate the UUT
RegisterBank_ALU uut (
    .clk(clock),
    .reset(reset),
    .instruction(instruction),
    .write_enable(button),
    .Out(result),
    .zeroFlag(zeroFlag),
    .overflowFlag(overflowFlag)
);

// Clock generation
initial begin
    clock = 0;
    forever #5 clock = ~clock;
end

// R-type helper parameters
localparam [5:0] R_TYPE = 6'b000000;
localparam [5:0] ADD_F  = 6'b001000;
localparam [5:0] SUB_F  = 6'b001001;
localparam [5:0] INC_F  = 6'b001010;
localparam [5:0] DEC_F  = 6'b001011;
localparam [5:0] SLT_F  = 6'b001100;
localparam [5:0] SGT_F  = 6'b001101;
localparam [5:0] AND_F  = 6'b010000;
localparam [5:0] OR_F   = 6'b010001;
localparam [5:0] XOR_F  = 6'b010010;
localparam [5:0] NOR_F  = 6'b010011;
localparam [5:0] NOT_F  = 6'b010100;
localparam [5:0] SL_F   = 6'b011000;
localparam [5:0] SRL_F  = 6'b011001;
localparam [5:0] SRA_F  = 6'b011010;
localparam [5:0] HAM_F  = 6'b100000;
localparam [5:0] MOVE_F = 6'b101000;
localparam [5:0] CMOV_F = 6'b101001;

// I-type helper parameters
localparam [5:0] ADDI_OP = 6'b001000;
localparam [5:0] SUBI_OP = 6'b001001;
localparam [5:0] ANDI_OP = 6'b010000;
localparam [5:0] ORI_OP  = 6'b010001;
localparam [5:0] XORI_OP = 6'b010010;
localparam [5:0] SLAI_OP = 6'b011000;
localparam [5:0] SRLI_OP = 6'b011001;
localparam [5:0] SRAI_OP = 6'b011010;
localparam [5:0] LUI_OP  = 6'b100001;

integer pass_count = 0, fail_count = 0;

// ---- TASK: Execute Instruction ----
task execute_instruction_R_TYPE;
    input [31:0] instr;
    input [31:0] expected_result;
    begin
        instruction = instr;
        button = 1;
        #10;
        button = 0;
        #20;
        rs = instruction[25:22];
        rt = instruction[21:18];
        rd = instruction[17:14];

        $display("Rs = r%d (Data = %0d), Rt = r%d (Data = %0d), Rd = r%d", rs, uut.RB.registers[rs], rt, uut.RB.registers[rt], rd);

        if (result === expected_result) begin
            pass_count = pass_count + 1;
            $display("PASS | Result = %0d | Expected = %0d | Zero = %b | Overflow = %b",
                    result, expected_result, zeroFlag, overflowFlag);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL | Result = %0d | Expected = %0d | Zero = %b | Overflow = %b",
                    result, expected_result, zeroFlag, overflowFlag);
        end
        $display("================================================\n");
    end
endtask

task execute_instruction_I_TYPE;
    input [31:0] instr;
    input [31:0] expected_result;
    begin
        instruction = instr;
        button = 1;
        #10;
        button = 0;
        #20;
        rs = instruction[25:22];
        rt = instruction[21:18];
        immediate = instruction[17:2];

        $display("Rs = r%d (Data = %0d), Rt = r%d, immediate = %d", rs, uut.RB.registers[rs], rt, immediate);

        if (result === expected_result) begin
            pass_count = pass_count + 1;
            $display("PASS | Result = %0d | Expected = %0d | Zero = %b | Overflow = %b",
                    result, expected_result, zeroFlag, overflowFlag);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL | Result = %0d | Expected = %0d | Zero = %b | Overflow = %b",
                    result, expected_result, zeroFlag, overflowFlag);
        end
        $display("================================================\n");
    end
endtask

// Preload registers
initial begin
    // Initialize waveform dump
    $dumpfile("RegisterBank_ALU_CompleteTopModule_tb.vcd");
    $dumpvars(0, tb_RegisterBank_ALU_CompleteTopModule);

    // Reset
    reset = 1;
    button = 0;
    instruction = 0;
    #20 reset = 0;

    // Initialize register values
    uut.RB.registers[0] = 32'd0;
    uut.RB.registers[1] = 32'd10;
    uut.RB.registers[2] = 32'd20;
    uut.RB.registers[3] = 32'd5;

    #10;
    $display("\n===== Starting Comprehensive ALU Testbench =====");

    // ==== R-TYPE TESTS ====
    // ADD r5 = r0 + r1
    $display("Executing: ADD r5 = r0 + r1");
    execute_instruction_R_TYPE({R_TYPE, 4'd0, 4'd1, 4'd5, 5'b0, ADD_F, 3'b000}, 32'd10);
    // SUB r6 = r2 - r1
    $display("Executing: SUB r6 = r2 - r1");
    execute_instruction_R_TYPE({R_TYPE, 4'd2, 4'd1, 4'd6, 5'b0, SUB_F, 3'b000}, 32'd10);
    // INC r7 = r0 + 1
    $display("Executing: INC r7 = r0 + 1");
    execute_instruction_R_TYPE({R_TYPE, 4'd0, 4'd0, 4'd7, 5'b0, INC_F, 3'b000}, 32'd1);
    // DEC r8 = r3 - 1
    $display("Executing: DEC r8 = r3 - 1");
    execute_instruction_R_TYPE({R_TYPE, 4'd3, 4'd3, 4'd8, 5'b0, DEC_F, 3'b000}, 32'd4);
    // SLT r9 = (r1 < r2)
    $display("Executing: SLT r9 = (r1 < r2)");
    execute_instruction_R_TYPE({R_TYPE, 4'd1, 4'd2, 4'd9, 5'b0, SLT_F, 3'b000}, 32'd1);
    // SGT r10 = (r2 > r1)
    $display("Executing: SGT r10 = (r2 > r1)");
    execute_instruction_R_TYPE({R_TYPE, 4'd2, 4'd1, 4'd10, 5'b0, SGT_F, 3'b000}, 32'd1);
    // AND r11 = r0 & r1
    $display("Executing: AND r11 = r0 & r1");
    execute_instruction_R_TYPE({R_TYPE, 4'd0, 4'd1, 4'd11, 5'b0, AND_F, 3'b000}, 32'd0);
    // OR r12 = r0 | r2
    $display("Executing: OR r12 = r0 | r2");
    execute_instruction_R_TYPE({R_TYPE, 4'd0, 4'd2, 4'd12, 5'b0, OR_F, 3'b000}, 32'd20);
    // XOR r13 = r0 ^ r3
    $display("Executing: XOR r13 = r0 ^ r3");
    execute_instruction_R_TYPE({R_TYPE, 4'd0, 4'd3, 4'd13, 5'b0, XOR_F, 3'b000}, 32'd5);
    // NOR r14 = ~(r0 | r2)
    $display("Executing: NOR r14 = ~(r0 | r2)");
    execute_instruction_R_TYPE({R_TYPE, 4'd0, 4'd2, 4'd14, 5'b0, NOR_F, 3'b000}, ~32'd20);
    // NOT r15 = ~r0
    $display("Executing: NOT r15 = ~r0");
    execute_instruction_R_TYPE({R_TYPE, 4'd0, 4'd0, 4'd15, 5'b0, NOT_F, 3'b000}, ~32'd0);
    // SL r4 = r1 << 1
    $display("Executing: SL r4 = r1 << r3[0] = r1 << 1");
    execute_instruction_R_TYPE({R_TYPE, 4'd1, 4'd3, 4'd4, 5'b0, SL_F, 3'b000}, 32'd20);
    // SRL r5 = r2 >> 1
    $display("Executing: SRL r5 = r2 >> r3[0] = r2 >> 1");
    execute_instruction_R_TYPE({R_TYPE, 4'd2, 4'd3, 4'd5, 5'b0, SRL_F, 3'b000}, 32'd10);
    // SRA r6 = r2 >>> 1
    $display("Executing: SRA r6 = r2 >>> r10[0] = r2 >>> 1");
    execute_instruction_R_TYPE({R_TYPE, 4'd2, 4'd10, 4'd6, 5'b0, SRA_F, 3'b000}, 32'd10);
    // HAM (popcount) of r0
    $display("Executing: HAM (popcount) of r0");
    execute_instruction_R_TYPE({R_TYPE, 4'd0, 4'd0, 4'd7, 5'b0, HAM_F, 3'b000}, 32'd0);
    // MOVE r8 = r1
    $display("Executing: MOVE r8 = r1");
    execute_instruction_R_TYPE({R_TYPE, 4'd1, 4'd8, 4'd0, 5'b0, MOVE_F, 3'b000}, 32'd10);
    // CMOV (conditional move)
    $display("Executing: CMOV (conditional move)");
    execute_instruction_R_TYPE({R_TYPE, 4'd1, 4'd2, 4'd9, 5'b0, CMOV_F, 3'b000}, 32'd10);

    // ==== I-TYPE TESTS ====
    // ADDI r10 = r0 + 5
    $display("Executing: ADDI r10 = r0 + 5");
    execute_instruction_I_TYPE({ADDI_OP, 4'd0, 4'd10, 16'd5, 2'b00}, 32'd5);
    // SUBI r11 = r2 - 3
    $display("Executing: SUBI r11 = r2 - 3");
    execute_instruction_I_TYPE({SUBI_OP, 4'd2, 4'd11, 16'd3, 2'b00}, 32'd17);
    // ANDI r12 = r0 & 0x00FF
    $display("Executing: ANDI r12 = r0 & 0x00FF");
    execute_instruction_I_TYPE({ANDI_OP, 4'd0, 4'd12, 16'h00FF, 2'b00}, 32'd0);
    // ORI r13 = r0 | 0x00FF
    $display("Executing: ORI r13 = r0 | 0x00FF");
    execute_instruction_I_TYPE({ORI_OP, 4'd0, 4'd13, 16'h00FF, 2'b00}, 32'h00FF);
    // XORI r14 = r1 ^ 0x0F0F
    $display("Executing: XORI r14 = r1 ^ 0x0F0F");
    execute_instruction_I_TYPE({XORI_OP, 4'd1, 4'd14, 16'h0F0F, 2'b00}, 32'h0F05);
    // SLAI r15 = r1 << 1
    $display("Executing: SLAI r15 = r1 << 1");
    execute_instruction_I_TYPE({SLAI_OP, 4'd1, 4'd15, 16'd1, 2'b00}, 32'd20);
    // SRLI r3 = r2 >> 1
    $display("Executing: SRLI r3 = r2 >> 1");
    execute_instruction_I_TYPE({SRLI_OP, 4'd2, 4'd3, 16'd1, 2'b00}, 32'd10);
    // SRAI r4 = r2 >>> 1
    $display("Executing: SRAI r4 = r2 >>> 1");
    execute_instruction_I_TYPE({SRAI_OP, 4'd2, 4'd4, 16'd1, 2'b00}, 32'd10);
    // LUI r5 = 0xABCD0000
    $display("Executing: LUI r5 = 0xABCD0000");
    execute_instruction_I_TYPE({LUI_OP, 4'd0, 4'd5, 16'hABCD, 2'b00}, 32'hABCD0000);

    $display("\n===== All Instruction Tests Completed =====");
    $display("Simulation Summary: %0d PASS, %0d FAIL", pass_count, fail_count);
    #50;
    $finish;
end

endmodule
