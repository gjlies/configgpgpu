//************************
// gjlies 04-20-19 Created
// gjlies 04-21-19 Updated to not select a warp if pipeline isn't ready
//************************
//Description:
//Chooses a warp to execute using round robin scheduling
`include "../misc/priority_encoder.sv"
module warp_scheduler (clk, rst, ready, select, valid, selected);

  parameter NUM_WARPS = 16;                               // Number of warps per MP
  parameter WARPID_DEPTH = $clog2(NUM_WARPS);             // Number of bits to represent a warp
  
  input clk;                                              // Clock
  input rst;                                              // Reset
  input [NUM_WARPS - 1 : 0] ready;                        // Ready bits from each warp
  input select;                                           // Pipeline is ready to select a new warp
  
  output valid;                                           // 1 if a valid warp was chosen (some warp is ready)
  output [WARPID_DEPTH - 1 : 0] selected;                 // Chosen warp to execute
  
  wire [NUM_WARPS - 1 : 0] ready_exe;                     // 1 if warp can execute

  wire none_ready;                                        // 0 if no warps ready to execute

  wire [WARPID_DEPTH - 1 : 0] warp_selected;              // Warp selected to execute

  reg [NUM_WARPS - 1 : 0] mask;                           // Priority encoder mask to ensure round robin

  //Instantiate a priority encoder to select warp to execute
  assign ready_exe = ready & ~mask;                       // Even if warp is ready, mask it if others havent gone yet
  
  //If no warps ready to execute, set masks to 0 to stop blocking those which are ready
  assign none_ready = ~(ready_exe == 0);

  priority_encoder #(.INPUT_WIDTH(NUM_WARPS)) scheduler(.in(ready_exe),
                                                        .out(warp_selected));
  
  //Mask to prevent same warps from executing multiple times before another warp which is ready
  always @ (posedge clk or negedge none_ready) begin
    if(none_ready == 0) begin
      mask <= 0;
    end
    else if(select) begin
      mask[warp_selected] <= 1;
    end
  end
  
  //assign outputs
  assign valid = none_ready & select;
  assign selected = warp_selected;
  
endmodule
