`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.04.2026 22:34:54
// Design Name: 
// Module Name: shifter_unit
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

// amount needed is only 0 to 31
//select is either of {0, 1, 2} but still we use 3 bit select
module shifter_unit(input [31:0] In, input [4:0] amount, input [2:0] select_function, output reg [31:0] Out);
    //Shift Left Arithmetic
    //Shift Right Logical
    //Shift Right Arithmetic
    
    always @(*) begin
        case(select_function)
            0: Out = In << amount;
            1: Out = In >> amount;
            2: Out = ($signed(In) >>> amount);
            default: Out = 32'b0;
        endcase
    end
endmodule
