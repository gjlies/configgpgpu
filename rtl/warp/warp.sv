//************************
// gjlies 04-16-19 created
// gjlies 04-21-19 Removed valid input
// gjlies 04-21-19 Added support for resetting state when BAR finished
// gjlies 04-26-19 Added support for tracking number of registers required per thread
//************************
//Description:
//All information tracked by a single warp
`include "../bram/bram_1.sv"
`include "../misc/mux_generic.sv"
module warp (clk, rst, wid_init, wid, bid, wpc, wpc_p1, label, base_addr, reg_per_thread, wstate, wmask, wi, control, contention, tid_wa, tid_d, tid_we, bar_id,
             bar_rst, diverge, ssy_en, take_branch, next_mask, stack_mask, wup, exit, enter_id, enter, ready, pc_o, base_addr_o, valid_o, wmask_o, tid_o, wid_o,
             bid_o, reg_per_thread_o);
  
  parameter NUM_WARPS = 16;                                     // Number of warps per MP
  parameter WARPID_DEPTH = $clog2(NUM_WARPS);                   // Number of bits to represent a warp
  parameter NUM_BLOCKS = 8;                                     // Number of blocks per MP
  parameter BLOCKID_DEPTH = $clog2(NUM_BLOCKS);                 // Number of bits to represent a block
  parameter I_ADDR_WIDTH = 10;                                  // Number of address bits in isntruction cache
  parameter R_ADDR_WIDTH = 10;                                  // Number of address bits in register
  parameter CONTROL_WIDTH = 20;                                 // Number of control bits
  parameter WARP_WIDTH = 32;                                    // Number of threads per warp
  parameter WARP_DEPTH = $clog2(WARP_WIDTH);                    // Number of bits to represent a thread
  parameter BLOCK_DIM = 32;                                     // Number of bits in thread ID
  
  input clk;                                                    // Clock
  input rst;                                                    // Reset
  input [WARPID_DEPTH - 1 : 0] wid_init;                        // Warp ID for initialize
  input [WARPID_DEPTH - 1 : 0] wid;                             // Warp ID from pipeline
  input [BLOCKID_DEPTH - 1 : 0] bid;                            // Block ID
  input [I_ADDR_WIDTH - 1 : 0] wpc;                             // Warp PC
  input [I_ADDR_WIDTH - 1 : 0] wpc_p1;                          // Warp PC + 1
  input [I_ADDR_WIDTH - 1 : 0] label;                           // Label to branch to or ssy pc
  input [R_ADDR_WIDTH - 1 : 0] base_addr;                       // Base register address
  input [R_ADDR_WIDTH - 1 : 0] reg_per_thread;                  // Number of registers per thread
  input [1 : 0] wstate;                                         // Warp state from pipeline
  input [WARP_WIDTH - 1 : 0] wmask;                             // Warp thread mask
  input wi;                                                     // Warp Initialize
  input [CONTROL_WIDTH - 1 : 0] control;                        // Control bits from pipeline
  input contention;                                             // ldst contention
  input diverge;                                                // Threads diverging in pipeline
  input [WARP_DEPTH - 1 : 0] tid_wa;                            // Write address to thread ids
  input [BLOCK_DIM - 1 : 0] tid_d;                              // Thread id data to store
  input tid_we;                                                 // Write enable to thread id register
  input ssy_en;                                                 // Signal from pipeline to push sync pc
  input take_branch;                                            // Branch taken from pipeline
  input [WARP_WIDTH - 1 : 0] next_mask;                         // Next warp mask
  input [WARP_WIDTH - 1 : 0] stack_mask;                        // Next stack mask to push
  input wup;                                                    // Signal from pipeline to update warp
  input exit;                                                   // Signal to exit the warp (Done processing)
  input [WARPID_DEPTH - 1 : 0] enter_id;                        // Warp chosen to enter pipeline
  input enter;                                                  // Warp is entering pipeline
  input [BLOCKID_DEPTH - 1 : 0] bar_id;                         // Block ID issuing BAR reset
  input bar_rst;                                                // All warps at barrier, reset state
  
  output ready;                                                 // Warp is ready to execute
  output [I_ADDR_WIDTH - 1 : 0] pc_o;                           // Current warp pc to read
  output [R_ADDR_WIDTH - 1 : 0] base_addr_o;                    // Base register address to read
  output valid_o;                                               // Whether or not the warp is valid
  output [WARP_WIDTH - 1 : 0] wmask_o;                          // Warp mask to use when executing
  output [BLOCK_DIM - 1 : 0] tid_o [WARP_WIDTH - 1 : 0];        // Thread Ids
  output [WARPID_DEPTH - 1 : 0] wid_o;                          // Current warp ID
  output [BLOCKID_DEPTH - 1 : 0] bid_o;                         // Current block ID
  output [R_ADDR_WIDTH - 1 : 0] reg_per_thread_o;               // Registers per thread
  
  wire update;                                                  // Signal to update this warp

  wire [I_ADDR_WIDTH - 1 : 0] pc_not_taken;                     // Not taken path PC
  wire [WARP_WIDTH - 1 : 0] cur_stack_mask;                     // current stack mask
  wire mask_update;                                             // Signal to update the warp mask
  wire converge;                                                // Signal that the path is converging
  wire pc_update;                                               // Signal to update the warp PC

  reg [WARPID_DEPTH - 1 : 0] cur_wid;                           // This warp's warp ID
  reg [BLOCKID_DEPTH - 1 : 0] cur_bid;                          // This warp's Block ID
  reg [R_ADDR_WIDTH - 1 : 0] cur_base_addr;                     // This warp's base register address
  reg [R_ADDR_WIDTH - 1 : 0] cur_reg_per_thread;                // This warp's registers per thread

  wire bar_id_match;                                            // Check if pipeline block ID matches this warp's block ID

  reg cur_valid;                                                // Whether or not the warp is valid

  reg [I_ADDR_WIDTH - 1 : 0] cur_pc;                            // This warp's current PC

  wire [I_ADDR_WIDTH - 1 : 0] mux_next_pc_i [7 : 0];            // Next PC choice
  wire [2 : 0] mux_next_pc_sel;                                 // Selector for next pc choice
  wire [I_ADDR_WIDTH - 1 : 0] mux_next_pc;                      // Next PC to choose

  reg [WARP_WIDTH - 1 : 0] cur_mask;                            // This warp's current thread mask
  wire [WARP_WIDTH - 1 : 0] converge_mask;                      // The converge mask to update to

  reg [1 : 0] cur_state;                                        // This warp's current state
  
  wire w_enter;                                                 // Warp is entering the pipeline

  wire [I_ADDR_WIDTH - 1 : 0] mux_pc_o_i [1 : 0];               // PC to give to pipeline

  wire [WARP_WIDTH - 1 : 0] mux_mask_o_i [3 : 0];               // Thread mask to give to pipeline
  wire [1 : 0] mux_mask_sel;                                    // Selector to choose thread mask

  //Only update warp if wup and wid matches this warps wid
  //and the warp is valid
  assign update = wup & (wid == cur_wid) & cur_valid;
  
  //Setup stack
  warp_stack #(.CONTROL_WIDTH(CONTROL_WIDTH),
               .I_ADDR_WIDTH(I_ADDR_WIDTH),
               .WARP_WIDTH(WARP_WIDTH)) stack(.clk(clk),
                                              .rst(rst),
                                              .wup(update),
                                              .contention(contention),
                                              .control(control),
                                              .diverge(diverge),
                                              .cur_pc(cur_pc),
                                              .cur_pc_p1(wpc_p1),
                                              .ssy_en(ssy_en),
                                              .ssy_pc_i(label),
                                              .cur_mask(cur_mask),
                                              .stack_mask_i(stack_mask),
                                              .pc_o(pc_not_taken),
                                              .smask_o(cur_stack_mask),
                                              .mask_update(mask_update),
                                              .converge(converge),
                                              .pc_update(pc_update));
  
  //Setup registers to hold thread IDs
  bram_1 #(.DATA_WIDTH(BLOCK_DIM),
           .ADDR_WIDTH(WARP_DEPTH)) thread_ids(.clk(clk),
                                               .wa(tid_wa),
                                               .we(tid_we),
                                               .di(tid_d),
                                               .dout(tid_o));
                                               
  //Update the warp values
  //Warp ID, Block ID, base address, and registers per thread set on initialize
  always @ (posedge clk) begin
    if(wi) begin
      cur_wid            <= wid_init;
      cur_bid            <= bid;
      cur_base_addr      <= base_addr;
      cur_reg_per_thread <= reg_per_thread;
    end
  end
  
  //Check if cur_bid == bar_id for reseting state
  assign bar_id_match = (cur_bid == bar_id) & cur_valid;
  
  //Valid bit is set on initialize or reset on exit
  always @ (posedge clk or negedge rst) begin
    if(rst == 0) begin
      cur_valid <= 0;
    end
    else if(wi) begin
      cur_valid <= 1;
    end
    else if(exit) begin
      cur_valid <= 0;
    end
  end
  
  //Only update PC on update, or initialize
  //Mux to control next value of warp pc
  assign mux_next_pc_i[0] = wpc;
  assign mux_next_pc_i[1] = wpc_p1;
  assign mux_next_pc_i[2] = label;
  assign mux_next_pc_i[3] = cur_pc;
  assign mux_next_pc_i[4] = pc_not_taken;
  assign mux_next_pc_i[5] = pc_not_taken;
  assign mux_next_pc_i[6] = pc_not_taken;
  assign mux_next_pc_i[7] = pc_not_taken;
  
  //choose 1 when update and not taking branch, 2 when updating and taking branch, 3 when ldst contention and updating,
  //4 when switching to not taken path
  assign mux_next_pc_sel[2] = pc_update;
  assign mux_next_pc_sel[0] = (update & ~take_branch) | (update & contention);
  assign mux_next_pc_sel[1] = (update & take_branch) | (update & contention);
  
  mux_generic #(.INPUT_WIDTH(I_ADDR_WIDTH),
                .NUM_INPUTS(8)) multiplex_next_pc(.in(mux_next_pc_i),
                                                  .sel(mux_next_pc_sel),
                                                  .out(mux_next_pc));
                                            
  always @ (posedge clk) begin
    if(wi | update | pc_update) begin
      cur_pc <= mux_next_pc;
    end
  end
  
  //Update warp state to 1 on initialize, 1 on Bar rst, 0 when entering pipeling,
  //otherwise update state on update to given value
  assign w_enter = enter & (enter_id == cur_wid) & cur_valid;
  always @ (posedge clk) begin
    if(wi) begin
      cur_state <= 1;
    end
    else if(w_enter) begin
      cur_state <= 0;
    end
    else if(update) begin
      cur_state <= wstate;
    end
    else if(bar_rst) begin
      if(bar_id_match) begin
        cur_state <= 1;
      end
    end
  end
  
  //Update warp mask on initialize, update, mask_update, or converge
  assign converge_mask = cur_mask | cur_stack_mask;
  
  always @ (posedge clk) begin
    if(wi) begin
      cur_mask <= wmask;
    end
    else if(update & ~mask_update) begin
      cur_mask <= next_mask;
    end
    else if(mask_update) begin
      cur_mask <= cur_stack_mask;
    end
    else if(converge) begin
      cur_mask <= converge_mask;
    end
  end
  
  //assign outputs
  //Only ready if we are in warp state 1 and the warp is valid
  assign ready = cur_state[0] & ~cur_state[1] & cur_valid;
  
  assign base_addr_o = cur_base_addr;
  assign reg_per_thread_o = cur_reg_per_thread;
  assign valid_o = cur_valid;
  assign wid_o = cur_wid;
  assign bid_o = cur_bid;
  
  //Mux to choose pc to output
  assign mux_pc_o_i[0] = cur_pc;
  assign mux_pc_o_i[1] = pc_not_taken;
  
  //Pick not taken pc on pc update as this may occur when this warp is selected but the pc is updating
  //due to synchronization point
  mux_generic #(.INPUT_WIDTH(I_ADDR_WIDTH),
                .NUM_INPUTS(2)) mux_pc_o(.in(mux_pc_o_i),
                                         .sel(pc_update),
                                         .out(pc_o));
  
  //Mux to choose mask to output
  assign mux_mask_o_i[0] = cur_mask;
  assign mux_mask_o_i[1] = cur_stack_mask;
  assign mux_mask_o_i[2] = converge_mask;
  assign mux_mask_o_i[3] = converge_mask;
  assign mux_mask_sel[1] = converge;
  assign mux_mask_sel[0] = mask_update;
  
  mux_generic #(.INPUT_WIDTH(WARP_WIDTH),
                .NUM_INPUTS(4)) mux_mask_o(.in(mux_mask_o_i),
                                           .sel(mux_mask_sel),
                                           .out(wmask_o));
                                           
endmodule
