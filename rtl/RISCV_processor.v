`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.05.2026 01:06:09
// Design Name: 
// Module Name: RISCV_processor
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


module RISCV_processor #(
    parameter IMEM_INIT_FILE = ""   // ROM image for synthesis (see instruction_memory)
)(
    input clk,
    input reset,

    // Retirement trace (RVFI-style): one record per executed instruction.
    output        ret_valid,
    output [31:0] ret_pc,
    output [31:0] ret_insn,
    output        ret_rd_we,
    output [3:0]  ret_rd,
    output [31:0] ret_rd_wdata,
    output        ret_mem_we,
    output [7:0]  ret_mem_addr,
    output [31:0] ret_mem_wdata,
    output        halted
    );
    
    // =============================
    //          STATE
    // =============================
    reg state;
    localparam S_RUN  = 1'b0;
    localparam S_IDLE = 1'b1;
    
    // ==============================
    //     INSTRUCTION + IM
    // ==============================
    wire [31:0] instruction;
    
    (* dont_touch = "true" *) reg [31:0] PC;
    instruction_memory #(.INIT_FILE(IMEM_INIT_FILE)) IM(
          .clk(clk),
          .address(PC[7:0]),
          .instruction(instruction)
    );
    
    // ==============================
    //       INSTRUCTION DECODE
    // ==============================
    wire [5:0] opcode = instruction [31:26];
    wire [3:0] rs = instruction [25:22];
    wire [3:0] rt = instruction [21:18];
    wire [3:0] rd = instruction [17:14];
    wire [4:0] shift = instruction [13:9];
    wire [5:0] funct = instruction [8:3];
    wire [15:0] immediate16 = instruction [17:2];
    wire [25:0] immediate26 = instruction [25:0];
    wire immediateselect;
    wire [31:0] immediate_extension = (immediateselect == 1'b0)?{{16{immediate16[15]}}, immediate16}:{{6{immediate26[25]}}, immediate26};
    
    
    // ==============================
    //    CONTROL SIGNALS & UNIT
    // ==============================
    wire regWrite;
    wire memRead;
    wire memWrite;
    wire DRselect;
    wire [2:0] brOp;
    wire regselect;
    wire isCMOVE;

    
    control_unit CU(
        .opcode(opcode),
        .funct(funct),
        .regWrite(regWrite),
        .memRead(memRead),
        .memWrite(memWrite),
        .DRselect(DRselect),
        .brOp(brOp),
        .regselect(regselect),
        .isCMOVE(isCMOVE),
        .immediateselect(immediateselect)
    );
    

    // ==============================
    //       REGISTER BANK
    // ==============================
    wire [31:0] read_data1, read_data2;
    wire [31:0] write_data;
    wire [3:0] write_reg;
    
    register_bank RB(
        .clk(clk), 
        .reset(reset),
        .read_reg1(rs),
        .read_reg2(rt),
        .read_data1(read_data1), 
        .read_data2(read_data2), 
        .write_reg(write_reg), 
        .write_data(write_data), 
        .write_enable(regWrite)
    );
    
    // ==============================
    //         DATA MEMORY
    // ==============================
    wire  [7:0]  memAddress;
    wire  [31:0] memWriteData;
    wire [31:0] memReadData;
    
    memory MEM(
        .clk(clk),
        .reset(reset),
        .memRead(memRead),
        .memWrite(memWrite),
        .address(memAddress),
        .writeData(memWriteData),
        .readData(memReadData)
    );
    
    // ==============================
    //            ALU
    // ==============================
    reg [31:0] A, B; 
    wire [31:0] ALU_Out;
    wire [4:0] ALU_shift;
    wire zeroFlag, overflowFlag;
    
    ALU_unit ALU(
        .A(A),
        .B(B),
        .opcode(opcode),
        .funct(funct),
        .shift_amount(ALU_shift),   // fix: was raw 'shift', breaking SLAI/SRLI/SRAI
        .zeroFlag(zeroFlag),
        .overflowFlag(overflowFlag),
        .Out(ALU_Out)
    );
    
    
    
    
    // ==============================
    //            MULTIPLEXING
    // ==============================
    assign write_reg = (regselect == 1'b0)? rt: rd;
    assign write_data = (isCMOVE == 1'b1)? (($signed(read_data1) < $signed(read_data2))? read_data1 : read_data2): 
                        ((memRead == 1'b1)? memReadData: 
                        ((opcode == 6'b000000 && funct == 6'b101000)? read_data1: ALU_Out));
    // 256-word memory: only the low 8 address bits matter (sum mod 256)
    assign memAddress = read_data1[7:0] + immediate_extension[7:0];
    assign memWriteData = (memWrite == 1'b1)? read_data2 : 32'd0;
    assign ALU_shift = (opcode == 6'b000000)? shift: immediate_extension[4 :0];
    always @(*) begin
        A = read_data1;
        B = (DRselect == 1'b0)? read_data2 : immediate_extension;
    end
    
    
    // ==============================
    //            BRANCNING
    // ==============================
    wire take_branch;
    branch_comparator BC(
        .brOp(brOp),
        .data(read_data1),
        .take_branch(take_branch)
    );
    
    // =============================
    //              PC
    // =============================

    reg [31:0] next_PC;
    always @(*) begin
        if (take_branch)
            if (opcode == 6'b110000) begin
                next_PC = immediate_extension;  // absolute jump
            end
            else begin
                next_PC = PC + immediate_extension;
            end  
        else
            next_PC = PC + 1;                    
    end
    
    
    // =============================
    //      SEQUENTIAL LOGIC
    // =============================
    localparam [5:0] HALT = 6'b111000;
    localparam [5:0] NOP  = 6'b111001;
    always @(posedge clk) begin
        if(reset) begin
            PC <= 32'd0; 
            state <= S_RUN;
        end
        else begin
            // Execute based on BRANCH + NORMAL CASE + HALT + NOP
            case(state)
                S_RUN: begin
                    if(opcode == HALT) begin
                        state <= S_IDLE;
                    end
                    else if(opcode == NOP) begin 
                        PC <= PC + 1;
                    end
                    else begin
                        PC <= next_PC;
                    end
                end
                
                S_IDLE: begin
                    PC <= PC;
                end
            endcase
        end
    end

    // =======================================================
    //   RETIREMENT TRACE
    // =======================================================
    wire retiring        = (state == S_RUN) & ~reset;
    assign ret_valid     = retiring;
    assign ret_pc        = PC;
    assign ret_insn      = instruction;
    assign ret_rd_we     = retiring & regWrite;
    assign ret_rd        = write_reg;
    assign ret_rd_wdata  = write_data;
    assign ret_mem_we    = retiring & memWrite;
    assign ret_mem_addr  = memAddress;
    assign ret_mem_wdata = memWriteData;
    assign halted        = (state == S_IDLE);
endmodule
