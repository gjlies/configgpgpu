//************************
// gjlies 04-24-19 Created
//************************
//Description:
//A Multiprocessor for a GPU
`include "../warp/warp_fsm.sv"
`include "../warp/warp_unit.sv"
`include "../misc/mux_generic.sv"
`include "../pipeline/pipeline_top.sv"
`include "../misc/counter.sv"
module multiprocessor (clk, rst, mpid, gs_iwe, gs_cwe, gs_dwe, gs_start, gs_mpid, gs_bdim, gs_gdim, gs_params, gs_warp, gs_reg, gs_bidx,
                       gs_instr_wa, gs_const_wa, gs_l1_wa, gs_i_data, gs_c_data, gs_l_data, any_valid, ready);

  parameter SYNTHESIS = 1;                                                      // 1 if synthesizing
  
  //If synthesizing, synthesize this module, copy gpgpu parameters with parameters below
  
  parameter GRID_DIM = 32;                                                      // Number of bits in grid dim xyz
  parameter GRID_DIM_WIDTH = 10;                                                // Number of bits in a single grid dim
  parameter BLOCK_DIM = 32;                                                     // Number of bits in block dim xyz
  parameter BLOCK_DIM_WIDTH = 10;                                               // Number of bits in single block dim
  parameter NUM_PARAMS = 8;                                                     // Number of supported parameters
  
  parameter NUM_MPS = 8;                                                        // Number of MPs
  parameter NUM_WARPS = 16;                                                     // Number of warps / MP
  parameter NUM_BLOCKS = 4;                                                     // Number of blocks / MP
  parameter SP_PER_MP = 8;                                                      // Number of SPs per MP
  parameter WARP_WIDTH = 32;                                                    // Number of threads / Warp
  
  parameter I_DATA_WIDTH = 32;                                                  // Number of bits in instruction entry
  parameter I_ADDR_WIDTH = 10;                                                  // Number of bits in instruction address
  parameter R_DATA_WIDTH = 32;                                                  // Number of bits in a register entry
  parameter R_ADDR_WIDTH = 10;                                                  // Number of bits in register address
  parameter C_ADDR_WIDTH = 8;                                                   // Number of bits in constant address
  parameter L_ADDR_WIDTH = 10;                                                  // Number of bits in L1 address
  
  parameter CONTROL_WIDTH = 21;                                                 // Number of bits in control signal
  parameter OP_WIDTH = 6;                                                       // Number of bits in opcode of instruction
  parameter FUNC_WIDTH = 6;                                                     // Number of bits in function code of instruction
  parameter DEST_WIDTH = 5;                                                     // Number of bits in dest of instruction
  parameter SRC_WIDTH = 5;                                                      // Number of bits in src of instruction
  parameter IMM_WIDTH = 16;                                                     // Number of bits in imm of instruction
  
  //Do not paste over the parameters below
  
  parameter MPID_DEPTH = $clog2(NUM_MPS);                                       // Number of bits to represent a MP
  parameter WARPID_DEPTH = $clog2(NUM_WARPS);                                   // Number of bits to represent a warp
  parameter BLOCKID_DEPTH = $clog2(NUM_BLOCKS);                                 // Number of bits to represent a block
  parameter PARAM_DEPTH = $clog2(NUM_PARAMS);                                   // Number of bits to represent a parameter
  parameter NUM_ROWS = WARP_WIDTH / SP_PER_MP;                                  // Number of rows in warp
  parameter ROW_DEPTH = $clog2(NUM_ROWS);                                       // Number of bits to represent a row
  parameter WARP_DEPTH = $clog2(WARP_WIDTH);                                    // Number of bits to represent a thread in a warp
  
  input clk;                                                                    // Clock
  input rst;                                                                    // Reset
  input [MPID_DEPTH - 1 : 0] mpid;                                              // ID for this multiprocessor
  input gs_iwe;                                                                 // Instruction write enable from global scheduler
  input gs_cwe;                                                                 // Constant write enable from global scheduler
  input gs_dwe;                                                                 // Data write enable from global scheduler
  input gs_start;                                                               // Signal to start initializing a block
  input [MPID_DEPTH - 1 : 0] gs_mpid;                                           // MP to start initializing
  input [BLOCK_DIM - 1 : 0] gs_bdim;                                            // Block dimension of initializing block
  input [GRID_DIM - 1 : 0] gs_gdim;                                             // Grid dimensions of kernel
  input [R_DATA_WIDTH - 1 : 0] gs_params [NUM_PARAMS - 1 : 0];                  // Block parameters to initialize
  input [WARPID_DEPTH - 1 : 0] gs_warp;                                         // Number of warps in the block to initialize
  input [R_ADDR_WIDTH - 1 : 0] gs_reg;                                          // Number of registers per thread in a block
  input [GRID_DIM - 1 : 0] gs_bidx;                                             // Index of block to initialize
  input [I_ADDR_WIDTH - 1 : 0] gs_instr_wa;                                     // Instruction address to write to
  input [C_ADDR_WIDTH - 1 : 0] gs_const_wa;                                     // Constant address to write to
  input [L_ADDR_WIDTH - 1 : 0] gs_l1_wa;                                        // L1 address to write to
  input [I_DATA_WIDTH - 1 : 0] gs_i_data;                                       // Instruction data to store
  input [R_DATA_WIDTH - 1 : 0] gs_c_data;                                       // Constant data to store
  input [R_DATA_WIDTH - 1 : 0] gs_l_data;                                       // L1 data to store
  
  output any_valid;                                                             // Whether or not there are any valid warps
  output ready;                                                                 // Signal this MP is ready to initialize a new block
  
  reg [MPID_DEPTH - 1 : 0] cur_mpid;                                            // This multiprocessor's ID
  reg gs_iwe_p;                                                                 // Signal to write to instruction cache
  reg gs_cwe_p;                                                                 // Signal to write to constant cache
  reg gs_dwe_p;                                                                 // Signal to write to l1 cache
  reg gs_start_p;                                                               // Signal to start initializing a block
  reg [MPID_DEPTH - 1 : 0] gs_mpid_p;                                           // MP to initialize the block
  reg [BLOCK_DIM - 1 : 0] gs_bdim_p;                                            // Block Dimension of block to initialize
  reg [GRID_DIM - 1 : 0] gs_gdim_p;                                             // Grid Dimension of block to initialize
  reg [R_DATA_WIDTH - 1 : 0] gs_params_p [NUM_PARAMS - 1 : 0];                  // Parameters of block to initialize
  reg [WARPID_DEPTH - 1 : 0] gs_warp_p;                                         // Number of warps associated with the block to initialize
  reg [R_ADDR_WIDTH - 1 : 0] gs_reg_p;                                          // Number of registers required per thread in the block to initialize
  reg [GRID_DIM - 1 : 0] gs_bidx_p;                                             // Block index of the block to initialize
  reg [I_ADDR_WIDTH - 1 : 0] gs_instr_wa_p;                                     // Instruction address to write to
  reg [C_ADDR_WIDTH - 1 : 0] gs_const_wa_p;                                     // Constant address to write to
  reg [L_ADDR_WIDTH - 1 : 0] gs_l1_wa_p;                                        // L1 address to write to
  reg [I_DATA_WIDTH - 1 : 0] gs_i_data_p;                                       // Instruction data to write
  reg [R_DATA_WIDTH - 1 : 0] gs_c_data_p;                                       // Constant data to write
  reg [R_DATA_WIDTH - 1 : 0] gs_l_data_p;                                       // L1 data to write

  wire start_rst;                                                               // Reset start signal for fsm
  wire [WARPID_DEPTH - 1 : 0] next_warp;                                        // Next warp to initialize
  wire [BLOCKID_DEPTH - 1 : 0] next_block;                                      // Next block to initialize

  wire mp_match;                                                                // Check if gs_mpid_p matches this mpid
  wire [WARP_WIDTH - 1 : 0] wmask_init;                                         // Warp Mask to initialize
  wire [BLOCK_DIM - 1 : 0] tid_init;                                            // Thread ID to initialize
  wire twe;                                                                     // Thread ID write enable
  wire [WARP_DEPTH - 1 : 0] twa;                                                // Thread ID write address
  wire pwe;                                                                     // Parameter write enable
  wire [PARAM_DEPTH - 1 : 0] pwa;                                               // Parameter write address
  wire warp_init;                                                               // Signal to initialize warp
  wire fsm_done;                                                                // Signal that the fsm is done
  wire mp_ready;                                                                // Signal that the mp is ready to initialize a new block
  wire [R_ADDR_WIDTH - 1 : 0] base_reg;                                         // Base register value to initialize to a new warp

  wire [NUM_WARPS - 1 : 0] wi;                                                  // Warp initialize signals
  wire [NUM_WARPS - 1 : 0] tid_we;                                              // Thread idx write enable signals
  wire [NUM_BLOCKS - 1 : 0] bi;                                                 // Block initialize signals

  wire [R_DATA_WIDTH - 1 : 0] param_d;                                          // Parameter to write

  wire [I_ADDR_WIDTH - 1 : 0] pc_o;                                             // PC to read next in pipeline
  wire [R_ADDR_WIDTH - 1 : 0] base_o;                                           // Base register value of next warp
  wire [WARP_WIDTH - 1 : 0] mask_o;                                             // Thread mask of next warp
  wire [WARPID_DEPTH - 1 : 0] wid_o;                                            // Warp ID of next warp
  wire [BLOCKID_DEPTH - 1 : 0] bid_o;                                           // Block ID of next warp
  wire [ROW_DEPTH - 1 : 0] row_o;                                               // Warp row of executing warp DELETE IF NO ROWS
  wire [R_ADDR_WIDTH - 1 : 0] rpt_o;                                            // Registers per thread in next warp
  wire [BLOCK_DIM - 1 : 0] tids_o [WARP_WIDTH - 1 : 0];                         // Thread IDs of warp reading them
  wire [R_DATA_WIDTH - 1 : 0] spec_o;                                           // Special data of warp reading them
  wire valid_o;                                                                 // Whether or not the warp is valid

  wire bar_o;                                                                   // Signal that this is a barrier instruction
  wire ssy_en;                                                                  // Signal that this is a ssy instruction
  wire exit;                                                                    // Signal to exit the warp
  wire [I_ADDR_WIDTH - 1 : 0] label;                                            // Label portion of instruction
  wire [1: 0] wstate;                                                           // Warp state to update to
  wire [WARPID_DEPTH - 1 : 0] wid_p;                                            // Warp ID of warp to update
  wire [I_ADDR_WIDTH - 1 : 0] pc_p1_o;                                          // PC + 1 of current PC in pipeline
  wire [WARP_WIDTH - 1 : 0] next_mask_o;                                        // Next mask to store for warp in pipeline
  wire [WARP_WIDTH - 1 : 0] stack_mask_o;                                       // Stack mask to store for warp in pipeline 
  wire take_branch;                                                             // Signal for warp to take branch
  wire diverge_wb;                                                              // Signal the warp is diverging
  wire contention_wb;                                                           // Signal there is ldst contention
  wire warp_update;                                                             // Signal the warp to update
  wire [SRC_WIDTH - 1 : 0] src1_o;                                              // Src 1 from instruction in decode
  wire [WARPID_DEPTH - 1 : 0] wid_fp_o;                                         // Warp ID in decode for reading thread IDs
  wire [BLOCKID_DEPTH - 1 : 0] bid_p;                                           // Block ID of warp in pipeline
  wire [BLOCKID_DEPTH - 1 : 0] bid_fp_o;                                        // Block ID in decode stage for reading special value
  wire [CONTROL_WIDTH - 1 : 0] control_o;                                       // Control signals from write back

  //Register to hold this MP's ID
  always @ (posedge clk) begin
    cur_mpid <= mpid;
  end
  
  //Pipe inputs from Global Scheduler, memorize mpid
  always @ (posedge clk or negedge rst) begin
    if(rst == 0) begin
      gs_iwe_p      <= 0;
      gs_cwe_p      <= 0;
      gs_dwe_p      <= 0;
      gs_mpid_p     <= 0;
      gs_bdim_p     <= 0;
      gs_gdim_p     <= 0;
      gs_warp_p     <= 0;
      gs_reg_p      <= 0;
      gs_bidx_p     <= 0;
      gs_instr_wa_p <= 0;
      gs_const_wa_p <= 0;
      gs_l1_wa_p    <= 0;
      gs_i_data_p   <= 0;
      gs_c_data_p   <= 0;
      gs_l_data_p   <= 0;
    end
    else if(mp_ready) begin
      gs_iwe_p      <= gs_iwe;
      gs_cwe_p      <= gs_cwe;
      gs_dwe_p      <= gs_dwe;
      gs_mpid_p     <= gs_mpid;
      gs_bdim_p     <= gs_bdim;
      gs_gdim_p     <= gs_gdim;
      gs_warp_p     <= gs_warp;
      gs_reg_p      <= gs_reg;
      gs_bidx_p     <= gs_bidx;
      gs_instr_wa_p <= gs_instr_wa;
      gs_const_wa_p <= gs_const_wa;
      gs_l1_wa_p    <= gs_l1_wa;
      gs_i_data_p   <= gs_i_data;
      gs_c_data_p   <= gs_c_data_p;
      gs_l_data_p   <= gs_l_data_p;
    end
  end
  
  //Make sure to clear start when done initializing so we dont initialize the same block again
  assign start_rst = rst | ~fsm_done;
  
  always @ (posedge clk or negedge start_rst) begin
    if(start_rst == 0) begin
      gs_start_p <= 0;
    end
    else if(mp_ready) begin
      gs_start_p <= gs_start;
    end
  end
  
  genvar gi;
  generate
    for(gi = 0; gi < NUM_PARAMS; gi = gi + 1) begin
      always @ (posedge clk or negedge rst) begin
        if(rst == 0) begin
          gs_params_p[gi] <= 0;
        end
        else begin
          gs_params_p[gi] <= gs_params[gi];
        end
      end
    end
  endgenerate
  
  //Count to keep track of what warp is next to initialize
  counter #(.COUNT_WIDTH(WARPID_DEPTH)) next_warp_count(.clk(clk),
                                                        .rst(rst),
                                                        .en(warp_init),
                                                        .up(1'b1),
                                                        .count(next_warp));
  
  //Count to keep track of what block is next to initialize
  counter #(.COUNT_WIDTH(BLOCKID_DEPTH)) next_block_count(.clk(clk),
                                                          .rst(rst),
                                                          .en(fsm_done),
                                                          .up(1'b1),
                                                          .count(next_block));
  
  //Instaniate fsm to initialize warps
  //Global scheduler has told this MP to initialize a block if this MP's ID is equal to the gs MP ID
  assign mp_match = (cur_mpid == gs_mpid_p);
  
  warp_fsm #(.BLOCK_DIM(BLOCK_DIM),
             .BLOCK_DIM_WIDTH(BLOCK_DIM_WIDTH),
             .NUM_PARAMS(NUM_PARAMS),
             .WARP_WIDTH(WARP_WIDTH),
             .R_ADDR_WIDTH(R_ADDR_WIDTH)) fsm(.clk(clk),
                                              .rst(rst),
                                              .start(gs_start_p),
                                              .mp_match(mp_match),
                                              .bdim(gs_bdim_p),
                                              .reg_per_thread(gs_reg_p),
                                              .wmask_o(wmask_init),
                                              .tid_o(tid_init),
                                              .twe(twe),
                                              .twa(twa),
                                              .pwe(pwe),
                                              .pwa(pwa),
                                              .wi(warp_init),
                                              .done_o(fsm_done),
                                              .ready(mp_ready),
                                              .base_reg(base_reg));
  
  //Create separate warp signals depending on warp initializing
  genvar gj;
  generate
  for(gj = 0; gj < NUM_WARPS; gj = gj + 1) begin : warp_signals
  
    wire warp_match;
    assign warp_match = (gj == next_warp);
    
    assign wi[gj] = warp_match & warp_init;
    assign tid_we[gj] = warp_match & twe;
    
  end
  endgenerate
  
  genvar gk;
  generate
    for(gk = 0; gk < NUM_BLOCKS; gk = gk + 1) begin
    
      wire block_match;
      assign block_match = (gk == next_block);
      
      assign bi[gk] = block_match & pwe;
      
    end
  endgenerate
  
  //Choose parameter to write
  mux_generic #(.INPUT_WIDTH(R_DATA_WIDTH),
                .NUM_INPUTS(NUM_PARAMS)) mux_param(.in(gs_params_p),
                                                   .sel(pwa),
                                                   .out(param_d));
  
  //Instantiate Warp Unit
  warp_unit # (.NUM_BLOCKS(NUM_BLOCKS),
               .NUM_WARPS(NUM_WARPS),
               .WARP_WIDTH(WARP_WIDTH),
               .BLOCK_DIM(BLOCK_DIM),
               .GRID_DIM(GRID_DIM),
               .NUM_PARAMS(NUM_PARAMS),
               .SP_PER_MP(SP_PER_MP),
               .I_ADDR_WIDTH(I_ADDR_WIDTH),
               .R_ADDR_WIDTH(R_ADDR_WIDTH),
               .R_DATA_WIDTH(R_DATA_WIDTH),
               .CONTROL_WIDTH(CONTROL_WIDTH),
               .SRC_WIDTH(SRC_WIDTH)) complete_scheduler(.clk(clk),
                                                         .rst(rst),
                                                         .wid_init(next_warp),
                                                         .wid(wid_p),
                                                         .bid_init(next_block),
                                                         .wpc_init(0),
                                                         .wpc_p1(pc_p1_o),
                                                         .label(label),
                                                         .base_addr_init(base_reg),
                                                         .reg_per_thread(gs_reg_p),
                                                         .wstate(wstate),
                                                         .wmask_init(wmask_init),
                                                         .wi(wi),
                                                         .control(control_o),
                                                         .contention(contention_wb),
                                                         .tid_wa(twa),
                                                         .tid_d(tid_init),
                                                         .tid_we(tid_we),
                                                         .wid_fp(wid_fp_o),
                                                         .bid_fp(bid_fp_o),
                                                         .diverge(diverge_wb),
                                                         .ssy_en(ssy_en),
                                                         .take_branch(take_branch),
                                                         .next_mask(next_mask_o),
                                                         .stack_mask(stack_mask_o),
                                                         .wup(warp_update),
                                                         .exit(exit),
                                                         .bid(bid_p),
                                                         .warps_assoc(gs_warp_p),
                                                         .bdim_init(gs_bdim_p),
                                                         .gdim_init(gs_gdim_p),
                                                         .bidx_init(gs_bidx_p),
                                                         .p_wa(pwa),
                                                         .p_d(param_d),
                                                         .p_we(pwe),
                                                         .bi(bi),
                                                         .bar(bar_o),
                                                         .src1(src1_o),
                                                         .pc_o(pc_o),
                                                         .base_o(base_o),
                                                         .mask_o(mask_o),
                                                         .wid_o(wid_o),
                                                         .bid_o(bid_o),
                                                         .row_o(row_o),
                                                         .rpt_o(rpt_o),
                                                         .tids_o(tids_o),
                                                         .spec_o(spec_o),
                                                         .valid_o(valid_o),
                                                         .any_valid(any_valid));
  
  //Instantiate Pipeline
  pipeline_top #(.SYNTHESIS(SYNTHESIS),
                 .I_DATA_WIDTH(I_DATA_WIDTH),
                 .I_ADDR_WIDTH(I_ADDR_WIDTH),
                 .R_DATA_WIDTH(R_DATA_WIDTH),
                 .R_ADDR_WIDTH(R_ADDR_WIDTH),
                 .SP_PER_MP(SP_PER_MP),
                 .CONTROL_WIDTH(CONTROL_WIDTH),
                 .OP_WIDTH(OP_WIDTH),
                 .FUNC_WIDTH(FUNC_WIDTH),
                 .DEST_WIDTH(DEST_WIDTH),
                 .SRC_WIDTH(SRC_WIDTH),
                 .IMM_WIDTH(IMM_WIDTH),
                 .L_ADDR_WIDTH(L_ADDR_WIDTH),
                 .WARP_WIDTH(WARP_WIDTH),
                 .NUM_WARPS(NUM_WARPS),
                 .C_DATA_WIDTH(R_DATA_WIDTH),
                 .C_ADDR_WIDTH(C_ADDR_WIDTH),
                 .NUM_BLOCKS(NUM_BLOCKS)) pipeline(.clk(clk),
                                                   .rst(rst),
                                                   .pc_r(pc_o),
                                                   .pc_w(gs_instr_wa_p),
                                                   .instr_we(gs_iwe_p),
                                                   .instr_i(gs_i_data_p),
                                                   .base_rval_i(base_o),
                                                   .wmask_i(mask_o),
                                                   .wrow(row_o), //DELETE IF NO ROW
                                                   .reg_per_thread(rpt_o),
                                                   .wid_i(wid_o),
                                                   .bid_i(bid_o),
                                                   .lwe_gs(gs_dwe_p),
                                                   .addr_gs(gs_l1_wa_p),
                                                   .ldata_gs(gs_l_data_p),
                                                   .cwe_gs(gs_cwe_p),
                                                   .caddr_gs(gs_const_wa_p),
                                                   .cdata_gs(gs_c_data_p),
                                                   .tids(tids_o),
                                                   .spec_d(spec_o),
                                                   .valid(valid_o),
                                                   .bar_o(bar_o),
                                                   .ssy_en(ssy_en),
                                                   .label(label),
                                                   .exit(exit),
                                                   .wstate(wstate),
                                                   .wid_o(wid_p),
                                                   .pc_p1_o(pc_p1_o),
                                                   .next_mask_o(next_mask_o),
                                                   .stack_mask_o(stack_mask_o),
                                                   .take_branch(take_branch),
                                                   .diverge_wb(diverge_wb),
                                                   .contention_wb(contention_wb),
                                                   .warp_update(warp_update),
                                                   .src1_o(src1_o),
                                                   .wid_fp_o(wid_fp_o),
                                                   .bid_o(bid_p),
                                                   .bid_fp_o(bid_fp_o),
                                                   .control_o(control_o));
  
  assign ready = mp_ready;
  
endmodule
