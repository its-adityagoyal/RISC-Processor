`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.04.2026 22:20:44
// Design Name: 
// Module Name: ham_unit
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


module ham_unit(input [31:0] In, output reg [31:0] Out);
    integer i;  //Variable inside is not allowed
    always @(*) begin
        Out = 32'd0;
        for (i=0;i<32;i=i+1) begin
            Out = Out + In[i];    
        end
    end
endmodule
    
