`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.04.2026 21:59:55
// Design Name: 
// Module Name: logical_unit
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

module logical_unit(input [31:0] A, input [31:0] B, input [2:0] select_function, output reg [31:0] Out);
    //AND, OR, XOR, NOR, NOT
    always @(*) begin
        case(select_function)
            0: Out = A & B;
            1: Out = A | B;
            2: Out = A ^ B;
            3: Out = ~(A|B);
            4: Out = ~A;  //Only NOT OF A is returned
            default: Out = 32'd0;
        endcase
    end
endmodule
