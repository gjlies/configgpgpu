//************************
// gjlies 04-21-19 Created
// gjlies 04-27-19 Added outputs for thread idxs and special data
// gjlies 04-27-19 Changed thread idx selection for proper array assignment
// gjlies 04-28-19 Added any_valid output to easily see if ther are any valid warps
//************************
//Description:
//Top level warp scheduling module to integrate all warp pieces together
`include "../misc/mux_generic.sv"
`include "../misc/counter.sv"
module warp_unit (clk, rst, wid_init, wid, bid_init, wpc_init, wpc_p1, label, base_addr_init, reg_per_thread, wstate, wmask_init, wi, control, contention, tid_wa,
                  tid_d, tid_we, wid_fp, bid_fp, diverge, ssy_en, take_branch, next_mask, stack_mask, wup, exit, bid, warps_assoc, bdim_init, gdim_init,
                  bidx_init, p_wa, p_d, p_we, bi, bar, src1, pc_o, base_o, mask_o, wid_o, bid_o, row_o, rpt_o, tids_o, spec_o, valid_o, any_valid);

  parameter NUM_BLOCKS = 4;                                // Number of blocks per MP
  parameter NUM_WARPS = 16;                                // Number of warps per MP
  parameter WARP_WIDTH = 32;                               // Number of threads per warp
  parameter BLOCK_DIM = 32;                                // Number of bits in block dimension xyz
  parameter GRID_DIM = 32;                                 // Number of bits in grid dimension xyz
  parameter NUM_PARAMS = 8;                                // Number of parameters supported
  
  parameter SP_PER_MP = 8;                                 // Number of SPs per MP
  
  parameter I_ADDR_WIDTH = 10;                             // Number of bits in instruction address
  parameter R_ADDR_WIDTH = 10;                             // Number of bits in register address
  parameter R_DATA_WIDTH = 32;                             // Number of bits in register entry
  parameter CONTROL_WIDTH = 21;                            // Number of pipeline control signals
  
  parameter SRC_WIDTH = 5;                                 // Number of bits for src in instruction
  
  parameter NUM_ROWS = WARP_WIDTH / SP_PER_MP;             // Number of rows in a warp
  parameter ROW_DEPTH = $clog2(NUM_ROWS);                  // Number of bits to represent a row
  parameter WARPID_DEPTH = $clog2(NUM_WARPS);              // Number of bits to represent a warp
  parameter BLOCKID_DEPTH = $clog2(NUM_BLOCKS);            // Number of bits to represent a block
  parameter WARP_DEPTH = $clog2(WARP_WIDTH);               // Number of bits to represent a thread
  parameter PARAM_DEPTH = $clog2(NUM_PARAMS);              // Number of bits to represent a parameter
  
  input clk;                                               // Clock
  input rst;                                               // Reset
  input [WARPID_DEPTH - 1 : 0] wid_init;                   // Warp ID to initialize
  input [WARPID_DEPTH - 1 : 0] wid;                        // Warp ID from pipeline
  input [BLOCKID_DEPTH - 1 : 0] bid_init;                  // Block ID to initialize
  input [I_ADDR_WIDTH - 1 : 0] wpc_init;                   // Warp PC to initialize
  input [I_ADDR_WIDTH - 1 : 0] wpc_p1;                     // Warp PC + 1 from pipeline
  input [I_ADDR_WIDTH - 1 : 0] label;                      // Label from instruction in pipeline
  input [R_ADDR_WIDTH - 1 : 0] base_addr_init;             // Base register address to initialize
  input [R_ADDR_WIDTH - 1 : 0] reg_per_thread;             // Registers required per thread to initialize
  input [1 : 0] wstate;                                    // Warp state to store from pipeline
  input [WARP_WIDTH - 1 : 0] wmask_init;                   // Warp mask to initialize
  input [NUM_WARPS - 1 : 0] wi;                            // Signal to initialize one of the warps
  input [CONTROL_WIDTH - 1 : 0] control;                   // Control bits from pipeline
  input contention;                                        // Contention signal from pipeline
  input [WARP_DEPTH - 1 : 0] tid_wa;                       // Thread write address for initializing thread IDs
  input [BLOCK_DIM - 1 : 0] tid_d;                         // Thread ID to store
  input [NUM_WARPS - 1 : 0] tid_we;                        // Write enable to thread ID registers
  input [WARPID_DEPTH - 1 : 0] wid_fp;                     // Warp ID currently in decode
  input [BLOCKID_DEPTH - 1 : 0] bid_fp;                    // Block ID currently in decode
  input diverge;                                           // Threads diverging in pipeline
  input ssy_en;                                            // Signal to push synchronous PC from pipeline
  input take_branch;                                       // Signal to take branch from pipeline
  input [WARP_WIDTH - 1 : 0] next_mask;                    // Next warp mask from pipeline
  input [WARP_WIDTH - 1 : 0] stack_mask;                   // Stack mask to push from pipeline
  input wup;                                               // Signal from pipeline to update warp
  input exit;                                              // Signal to exit warp from pipeline
  input [BLOCKID_DEPTH - 1 : 0] bid;                       // Block ID from pipeline
  input [WARPID_DEPTH - 1 : 0] warps_assoc;                // Number of warps associated with a block
  input [BLOCK_DIM - 1 : 0] bdim_init;                     // Block Dimension to initialize
  input [GRID_DIM - 1 : 0] gdim_init;                      // Grid Dimension to initialize
  input [GRID_DIM - 1 : 0] bidx_init;                      // Block Index to initialize
  input [PARAM_DEPTH - 1 : 0] p_wa;                        // Param write address
  input [R_DATA_WIDTH - 1 : 0] p_d;                        // Param data to store
  input p_we;                                              // Param write enable
  input [NUM_BLOCKS - 1 : 0] bi;                           // Signal to initialize one of the blocks
  input bar;                                               // BAR signal from pipeline
  input [SRC_WIDTH - 1 : 0] src1;                          // Src1 instruction bits from pipeline
  
  output [I_ADDR_WIDTH - 1 : 0] pc_o;                      // PC to read in pipeline
  output [R_ADDR_WIDTH - 1 : 0] base_o;                    // Base register for pipeline
  output [WARP_WIDTH - 1 : 0] mask_o;                      // Thread mask for pipeline
  output [WARPID_DEPTH - 1 : 0] wid_o;                     // Warp ID for pipeline
  output [BLOCKID_DEPTH - 1 : 0] bid_o;                    // Block ID for pipeline
  output [ROW_DEPTH - 1 : 0] row_o;                        // Row to execute for pipeline REMOVE IF NO ROWS
  output [R_ADDR_WIDTH - 1 : 0] rpt_o;                     // Registers per thread for the pipeline
  output [BLOCK_DIM - 1 : 0] tids_o [WARP_WIDTH - 1 : 0];  // Thread idxs of threads in pipeline
  output [R_DATA_WIDTH - 1 : 0] spec_o;                    // Special data required by threads in pipeline
  output valid_o;                                          // Whether or not the warp entering pipeline is valid
  output any_valid;                                        // Signal if any warps are valid
  
  wire [NUM_WARPS - 1 : 0] ready;                                        // If each warp is ready, packed for scheduler
  wire [I_ADDR_WIDTH - 1 : 0] warp_pcs [NUM_WARPS - 1 : 0];              // Current PCs of each warp
  wire [R_ADDR_WIDTH - 1 : 0] base_addrs [NUM_WARPS - 1 : 0];            // Base register values of each warp
  wire [NUM_WARPS - 1 : 0] valid;                                        // If each warp is valid
  wire [WARP_WIDTH - 1 : 0] warp_masks [NUM_WARPS - 1 : 0];              // Thread masks of each warp
  wire [BLOCK_DIM - 1 : 0] tids [NUM_WARPS - 1 : 0][WARP_WIDTH - 1 : 0]; // Thread Ids of each warp
  wire [WARPID_DEPTH - 1 : 0] wids [NUM_WARPS - 1 : 0];                  // Warp IDs of each warp
  wire [BLOCKID_DEPTH - 1 : 0] bids [NUM_WARPS - 1 : 0];                 // Block IDs of each warp
  wire [R_ADDR_WIDTH - 1 : 0] regs_per_thread [NUM_WARPS - 1 : 0];       // Registers required by each thread

  reg [R_DATA_WIDTH - 1 : 0] block_spec [NUM_BLOCKS - 1 : 0];            // Special data from each block
  reg [NUM_BLOCKS - 1 : 0] bar_max;                                      // Signal all warps are at Barrier for each block, packed for encoder

  wire bar_finish;                                                       // Barrier is complete
  wire [BLOCKID_DEPTH - 1 : 0] bar_id;                                   // Block ID of barrier completion

  wire warp_enter;                                                       // Warp is entering the pipeline
  wire [WARPID_DEPTH - 1 : 0] enter_id;                                  // Warp entering the pipeline
  wire new_warp;                                                         // Signal that the scheduler is ready to select a new warp

  wire [I_ADDR_WIDTH - 1 : 0] selected_pc;                               // PC of selected warp
  wire [R_ADDR_WIDTH - 1 : 0] selected_base;                             // Base register address of selected warp
  wire [WARP_WIDTH - 1 : 0] selected_mask;                               // Mask of selected warp
  wire [WARPID_DEPTH - 1 : 0] selected_wid;                              // Warp ID of selected warp
  wire [R_ADDR_WIDTH - 1 : 0] selected_rpt;                              // Register per thread of selected warp
  wire [BLOCKID_DEPTH - 1 : 0] selected_bid;                             // Block ID of selected warp
  wire [BLOCK_DIM - 1 : 0] selected_tids [WARP_WIDTH - 1 : 0];           // Selected thread IDs, 1 for each thread in a warp
  wire [R_DATA_WIDTH - 1 : 0] selected_special;                          // Selected special data of warp in decode

  reg [I_ADDR_WIDTH - 1 : 0] selected_pc_p;                              // Selected warp's PC
  reg [R_ADDR_WIDTH - 1 : 0] selected_base_p;                            // Selected warp's base register addr
  reg [WARP_WIDTH - 1 : 0] selected_mask_p;                              // Selected warp's thread mask
  reg [WARPID_DEPTH - 1 : 0] selected_wid_p;                             // Selected warp's warp ID
  reg [BLOCKID_DEPTH - 1 : 0] selected_bid_p;                            // Selected warp's block ID
  reg [ROW_DEPTH - 1 : 0] selected_row_p;                                // Row of selected warp to execute  DELETE IF NO ROWS
  reg [R_ADDR_WIDTH - 1 : 0] selected_rpt_p;                             // Selected warp's registers per thread
  reg valid_warp_p;                                                      // Whether or not the warp in pipeline is valid

  wire valid_warp;                                                       // A warp is ready to enter the pipeline
  wire bar_finished;                                                     // Check if any barriers are finished

  //Instantiate each warp
  genvar gi;
  genvar gm;
  generate
    for(gi = 0; gi < NUM_WARPS; gi = gi + 1) begin : warp_generate
    
      //Create a temporary wire to grab thread idxs
      wire [BLOCK_DIM - 1 : 0] tidx [WARP_WIDTH - 1 : 0];
      
      //Another loop to store the indexes into a 2D array
      for(gm = 0; gm < WARP_WIDTH; gm = gm + 1) begin
        assign tids[gi][gm] = tidx[gm]; 
      end
      
      warp #(.NUM_WARPS(NUM_WARPS),
             .NUM_BLOCKS(NUM_BLOCKS),
             .I_ADDR_WIDTH(I_ADDR_WIDTH),
             .R_ADDR_WIDTH(R_ADDR_WIDTH),
             .CONTROL_WIDTH(CONTROL_WIDTH),
             .WARP_WIDTH(WARP_WIDTH),
             .BLOCK_DIM(BLOCK_DIM)) warp_gi(.clk(clk),
                                            .rst(rst),
                                            .wid_init(wid_init),
                                            .wid(wid),
                                            .bid(bid_init),
                                            .wpc(wpc_init),
                                            .wpc_p1(wpc_p1),
                                            .label(label),
                                            .base_addr(base_addr_init),
                                            .reg_per_thread(reg_per_thread),
                                            .wstate(wstate),
                                            .wmask(wmask_init),
                                            .wi(wi[gi]),
                                            .control(control),
                                            .contention(contention),
                                            .tid_wa(tid_wa),
                                            .tid_d(tid_d),
                                            .tid_we(tid_we[gi]),
                                            .diverge(diverge),
                                            .ssy_en(ssy_en),
                                            .take_branch(take_branch),
                                            .next_mask(next_mask),
                                            .stack_mask(stack_mask),
                                            .wup(wup),
                                            .exit(exit),
                                            .enter_id(enter_id),
                                            .enter(warp_enter),
                                            .bar_id(bar_id),
                                            .bar_rst(bar_finished),
                                            .ready(ready[gi]),
                                            .pc_o(warp_pcs[gi]),
                                            .base_addr_o(base_addrs[gi]),
                                            .valid_o(valid[gi]),
                                            .wmask_o(warp_masks[gi]),
                                            .tid_o(tidx),
                                            .wid_o(wids[gi]),
                                            .bid_o(bids[gi]),
                                            .reg_per_thread_o(regs_per_thread[gi]));
                                            
    end
  endgenerate
  
  //Instantiate each block
  genvar gj;
  generate
    for(gj = 0; gj < NUM_BLOCKS; gj = gj + 1) begin : block_generate
      block #(.NUM_BLOCKS(NUM_BLOCKS),
              .NUM_WARPS(NUM_WARPS),
              .BLOCK_DIM(BLOCK_DIM),
              .GRID_DIM(GRID_DIM),
              .R_DATA_WIDTH(R_DATA_WIDTH),
              .NUM_PARAMS(NUM_PARAMS),
              .SRC_WIDTH(SRC_WIDTH)) block_gj(.clk(clk),
                                              .rst(rst),
                                              .bid(bid),
                                              .bid_init(bid_init),
                                              .num_warp(warps_assoc),
                                              .bdim(bdim_init),
                                              .gdim(gdim_init),
                                              .bidx(bidx_init),
                                              .pwa(p_wa),
                                              .param(p_d),
                                              .pwe(p_we),
                                              .bi(bi[gj]),
                                              .bar(bar),
                                              .wup(wup),
                                              .src1(src1),
                                              .spec_o(block_spec[gj]),
                                              .bar_max_o(bar_max[gj]));
    end
  endgenerate
  
  //Check Barrier signals so warps can re-enable if everyone is at barrier
  bar_check #(.NUM_BLOCKS(NUM_BLOCKS)) bar_checker(.bar_max(bar_max),
                                                   .valid(bar_finished),
                                                   .selected(bar_id));

  //Create Warp scheduler
  warp_scheduler #(.NUM_WARPS(NUM_WARPS)) scheduler(.clk(clk),
                                                    .rst(rst),
                                                    .ready(ready),
                                                    .select(new_warp),
                                                    .valid(warp_enter),
                                                    .selected(enter_id));
  
  //Select information to send to pipeline
  //Mux for selecting Warp PC to pipe
  mux_generic #(.INPUT_WIDTH(I_ADDR_WIDTH),
                .NUM_INPUTS(NUM_WARPS)) mux_warp_pc(.in(warp_pcs),
                                                    .sel(enter_id),
                                                    .out(selected_pc));
                                                    
  //Mux for selecting base register address to pipe
  mux_generic #(.INPUT_WIDTH(R_ADDR_WIDTH),
                .NUM_INPUTS(NUM_WARPS)) mux_warp_base(.in(base_addrs),
                                                      .sel(enter_id),
                                                      .out(selected_base));
                                                      
  //Mux for selecting warp mask to pipe
  mux_generic #(.INPUT_WIDTH(WARP_WIDTH),
                .NUM_INPUTS(NUM_WARPS)) mux_warp_mask(.in(warp_masks),
                                                      .sel(enter_id),
                                                      .out(selected_mask));
    
  //Mux for selecting warp ID to pipe, should always match enter_id for now
  mux_generic #(.INPUT_WIDTH(WARPID_DEPTH),
                .NUM_INPUTS(NUM_WARPS)) mux_warp_wid(.in(wids),
                                                     .sel(enter_id),
                                                     .out(selected_wid));
  
  //Mux for selecting block ID to pipe
  mux_generic #(.INPUT_WIDTH(BLOCKID_DEPTH),
                .NUM_INPUTS(NUM_WARPS)) mux_warp_bid(.in(bids),
                                                     .sel(enter_id),
                                                     .out(selected_bid));
  
  //Mux for selecting registers per thread
  mux_generic #(.INPUT_WIDTH(R_ADDR_WIDTH),
                .NUM_INPUTS(NUM_WARPS)) mux_warp_rpt(.in(regs_per_thread),
                                                     .sel(enter_id),
                                                     .out(selected_rpt));
  
  //Muxes for selecting thread IDs
  genvar gk;
  genvar gn;
  generate
    //One mux for selecting each tidx from each warp
    for(gk = 0; gk < WARP_WIDTH; gk = gk + 1) begin : select_tids
      wire [BLOCK_DIM - 1 : 0] mux_warp_tids_i [NUM_WARPS - 1 : 0];  //Setup thread IDs to select from
      
      //Assign the inputs
      for(gn = 0; gn < NUM_WARPS; gn = gn + 1) begin
        assign mux_warp_tids_i[gn] = tids[gn][gk];
      end
      
      mux_generic #(.INPUT_WIDTH(BLOCK_DIM),
                    .NUM_INPUTS(NUM_WARPS)) mux_warp_tids(.in(mux_warp_tids_i),
                                                          .sel(wid_fp),
                                                          .out(selected_tids[gk])); //Dont pipe, thread IDs chosen in decode stage
    end
  endgenerate
  
  //Mux for selecting Special data from blocks
  mux_generic #(.INPUT_WIDTH(R_DATA_WIDTH),
                .NUM_INPUTS(NUM_BLOCKS)) mux_warp_special(.in(block_spec),
                                                          .sel(bid_fp),
                                                          .out(selected_special)); //Not piped, sent directly to decode
  
  //Counter for keeping track of which warp row is executing
  generate
  //Only create a row counter if we have rows
  if(NUM_ROWS > 1) begin : row_counter_gen
    wire [ROW_DEPTH - 1 : 0] row_count;                           //Current row count
    wire row_count_en;                                            //Row counter enable, enable whenever warp_enter or count != 0
  
    assign row_count_en = warp_enter | (row_count != 0);
  
    counter #(.COUNT_WIDTH(ROW_DEPTH)) row_counter(.clk(clk),
                                                   .rst(rst),
                                                   .en(row_count_en),
                                                   .up(1'b1),
                                                   .count(row_count));
                                                 
    //Pipe selected row
    always @ (posedge clk or negedge rst) begin
      if(rst == 0) begin
        selected_row_p <= 0;
      end
      else begin
        selected_row_p <= row_count;
      end
    end
    
    //If row 0 we are ready for a new warp
    assign new_warp = (row_count == 0);
    
  end
  else begin : row_counter_gen
    assign new_warp = 1'b1;
  end
  endgenerate
  
  //Pipe signals to be input into pipeline
  assign valid_warp = warp_enter;                               //Only pipe when there is a warp to give
  
  //Signals only piped on selecting a warp
  always @ (posedge clk or negedge rst) begin
    if(rst == 0) begin
      selected_pc_p   <= 0;
      selected_base_p <= 0;
      selected_mask_p <= 0;
      selected_wid_p  <= 0;
      selected_bid_p  <= 0;
      selected_rpt_p  <= 0;
    end
    else if(valid_warp) begin
      selected_pc_p   <= selected_pc;
      selected_base_p <= selected_base;
      selected_mask_p <= selected_mask;
      selected_wid_p  <= selected_wid;
      selected_bid_p  <= selected_bid;
      selected_rpt_p  <= selected_rpt;
    end
  end
  
  //Signals piped every cycle
  //Pipe valid on row 0 or always if no rows
  generate
  if(NUM_ROWS > 1 ) begin : valid_pipe
    always @ (posedge clk or negedge rst) begin
      if(rst == 0) begin 
        valid_warp_p <= 0;
      end
      else if(new_warp) begin
        valid_warp_p <= valid_warp;
      end
    end
  end
  else begin : valid_pipe
    always @ (posedge clk or negedge rst) begin
      if(rst == 0) begin
        valid_warp_p <= 0;
      end
      else begin
        valid_warp_p <= valid_warp;
      end
    end
  end
  endgenerate
  
  //Assign outputs
  assign pc_o = selected_pc_p;
  assign base_o = selected_base_p;
  assign mask_o = selected_mask_p;
  assign wid_o = selected_wid_p;
  assign bid_o = selected_bid_p;
  assign row_o = selected_row_p;
  assign rpt_o = selected_rpt_p;
  assign spec_o = selected_special;
  assign valid_o = valid_warp_p;
  assign any_valid = |valid;
  
  genvar gl;
  generate
    for(gl = 0; gl < WARP_WIDTH; gl = gl + 1) begin
      assign tids_o[gl] = selected_tids[gl];
    end
  endgenerate
  
endmodule
