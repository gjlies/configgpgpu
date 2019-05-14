//************************
// gjlies 04-24-19 Created
// gjlies 04-26-19 Updated FSM to allow warps to execute in parallel with initialization
// gjlies 04-26-19 Added support to track base register value to initialize
//************************
//Description:
//A finite state machine for initializing warps
//Start signal given by global scheduler to distribute a block to a warp
`include "../misc/counter3.sv"
`include "../misc/mux_generic.sv"
module warp_fsm (clk, rst, start, mp_match, bdim, reg_per_thread, wmask_o, tid_o, twe, pwe, twa, wi, pwa, done_o, ready, base_reg);

  parameter BLOCK_DIM = 32;                                                     // Size of block dimensions xyz
  parameter BLOCK_DIM_WIDTH = 10;                                               // Size of individual block dimension
  parameter WARP_WIDTH = 32;                                                    // Number of threads per warp
  parameter NUM_PARAMS = 8;                                                     // Number of supported parameters
  parameter R_ADDR_WIDTH = 10;                                                  // Number of bits in register address
  parameter SP_PER_MP = 8;                                                      // Number of SPs per MP
  
  parameter WARP_DEPTH = $clog2(WARP_WIDTH);                                    // Number of bits to represent a thread
  parameter PARAM_DEPTH = $clog2(NUM_PARAMS);                                   // Number of bits to represent a parameter
  parameter NUM_ROWS = WARP_WIDTH / SP_PER_MP;                                  // Number of rows in a warp
  parameter NUM_ROWS_P1 = NUM_ROWS + 1;                                         // Number of rows + 1 in a warp
  parameter ROW_DEPTH_P1 = $clog2(NUM_ROWS_P1);                                 // Number of bits to represent number of rows + 1
  parameter ROW_DEPTH = $clog2(NUM_ROWS);                                       // Number of bits to represent a row
  
  input clk;                                                                    // Clock
  input rst;                                                                    // Reset
  input start;                                                                  // Start signal to kick off state machine
  input mp_match;                                                               // 1 if global scheduler has selected this MP
  input [BLOCK_DIM - 1 : 0] bdim;                                               // Block dimensions
  input [R_ADDR_WIDTH - 1 : 0] reg_per_thread;                                  // Number of registers per thread
  
  output [WARP_WIDTH - 1 : 0] wmask_o;                                          // Warp mask to store
  output [BLOCK_DIM - 1 : 0] tid_o;                                             // Thread idx to store
  output twe;                                                                   // Write enable for thread idx
  output [WARP_DEPTH - 1 : 0] twa;                                              // Write address for thread idx
  output wi;                                                                    // Signal to initialize a warp
  output [PARAM_DEPTH - 1 : 0] pwa;                                             // Write address for parameters
  output done_o;                                                                // Done signal
  output ready;                                                                 // Signal that the MP is ready for a new block
  output [R_ADDR_WIDTH - 1 : 0] base_reg;                                       // Base regsiter value to use for the warp
  output pwe;                                                                   // Write enable for parameters
  
  reg [1 : 0] state;                                                            // Two state bits

  wire init;                                                                    // State machine input to kick off fsm 
  wire max;                                                                     // State machine input signal that params and threads are done
  wire done;                                                                    // State machine input signal that fsm is done

  wire [1 : 0] next_state;                                                      // Next state bits

  wire state0;                                                                  // fsm in state 0
  wire state1;                                                                  // fsm in state 1
  wire state2;                                                                  // fsm in state 2
  wire state3;                                                                  // fsm in state 3

  wire [BLOCK_DIM_WIDTH - 1 : 0] block_x;                                       // Current x thread index
  wire [BLOCK_DIM_WIDTH - 1 : 0] block_y;                                       // current y thread index
  wire [BLOCK_DIM_WIDTH - 1 : 0] block_z;                                       // current z thread index

  wire block_x_en;                                                              // Enable to increase thread x index
  wire block_x_rst;                                                             // Reset for thread x index
  wire block_y_en;                                                              // Enable to increase thread y index
  wire block_y_rst;                                                             // Reset for thread y index
  wire block_z_en;                                                              // Enable to increase thread z index
  wire block_z_rst;                                                             // Reset for thread z index

  wire block_x_max;                                                             // Signal thread x index is max
  wire block_y_max;                                                             // Signal thread y index is max
  wire block_z_max;                                                             // Signal thread z index is max
  wire block_all_max;                                                           // Signal at max thread index

  wire [WARP_DEPTH - 1 : 0] progress;                                           // Counter to track progress of states 1 and 2
  wire progress_en;                                                             // Signal to increase the progress counter
  wire progress_rst;                                                            // Signal to reset the progress counter

  wire [WARP_DEPTH - 1 : 0] compare;                                            // Comparison value for progress
  wire [WARP_DEPTH - 1 : 0] mux_compare_in [1 : 0];                             // Comparison values to choose

  wire finished;                                                                // Progress is at max

  reg [WARP_WIDTH - 1 : 0] wmask;                                               // Warp mask to initialize warp with
  reg [R_ADDR_WIDTH - 1 : 0] base_reg_val;                                      // Base register value to initialize
  reg [R_ADDR_WIDTH - 1 : 0] base_reg_off;                                      // Register offset value depends on registers needed by threads

  //Instantiate DFFs to track state
  always @ (posedge clk or negedge rst) begin
    if(rst == 0) begin
      state[0] <= 0;
      state[1] <= 0;
    end
    else begin
      state[0] <= next_state[0];
      state[1] <= next_state[1];
    end
  end
  
  //kick off thes tate machine if signaled to start and global scheduler has told this MP to start
  assign init = start & mp_match & state0;
  assign max = finished;
  assign done = state3 & block_all_max;
  
  //Next state logic
  
  assign next_state[0] = (~max & state[0]) | (max & state[1] & ~state[0]) | init;
  assign next_state[1] = (max & ~state[1] & state[0]) | (~done & state[1]) | (state[1] & ~state[0]);
  
  //Check what state we are in
  assign state0 = ~state[1] & ~state[0];
  assign state1 = ~state[1] & state[0];
  assign state2 = state[1] & ~state[0];
  assign state3 = state[1] & state[0];
  
  //Counters to track thread IDs
  //Enable block x when in state 10 and not max block
  //Reset when block_x_max and not all max or done
  assign block_x_en = state2 & ~block_all_max;
  assign block_x_rst = rst | done | (block_x_max & ~block_all_max);
  
  //Enable block y when in state 10 and block_x count is at max dimension and not all max
  //Reset when block_y_max and block_x is at max and not all max or when done
  assign block_y_en = state2 & block_x_max & ~block_all_max;
  assign block_y_rst = rst | done | (block_y_max & block_x_max & ~block_all_max);
  
  //Enable block z when in state 10 and block_x and block_y max but not all max
  //Reset only on done
  assign block_z_en = state2 & block_x_max & block_y_max & ~block_all_max;
  assign block_z_rst = rst | done;
  
  
  counter3 #(.COUNT_WIDTH(BLOCK_DIM_WIDTH)) count_x(.clk(clk),
                                                    .rst(block_x_rst),
                                                    .en(block_x_en),
                                                    .up(1'b1),
                                                    .count(block_x));
                                                   
  counter3 #(.COUNT_WIDTH(BLOCK_DIM_WIDTH)) count_y(.clk(clk),
                                                    .rst(block_y_rst),
                                                    .en(block_y_en),
                                                    .up(1'b1),
                                                    .count(block_y));
  
  counter3 #(.COUNT_WIDTH(BLOCK_DIM_WIDTH)) count_z(.clk(clk),
                                                    .rst(block_z_rst),
                                                    .en(block_z_en),
                                                    .up(1'b1),
                                                    .count(block_z));
  
  //Check counts
  assign block_x_max = (block_x == bdim[BLOCK_DIM_WIDTH - 1 : 0]);
  assign block_y_max = (block_y == bdim[2*BLOCK_DIM_WIDTH - 1 : BLOCK_DIM_WIDTH]);
  assign block_z_max = (block_z == bdim[3*BLOCK_DIM_WIDTH - 1 : 2*BLOCK_DIM_WIDTH]);
  assign block_all_max = block_x_max & block_y_max & block_z_max;
  
  //Use a counter to track progress in state 1 and state 2
  //Enable whenever in state1 or state2
  //Reset when moving to another state
  assign progress_en = state1 | state2;
  assign progress_rst = rst | finished;
  counter3 #(.COUNT_WIDTH(WARP_DEPTH)) progress_counter(.clk(clk),
                                                        .rst(progress_rst),
                                                        .en(progress_en),
                                                        .up(1'b1),
                                                        .count(progress));
  
  //Check progress to see if we need to transition
  //Mux to select comparison value, WARP_DEPTH in state1, PARAM_DEPTH in state3
  //Assumed parameter depth is less than warp depth use generate if not
  assign mux_compare_in[1] = WARP_DEPTH - 1;
  assign mux_compare_in[0] = {0,PARAM_DEPTH-1};
  
  
  mux_generic #(.INPUT_WIDTH(WARP_DEPTH),
                .NUM_INPUTS(2)) mux_compare(.in(mux_compare_in),
                                            .sel(state[1]),
                                            .out(compare));
  
  //Done storing thread IDs or Parameters when registers are filled
  //or when we are in state2 and we hit the specified block dimensions.
  //Register with mask to store on warp initialize
  assign finished = (progress == compare) | (state2 & block_all_max); 
  always @ (posedge clk) begin
    if(state3) begin
      wmask <= 0;              //Reset after we store the mask value
    end
    else if(state2) begin
      wmask[progress] <= 1'b1;  //Enable thread if we set the thread ID
    end
  end
  
  //Keep track of base register value to initialize for warps
  always @ (posedge clk or negedge rst) begin
    if(rst == 0) begin
      base_reg_val <= 0;
    end
    else if(state3) begin
      base_reg_val <= base_reg_val + base_reg_off;
    end
  end
  
  //Setup reg value to offset for each warp
  always @ (reg_per_thread) begin
    base_reg_off[ROW_DEPTH - 1 : 0] <= 0;
    base_reg_off[R_ADDR_WIDTH - 1 : ROW_DEPTH_P1 - 1] <= reg_per_thread; 
  end
  
  //Assign outputs
  assign wmask_o = wmask;
  assign tid_o = {0,block_z,block_x,block_y};
  assign twa = progress;
  assign pwa = progress;
  assign wi = state3;
  assign twe = state2;
  assign pwe = state1;
  assign done_o = done;
  assign ready = state0 & ~init;
  assign base_reg = base_reg_val;
  
endmodule
