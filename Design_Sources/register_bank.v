`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.04.2026 22:47:29
// Design Name: 
// Module Name: register_bank
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


module register_bank(input clk, input reset,
    //Read from registers
    input [3:0] read_reg1, read_reg2,
    output [31:0] read_data1, read_data2,
    //Write to register
    input [3:0] write_reg,
    input [31:0] write_data,
    input write_enable
    );
    //Total 16 registers (4-bit required)
    reg [31:0] registers [15:0];
    
    //Firstly we cannot assign it outside a loop and secondly we want to initialize only at t=0
    initial begin
        registers[0] = 32'd5;
        registers[0] = 32'd2;
        registers[0] = 32'd1;
        registers[0] = 32'd15;
        registers[0] = 32'd0;
        registers[0] = 32'd0 ;
        registers[0] = 32'd0 ;
        registers[0] = 32'd0 ;
        registers[0] = 32'd0 ;
        registers[0] = 32'd0 ;
        registers[0] = 32'd0 ;
        registers[0] = 32'd0 ;
        registers[0] = 32'd0 ;
        registers[0] = 32'd0 ;
        registers[0] = 32'd0 ;
        registers[0] = 32'd0 ;
    end
    
    //Cannot assign value to a wire inside always
    assign read_data1 = registers[read_reg1];
    assign read_data2 = registers[read_reg2];
        
    integer i;
    always @(posedge clk or posedge reset) begin
        
        if(reset) begin
            for(i=0;i<16;i=i+1) begin
                registers[i] = 32'd0;
            end
        end 
        else if((~reset) & write_enable) begin
            registers[write_reg] = write_data;
        end
    end
endmodule
