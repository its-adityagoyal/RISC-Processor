`timescale 1ns / 1ps

module forwarding_unit(
    input [3:0] rsE,
    input [3:0] rtE,
    
    input [3:0] dest_regM,
    input regWriteM,
    
    input [3:0] dest_regW,
    input regWriteW,
    
    output reg [1:0] forwardA,
    output reg [1:0] forwardB
);

    always @(*) begin
        // default: 00 = from register file
        forwardA = 2'b00;
        forwardB = 2'b00;
        
        // MEM hazard
        if(regWriteW && (dest_regW == rsE)) begin
            forwardA = 2'b01; // 01 = from WB stage
        end
        if(regWriteW && (dest_regW == rtE)) begin
            forwardB = 2'b01;
        end
        
        // EX hazard (takes precedence over MEM hazard)
        if(regWriteM && (dest_regM == rsE)) begin
            forwardA = 2'b10; // 10 = from MEM stage
        end
        if(regWriteM && (dest_regM == rtE)) begin
            forwardB = 2'b10;
        end
    end

endmodule
