`timescale 1ns / 1ps

module hazard_unit(
    input [3:0] rsD,
    input [3:0] rtD,
    input [3:0] dest_regE,
    input memReadE,
    
    input branch_takenE, // branch is taken in EX
    input jump_takenE,   // absolute jump taken in EX

    output stallF,
    output stallD,
    output flushD,
    output flushE
);

    wire lwStall;
    
    // Load-Use hazard
    assign lwStall = memReadE && ((rsD == dest_regE) || (rtD == dest_regE));
    
    // Stall IF and ID if load-use hazard
    assign stallF = lwStall;
    assign stallD = lwStall;
    
    // Flush ID if control hazard (branch/jump taken)
    assign flushD = branch_takenE || jump_takenE;
    
    // Flush EX if load-use hazard OR control hazard
    assign flushE = lwStall || branch_takenE || jump_takenE;

endmodule
