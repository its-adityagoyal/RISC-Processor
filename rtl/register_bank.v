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
   
    integer i;
    initial begin
        for(i=0; i<16; i=i+1) begin
            registers[i] = 32'd0;
        end
    end
    
    //Cannot assign value to a wire inside always
    assign read_data1 = registers[read_reg1];
    assign read_data2 = registers[read_reg2];
        
    always @(negedge clk) begin
        
        if(reset) begin
            for(i=0;i<16;i=i+1) begin
                registers[i] <= 32'd0;
            end
        end 
        else if((~reset) & write_enable) begin
            registers[write_reg] <= write_data;
        end
    end
endmodule
