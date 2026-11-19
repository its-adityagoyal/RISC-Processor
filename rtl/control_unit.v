`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.05.2026 22:50:40
// Design Name: 
// Module Name: control_unit
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


module control_unit(
        input [5:0] opcode,
        input [5:0] funct,
        
        output reg regWrite,
        output reg memRead,
        output reg memWrite,
        output reg DRselect,
        output reg [2:0] brOp,
        output reg regselect,
        output reg isCMOVE,
        output reg immediateselect
    );
    // Opcode
    localparam [5:0] R_TYPE = 6'b000000;
    
    localparam [5:0] ADDI = 6'b001000;
    localparam [5:0] SUBI = 6'b001001;
    
    localparam [5:0] ANDI = 6'b010000;
    localparam [5:0] ORI = 6'b010001;
    localparam [5:0] XORI = 6'b010010;
    localparam [5:0] NORI = 6'b010011;
    
    localparam [5:0] SLAI = 6'b011000;
    localparam [5:0] SRLI = 6'b011001;
    localparam [5:0] SRAI = 6'b011010;
    
    localparam [5:0] LUI = 6'b100001;
    
    localparam [5:0] LD = 6'b101010;
    localparam [5:0] ST = 6'b101011;
    
    localparam [5:0] BR = 6'b110000;
    localparam [5:0] BMI = 6'b110001;
    localparam [5:0] BPL = 6'b110010;
    localparam [5:0] BZ = 6'b110011;
    
    localparam [5:0] HALT = 6'b111000;
    localparam [5:0] NOP = 6'b111001;
    
    // Functions for R_TYPE
    localparam [5:0] F_ADD = 6'b001000;
    localparam [5:0] F_SUB = 6'b001001;
    localparam [5:0] F_INC = 6'b001010;
    localparam [5:0] F_DEC = 6'b001011;
    localparam [5:0] F_SLT = 6'b001100;
    localparam [5:0] F_SGT = 6'b001101;
    
    localparam [5:0] F_AND = 6'b010000;
    localparam [5:0] F_OR = 6'b010001;
    localparam [5:0] F_XOR = 6'b010010;
    localparam [5:0] F_NOR = 6'b010011;
    localparam [5:0] F_NOT = 6'b010100;
    
    localparam [5:0] F_SL = 6'b011000;
    localparam [5:0] F_SRL = 6'b011001;
    localparam [5:0] F_SRA = 6'b011010;
    
    localparam [5:0] F_HAM = 6'b100000;
    
    localparam [5:0] F_MOVE = 6'b101000;
    localparam [5:0] F_CMOVE = 6'b101001;
    
    always @(*) begin
        regWrite = 1'b0;
        memRead = 1'b0;
        memWrite = 1'b0;
        brOp = 3'b100;
        DRselect = 1'b0;   // If 0 then DR get's value from Register else from Immediate
        regselect = 1'b0;  // If 1 destination register is rd else rt
        isCMOVE = 1'b0;
        immediateselect = 1'b0; // If 0 then take 16 bit immediate else 26 bit immediate
        
        case(opcode)
            R_TYPE: begin
                DRselect = 1'b0; 
                regWrite = 1'b1;
                regselect = 1'b1; 
                
                if(funct == F_CMOVE) begin
                    isCMOVE = 1'b1;
                end
            end
            
            ADDI, SUBI, ANDI, ORI, XORI, NORI, SLAI, SRLI, SRAI, LUI: begin
                regselect = 1'b0; 
                regWrite = 1'b1;
                DRselect = 1'b1;
            end
            
            LD: begin
                regselect = 1'b0; 
                regWrite = 1'b1;
                memRead = 1'b1;
                DRselect = 1'b1;
            end
            
            ST: begin 
                regselect = 1'b0; 
                regWrite = 1'b0;
                memWrite = 1'b1;
                DRselect = 1'b1; 
                
            end
            
            BR: begin
                DRselect = 1'b1;
                brOp = 3'b000;
                immediateselect = 1'b1;
            end       
            BMI: begin
                DRselect = 1'b1;
                brOp = 3'b001;
                immediateselect = 1'b0;
            end
            BPL: begin
                DRselect = 1'b1;
                brOp = 3'b010;
                immediateselect = 1'b0;
            end
            BZ: begin
                DRselect = 1'b1;
                brOp = 3'b011;
                immediateselect = 1'b0;
            end
            
            HALT, NOP: begin
            end
            
            default: begin
            end
        endcase
        //$display("CU: opcode=%b regWrite=%b memRead=%b", opcode, regWrite, memRead);
    end
endmodule
