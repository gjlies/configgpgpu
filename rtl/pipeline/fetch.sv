//************************
// gjlies 04-12-19 Created
// gjlies 04-14-19 Removed Signals just being piped to output
// gjlies 04-18-19 Added PC+1 output for storing next PC
//************************
//Description:
//The fetch stage of the multiprocessor pipeline
`include "../bram/bram_1_1.sv"
module fetch (clk, pc_r, pc_w, we, instr_i, instr_f, pc_p1);

  parameter I_DATA_WIDTH = 32;                                // Size of data per instr cache entry
  parameter I_ADDR_WIDTH = 10;                                // Bits of address for instr cache
  parameter SP_PER_MP = 8;                                    // Number of SPs per MP
  
  input clk;                                                  // Clock
  input [I_ADDR_WIDTH - 1 : 0] pc_r;                          // PC to read
  input [I_ADDR_WIDTH - 1 : 0] pc_w;                          // PC to write (to store instructions)
  input we;                                                   // Write enable
  input [I_DATA_WIDTH - 1 : 0] instr_i;                       // Instruction to write
  
  output [I_DATA_WIDTH - 1 : 0] instr_f;                      // Instruction read
  output [I_ADDR_WIDTH - 1 : 0] pc_p1;                        // Next PC address
  
  //Instantiate a single read, single write port block ram.
  //Reads/Writes new instructions
  bram_1_1 #(.DATA_WIDTH(I_DATA_WIDTH),
             .ADDR_WIDTH(I_ADDR_WIDTH)) instr_cache(.clk(clk), .ra(pc_r), .wa(pc_w), .we(we), .di(instr_i), .dout(instr_f));
  
  //Add 1 to PC for next PC address
  assign pc_p1 = pc_r + 1;
  
endmodule
