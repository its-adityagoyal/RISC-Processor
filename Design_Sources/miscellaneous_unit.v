`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.04.2026 23:10:23
// Design Name: 
// Module Name: miscellaneous_unit
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


module miscellaneous_unit(input [31:0] In, input [2:0] select_function, output reg [31:0] Out);
    wire [31:0] ham_out, lui_out;
    ham_unit HAMU(In, ham_out);
    lui_unit LUIU(In[15:0], lui_out);
    
    always @(*) begin
        case(select_function)
            0: Out = ham_out;
            1: Out = lui_out;
            default: Out = 32'd0;
        endcase
    end
endmodule
