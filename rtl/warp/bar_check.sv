//************************
// gjlies 04-21-19 Created
//************************
//Description:
//Checks if any blocks have signaled to finish a Barrier
`include "../misc/priority_encoder.sv"
module bar_check (bar_max, valid, selected);

  parameter NUM_BLOCKS = 4;                               // Number of blocks per MP
  parameter BLOCKID_DEPTH = $clog2(NUM_BLOCKS);           // Number of bits to represent a block
  
  input [NUM_BLOCKS - 1 : 0] bar_max;                     // Barrier signals from blocks
  
  output valid;                                           // 1 if any bar_max signals are 1
  output [BLOCKID_DEPTH - 1 : 0] selected;                // Block finishing Barrier
  
  //Instantiate priority encoder to see which block has met the barrier
  wire [BLOCKID_DEPTH - 1 : 0] block_selected;
  priority_encoder #(.INPUT_WIDTH(NUM_BLOCKS)) check(.in(bar_max),
                                                     .out(block_selected));
  
  //assign outputs
  assign valid = (bar_max != 0);
  assign selected = block_selected;
  
endmodule
