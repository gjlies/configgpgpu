//************************
// gjlies 04-20-19 Created
// gjlies 04-27-19 Changed parameters to only write on write enable and block initialize
//************************
//Description:
//Information tracked by a block, shared between warps with the same blockID
`include "../misc/counter.sv"
`include "../bram/bram_1_1.sv"
`include "../misc/mux_generic.sv"
module block (clk, rst, bid, bid_init, num_warp, bdim, gdim, bidx, pwa, param, pwe, bi, bar, wup, src1,
              spec_o, bar_max_o);

  parameter NUM_BLOCKS = 4;                                // Number of blocks per MP
  parameter BLOCKID_DEPTH = $clog2(NUM_BLOCKS);            // Number of bits to represent a block
  parameter NUM_WARPS = 16;                                // Number of warps per MP
  parameter WARPID_DEPTH = $clog2(NUM_WARPS);              // Number of bits to represent a warp
  parameter BLOCK_DIM = 32;                                // Number of bits in block dimension
  parameter GRID_DIM = 32;                                 // Number of bits in grid dimension
  parameter R_DATA_WIDTH = 32;                             // Number of bits in register entry
  parameter SRC_WIDTH = 5;                                 // Number of bits in src of instruction
  parameter NUM_PARAMS = 8;                                // Number of parameters supported
  parameter PARAM_DEPTH = $clog2(NUM_PARAMS);              // Number of bits to represent a parameter
  
  input clk;                                               // Clock
  input rst;                                               // Reset
  input [BLOCKID_DEPTH - 1 : 0] bid;                       // Block Id from pipeline
  input [BLOCKID_DEPTH - 1 : 0] bid_init;                  // Block ID to initialize
  input [WARPID_DEPTH - 1 : 0] num_warp;                   // Number of warps associated with this block
  input [BLOCK_DIM - 1 : 0] bdim;                          // Block dimension xyz
  input [GRID_DIM - 1 : 0] gdim;                           // Grid dimension xyz
  input [GRID_DIM - 1 : 0] bidx;                           // Block idx xyz
  input [R_DATA_WIDTH - 1 : 0] param;                      // Parameter to store into special register
  input pwe;                                               // Write enable to parameter register
  input bi;                                                // Block initialize
  input bar;                                               // Barrier instruction in pipeline
  input wup;                                               // Warp update signal from pipeline
  input [PARAM_DEPTH - 1 : 0] pwa;                         // Parameter write address
  input [SRC_WIDTH - 1 : 0] src1;                          // Src1 offset from instruction in pipeline
  
  output [R_DATA_WIDTH - 1 : 0] spec_o;                    // Selected special value to read
  output bar_max_o;                                        // 1 When all warps have hit barrier
  
  reg [BLOCKID_DEPTH - 1 : 0] cur_bid;                     // Current block ID
  reg [WARPID_DEPTH - 1 : 0] cur_num_warp;                 // Current number of warps associated
  reg [BLOCK_DIM - 1 : 0] cur_bdim;                        // Current block dimensions xyz
  reg [GRID_DIM - 1 : 0] cur_gdim;                         // Current Grid dimensions xyz
  reg [GRID_DIM - 1 : 0] cur_bidx;                         // Current block IDX xyz
  reg valid;                                               // Whether or not the block is valid (in use)

  wire bid_match;                                          // Whether or not the block in pipeline matches this block

  wire bar_count_rst;                                      // Reset for this blocks barrier counter
  wire [WARPID_DEPTH - 1 : 0] bar_count;                   // This blocks barrier count
  wire bar_count_up;                                       // Signal to increment the barrier count

  reg bar_max;                                             // Check to see if barrier counter is at the max

  wire spec_max;                                           // 1 if src1 is Max aside from lower 2 bits
  wire m0;                                                 // Checks if lower 2 bits for src1 are max
  wire m1;                                                 // checks if lower 2 bits of src1 are max - 1 = 2
  wire m2;                                                 // checks if lower 2 bits of src1 are max - 2 = 1

  wire [R_DATA_WIDTH - 1 : 0] param_reg;                   // Read parameter for this block
  wire param_we;                                           // Write enable to parameter register

  wire [R_DATA_WIDTH - 1 : 0] mux_special_i [3 : 0];       // Special data to select from
  wire [1 : 0] mux_special_sel;                            // Specified special data to select

  //Setup block Id, Num of warps, Block DIM, Grid DIM, and block Idx
  always @ (posedge clk) begin
    if(bi) begin
      cur_bid      <= bid_init;
      cur_num_warp <= num_warp;
      cur_bdim     <= bdim;
      cur_gdim     <= gdim;
      cur_bidx     <= bidx;
      valid        <= 1;
    end
  end
  
  //Check if cur_bid is equal to bid from pipeline
  assign bid_match = (cur_bid == bid) & valid;
  
  //Instantiate BAR counter.  Counts how many Warps have hit BAR instruction
  //When Count == current number of warps, then those warps with the matching bid
  //will be reenabled
  assign bar_count_up = bid_match & wup & bar & valid;     // Increase count if warp update, bid is match, and its a bar instruction, and block is valid
  assign bar_count_rst = rst | bar_max;                    // Reset bar counter on max count
  
  counter #(.COUNT_WIDTH(WARPID_DEPTH)) bar_counter(.clk(clk),
                                                    .rst(bar_count_rst),
                                                    .en(bar_count_up),
                                                    .up(bar_count_up),
                                                    .count(bar_count));
  
  //Check if bar count is the same as the number of warps
  always @ (bar_count or cur_num_warp) begin
    if(bar_count == cur_num_warp) begin
      bar_max <= 1;
    end
    else begin
      bar_max <= 0;
    end
  end
  
  //Instantiate block ram to store parameters
  assign param_we = bi & pwe;  //Only write parameters if this block is also initializing
  
  bram_1_1 #(.DATA_WIDTH(R_DATA_WIDTH),
             .ADDR_WIDTH(PARAM_DEPTH)) param_register(.clk(clk),
                                                      .ra(src1[PARAM_DEPTH - 1 : 0]),
                                                      .wa(pwa),
                                                      .we(param_we),
                                                      .di(param),
                                                      .dout(param_reg));
  
  //Check src1 to figure out what special value to pass to pipeline
  //Checks upper bits of src1 to see if they are all 1
  assign spec_max = (~src1[SRC_WIDTH - 1 : 2] == 0);
  
  //Checks lower bits of src1
  assign m0 = src1[0] & src1[1];
  assign m1 = ~src1[0] & src1[1];
  assign m2 = src1[0] & ~src1[1];
  
  //Mux to select special register data
  assign mux_special_i[0] = cur_bidx;
  assign mux_special_i[1] = cur_bdim;
  assign mux_special_i[2] = cur_gdim;
  assign mux_special_i[3] = param_reg;
  
  //select 0 when m0, 1 when m1, 2 when m2, 3 otherwise
  assign mux_special_sel[1] = m2 | (~m0 & ~m1 & ~m2);
  assign mux_special_sel[0] = m1 | (~m0 & ~m1 & ~m2);
  
  
  mux_generic #(.INPUT_WIDTH(R_DATA_WIDTH),
                .NUM_INPUTS(4)) mux_special(.in(mux_special_i),
                                            .sel(mux_special_sel),
                                            .out(spec_o));
    
  //Assign output
  assign bar_max_o = bar_max;
  
endmodule
