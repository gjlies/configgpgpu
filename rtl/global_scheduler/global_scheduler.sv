//************************
// gjlies 04-23-19 Created
// gjlies 04-26-19 Updated to track number of warps in a block
// gjlies 04-27-19 Added support for outputing block idx to initialize
// gjlies 04-27-19 Added outputs for cache addresses
// gjlies 04-27-19 Added outputs for cache data
//************************
//Description:
//Collects information about the kernel, and distributes blocks to warps
`include "../bram/bram_1_1.sv"
`include "../misc/counter.sv"
`include "../bram/bram_1.sv"
`include "../misc/mux_generic.sv"
`include "../misc/counter3.sv"
`include "../misc/priority_encoder.sv"
module global_scheduler (clk, rst, ready, iwe, cwe, dwe, start, mpid, bdim, gdim, param_o, warp_o, reg_o, instr_wa, l1_wa, const_wa, i_data, c_data, l_data, bidx);

  parameter GRID_DIM = 32;                                    // Number of bits in grid dimension xyz
  parameter BLOCK_DIM = 32;                                   // Number of bits in block dimension xyz
  parameter NUM_PARAMS = 8;                                   // Number of supported parameters
  parameter GRID_DIM_WIDTH = 10;                              // Number of bits in single grid dimension
  parameter NUM_MPS = 8;                                      // Number of Multiprocessors
  parameter NUM_WARPS = 16;                                   // Number of warps / MP
  
  parameter R_DATA_WIDTH = 32;                                // Size of register entry
  parameter R_ADDR_WIDTH = 10;                                // Number of bits in register address
  parameter I_DATA_WIDTH = 32;                                // Number of bit in instruction entry
  parameter I_ADDR_WIDTH = 10;                                // Number of bits in instruction address
  parameter C_ADDR_WIDTH = 10;                                // Number of bits in constant address
  parameter L_ADDR_WIDTH = 10;                                // Number of bits in L1 address
  
  parameter K_DATA_WIDTH = 36;                                // Size of data entry in kernel cache
  parameter K_ADDR_WIDTH = 10;                                // Number of address bits in kernel cache
  parameter K_OP_WIDTH = 4;                                   // Number of opcode bits
  parameter K_CONTROL_WIDTH = 9;                              // Number of control signals
  
  parameter PARAM_DEPTH = $clog2(NUM_PARAMS);                 // Number of bits to represent a parameter
  parameter MPID_DEPTH = $clog2(NUM_MPS);                     // Number of bits to represent a MP
  parameter WARPID_DEPTH = $clog2(NUM_WARPS);                 // Number of bits to represent a warp
  
  input clk;                                                  // Clock
  input rst;                                                  // Reset
  input [NUM_MPS - 1 : 0] ready;                              // Ready signals from MPs
  
  output iwe;                                                 // Signal to write to instruction caches
  output cwe;                                                 // Signal to write to constant caches
  output dwe;                                                 // Signal to write to L1 caches
  output start;                                               // Signal to initialize a block to the chosen MP
  output [MPID_DEPTH - 1 : 0] mpid;                           // Chosen MP to initialize a block
  output [BLOCK_DIM - 1 : 0] bdim;                            // Block dimension of block to initialize
  output [GRID_DIM - 1 : 0] gdim;                             // Grid dimension of kernel
  output [R_DATA_WIDTH - 1 : 0] param_o [NUM_PARAMS - 1 : 0]; // Block parameters to initialize
  output [WARPID_DEPTH - 1 : 0] warp_o;                       // Number of warps in a block
  output [R_ADDR_WIDTH - 1 : 0] reg_o;                        // Number of registers per thread in a block
  output [GRID_DIM - 1 : 0] bidx;                             // Block idx of block to initialize
  output [I_ADDR_WIDTH - 1 : 0] instr_wa;                     // Instruction address to write to
  output [C_ADDR_WIDTH - 1 : 0] const_wa;                     // Constant address to write to
  output [L_ADDR_WIDTH - 1 : 0] l1_wa;                        // L1 address to write to
  output [I_DATA_WIDTH - 1 : 0] i_data;                       // Data to store in instruction cache
  output [R_DATA_WIDTH - 1 : 0] c_data;                       // Data tos tore in constant cache
  output [R_DATA_WIDTH - 1 : 0] l_data;                       // Data to store in L1 cache
  
  wire [K_DATA_WIDTH - 1 : 0] kernel_data;                    // Current Kernel instruction
  wire [K_ADDR_WIDTH - 1 : 0] kernel_pointer;                 // Address pointer for kernel instructions
  wire pointer_en;                                            // enable to increase kernel pointer

  wire [K_CONTROL_WIDTH - 1 : 0] control;                     // Control signals for kernel instruction

  reg [GRID_DIM - 1 : 0] cur_grid;                            // Grid dimension of this kernel
  reg [BLOCK_DIM - 1 : 0] cur_block;                          // Block dimension of this kernel

  reg [WARPID_DEPTH - 1 : 0] cur_num_warp;                    // Number of warps per block
  reg [R_ADDR_WIDTH - 1 : 0] cur_reg_thread;                  // Number of registers per thread
  wire [R_DATA_WIDTH - 1 : 0] params [NUM_PARAMS - 1 : 0];    // Parameters of block

  wire [PARAM_DEPTH - 1 : 0] param_pointer;                   // Address pointer for writing parameters
  wire param_en;                                              // Enable to increase address pointer for parameters

  wire [I_ADDR_WIDTH - 1 : 0] instr_pointer;                  // Address pointer for instruction caches
  wire [C_ADDR_WIDTH - 1 : 0] const_pointer;                  // Address pointer for constant caches
  wire [L_ADDR_WIDTH - 1 : 0] l1_pointer;                     // Address pointer for L1 caches

  wire [GRID_DIM_WIDTH - 1 : 0] grid_x;                       // Current x block index
  wire [GRID_DIM_WIDTH - 1 : 0] grid_y;                       // Current y block index
  wire [GRID_DIM_WIDTH - 1 : 0] grid_z;                       // Current z block index
  
  wire grid_x_en;                                             // Enable to increase block x index
  wire grid_y_en;                                             // Enable to increase block y index
  wire grid_z_en;                                             // Enable to increase block z index
  
  wire grid_x_rst;                                            // Signal to reset block x index
  wire grid_y_rst;                                            // Signal to reset block y index

  wire grid_x_max;                                            // Signal block x index is max
  wire grid_y_max;                                            // Signal block y index is max
  wire grid_z_max;                                            // Signal block z index is max
  wire grid_all_max;                                          // Signal all block indexes are max

  wire mp_ready;                                              // Signal that a multiprocessor is ready to initialize a new block
  reg done;                                                   // Signal to track if all blocks have been issued

  wire [MPID_DEPTH - 1 : 0] mp_selected;                      // Multiprocessor ID of selected MP to initialize the next block

  //Instantiate block ram to hold kernel information
  bram_1_1 #(.DATA_WIDTH(K_DATA_WIDTH),
             .ADDR_WIDTH(K_ADDR_WIDTH)) kernel_info(.clk(clk),
                                                    .ra(kernel_pointer),
                                                    .we(1'b0),
                                                    .dout(kernel_data));
  
  //Counter for kernel read address
  //Once starting the kernel, stop reading instructions
  assign pointer_en = ~control[15];
  
  counter #(.COUNT_WIDTH(K_ADDR_WIDTH)) kernel_point(.clk(clk),
                                                     .rst(rst),
                                                     .en(pointer_en),
                                                     .up(1'b1),
                                                     .count(kernel_pointer));
  
  //Instantiate Decode Unit
  gs_decode #(.K_OP_WIDTH(K_OP_WIDTH),
              .K_CONTROL_WIDTH(K_CONTROL_WIDTH)) decoder(.instr_k(kernel_data[K_DATA_WIDTH - 1 : K_DATA_WIDTH - K_OP_WIDTH]),
                                                         .control_k(control));
  
  //Instantiate registers to hold grid and block dimensions, parameters, Number of warps / Block,
  //and Registers / Thread
  always @ (posedge clk or negedge rst) begin
    if(rst == 0) begin
      cur_grid <= 0;
    end
    else if(control[0]) begin
      cur_grid <= kernel_data[GRID_DIM - 1 : 0];
    end
  end
  
  always @ (posedge clk or negedge rst) begin
    if(rst == 0) begin
      cur_block <= 0;
    end
    else if(control[1]) begin
      cur_block <= kernel_data[BLOCK_DIM - 1 : 0];
    end
  end
  
  //Instantiate register for holding warps / block
  always @ (posedge clk or negedge rst) begin
    if(rst == 0) begin
      cur_num_warp <= 0;
    end
    else if(control[6]) begin
      cur_num_warp <= kernel_data[WARPID_DEPTH - 1 : 0];
    end
  end
  
  always @ (posedge clk or negedge rst) begin
    if(rst == 0) begin
      cur_reg_thread <= 0;
    end
    else if(control[7]) begin
      cur_reg_thread <= kernel_data[R_ADDR_WIDTH - 1 : 0];
    end
  end
  
  //Instantiate registers for holding parameter data
  bram_1 #(.DATA_WIDTH(R_DATA_WIDTH),
           .ADDR_WIDTH(PARAM_DEPTH)) param_reg(.clk(clk),
                                               .wa(param_pointer),
                                               .we(param_en),
                                               .di(kernel_data[R_DATA_WIDTH - 1 : 0]),
                                               .dout(params));
  
  //Count for keeping track of parameter pointer
  //If this is a parameter instruction increase the count
  assign param_en = control[2];
  
  counter #(.COUNT_WIDTH(PARAM_DEPTH)) param_point(.clk(clk),
                                                   .rst(rst),
                                                   .en(param_en),
                                                   .up(1'b1),
                                                   .count(param_pointer));
  
  //Counters to keep track of cache addresses
  counter #(.COUNT_WIDTH(I_ADDR_WIDTH)) instr_point(.clk(clk),
                                                    .rst(rst),
                                                    .en(control[3]),
                                                    .up(1'b1),
                                                    .count(instr_pointer));
  
  counter #(.COUNT_WIDTH(C_ADDR_WIDTH)) const_point(.clk(clk),
                                                    .rst(rst),
                                                    .en(control[4]),
                                                    .up(1'b1),
                                                    .count(const_pointer));
                                                      
  counter #(.COUNT_WIDTH(L_ADDR_WIDTH)) l1_point(.clk(clk),
                                                 .rst(rst),
                                                 .en(control[5]),
                                                 .up(1'b1),
                                                 .count(l1_pointer));
  
  //Counters to track which block we are on
  //Don't allow rst or enable if all at max
  //Enable grid_x counter when control[15] is 1 (distributing), and an MP is ready
  //Reset grid_x counter when mp_ready, and count == dimension
  assign grid_x_en = mp_ready & ~grid_all_max;
  assign grid_x_rst = rst | (grid_x_max & ~grid_all_max);
  //Enable grid_y counter when mp_ready and grid_x is at max
  //Reset grid_y when grid_y is at max
  assign grid_y_en = mp_ready & grid_x_max & ~grid_all_max;
  assign grid_y_rst = rst | (grid_y_max & grid_x_max & ~grid_all_max);
  //Enable grid_z counter when mp_ready and grid_x and grid_y are at max
  //Reset only on reset
  assign grid_z_en = mp_ready & grid_x_max & grid_y_max & ~grid_all_max;
  
  counter3 #(.COUNT_WIDTH(GRID_DIM_WIDTH)) count_x(.clk(clk),
                                                   .rst(grid_x_rst),
                                                   .en(grid_x_en),
                                                   .up(1'b1),
                                                   .count(grid_x));
                                                 
  counter3 #(.COUNT_WIDTH(GRID_DIM_WIDTH)) count_y(.clk(clk),
                                                   .rst(grid_y_rst),
                                                   .en(grid_y_en),
                                                   .up(1'b1),
                                                   .count(grid_y));
                                                 
  counter3 #(.COUNT_WIDTH(GRID_DIM_WIDTH)) count_z(.clk(clk),
                                                   .rst(rst),
                                                   .en(grid_z_en),
                                                   .up(1'b1),
                                                   .count(grid_z));
  
  //Check when counts are at max
  assign grid_x_max = (grid_x == cur_grid[GRID_DIM_WIDTH - 1 : 0]);
  assign grid_y_max = (grid_y == cur_grid[2*GRID_DIM_WIDTH - 1 : GRID_DIM_WIDTH]);
  assign grid_z_max = (grid_z == cur_grid[3*GRID_DIM_WIDTH - 1 : 2*GRID_DIM_WIDTH]);
  assign grid_all_max = grid_x_max & grid_y_max & grid_z_max;
  
  //Logic for distributing blocks
  //Or all the ready bits to see if any are ready, check if distributing.
  assign mp_ready = (|ready) & control[15];
  
  //Keep track if last block has been issued
  always @ (posedge clk or negedge rst) begin
    if(rst == 0) begin
      done <= 0;
    end
    else begin
      done <= done | (mp_ready & grid_all_max);
    end
  end
  
  //Instantiate a priority encoder to pick an MP to give the block to
  priority_encoder #(.INPUT_WIDTH(NUM_MPS)) mp_select(.in(ready),
                                                      .out(mp_selected));
  
  
  //Assign outputs
  assign iwe = control[3];
  assign cwe = control[4];
  assign dwe = control[5];
  
  //Only start if mp_ready and we haven't issued the last block
  assign start = mp_ready & ~done;
  assign mpid = mp_selected;
  assign warp_o = cur_num_warp;
  assign bdim = cur_block;
  assign gdim = cur_grid;
  assign reg_o = cur_reg_thread;
  assign bidx = {0, grid_z, grid_y, grid_x};
  assign instr_wa = instr_pointer;
  assign const_wa = const_pointer;
  assign l1_wa = l1_pointer;
  assign i_data = kernel_data[I_DATA_WIDTH - 1 : 0];
  assign c_data = kernel_data[R_DATA_WIDTH - 1 : 0];
  assign l_data = kernel_data[R_DATA_WIDTH - 1 : 0];
  
  genvar gi;
  generate
    for(gi = 0; gi < NUM_PARAMS; gi = gi + 1) begin : parameters
      assign param_o[gi] = params[gi];
    end
  endgenerate
  
endmodule
