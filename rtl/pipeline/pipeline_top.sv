//************************
// gjlies 04-12-19 Created
// gjlies 04-20-19 Added block ID pipe
// gjlies 04-20-19 Added support for load special instruction
// gjlies 04-21-19 Added muxes for selecting row information
// gjlies 04-26-19 Now sending correct base register address depending on row
// gjlies 04-27-19 Updated to handle case if only one row
// gjlies 04-28-19 Added control output from write back for warp stack to detect ldst
//************************
//Description:
//The top level module for the Multiprocessor pipeline
`include "../misc/mux_generic.sv"
`include "../branch/branch_eval.sv"
`include "../ldst/ldst_bank.sv"
`include "../ldst/ldst_const_cache.sv"
module pipeline_top (rst, clk, pc_r, pc_w, instr_we, instr_i, base_rval_i, wmask_i, wrow, reg_per_thread, wid_i, bid_i, lwe_gs, addr_gs, ldata_gs, cwe_gs,
                    caddr_gs, cdata_gs, tids, spec_d, valid, bar_o, ssy_en, label, exit, wstate, wid_o, pc_p1_o, next_mask_o, stack_mask_o, take_branch,
                    diverge_wb, contention_wb, warp_update, src1_o, wid_fp_o, bid_o, bid_fp_o, control_o);

  parameter SYNTHESIS = 0;                                    // Set to 1 when synthesizing
  parameter I_DATA_WIDTH = 32;                                // Size of data per instr cache entry
  parameter I_ADDR_WIDTH = 10;                                // Bits of address for instr cache
  parameter R_DATA_WIDTH = 32;                                // Size of data per register file entry
  parameter R_ADDR_WIDTH = 10;                                // Bits of address for register file (PER SP)
  parameter SP_PER_MP = 8;                                    // Number of SPs per MP
  parameter CONTROL_WIDTH = 21;                               // Number of bits for control signals
  parameter OP_WIDTH = 6;                                     // Size of opcode
  parameter FUNC_WIDTH = 6;                                   // Size of function
  parameter DEST_WIDTH = 5;                                   // Size of destination
  parameter SRC_WIDTH = 5;                                    // Size of sources
  parameter IMM_WIDTH = 16;                                   // Number of immediate bits
  parameter BANK_WIDTH = $clog2(SP_PER_MP);                   // Number of bits to represent a bank
  parameter L_ADDR_WIDTH = 10;                                // Bits of address for L1 bank
  parameter WARP_WIDTH = 32;                                  // Number of threads in a warp
  parameter ROW_WIDTH = WARP_WIDTH / SP_PER_MP;               // Number of rows in a warp
  parameter ROW_DEPTH = $clog2(ROW_WIDTH);                    // Bits required to represent rows
  parameter NUM_WARPS = 32;                                   // Number of warps on this MP
  parameter WARP_DEPTH = $clog2(NUM_WARPS);                   // Number of bits to represent a warp
  parameter C_DATA_WIDTH = 32;                                // Size of data per constant cache entry
  parameter C_ADDR_WIDTH = 6;                                 // Bits of address for constant cache
  parameter NUM_BLOCKS = 4;                                   // Number of blocks per MP
  parameter BLOCKID_DEPTH = $clog2(NUM_BLOCKS);               // Number of bits to represent block
  
  input rst;                                                  // Reset signal
  input clk;                                                  // Clock
  input [I_ADDR_WIDTH - 1 : 0] pc_r;                          // PC to read
  input [I_ADDR_WIDTH - 1 : 0] pc_w;                          // PC to write (to store instructions)
  input instr_we;                                             // Write enable to instruction cache
  input [I_DATA_WIDTH - 1 : 0] instr_i;                       // Instruction to write
  input [R_ADDR_WIDTH - 1 : 0] base_rval_i;                   // Pointer to base register value of the warp.
  input [WARP_WIDTH - 1 : 0] wmask_i;                         // Mask for enabled/disabled threads in this warp
  input [ROW_DEPTH - 1 : 0] wrow;                             // Current row number of warp REMOVE IF NO ROWS
  input [R_ADDR_WIDTH - 1 : 0] reg_per_thread;                // Registers required per thread
  input [WARP_DEPTH - 1 : 0] wid_i;                           // Warp ID of current warp
  input [BLOCKID_DEPTH - 1 : 0] bid_i;                        // Block ID for current warp
  input lwe_gs;                                               // L1 write enable from global scheduler
  input [L_ADDR_WIDTH - 1 : 0] addr_gs;                       // L1 write addr from global scheduler
  input [R_DATA_WIDTH - 1 : 0] ldata_gs;                      // L1 write data from global scheduler
  input cwe_gs;                                               // Constant cache write enable from global scheduler
  input [C_ADDR_WIDTH - 1 : 0] caddr_gs;                      // Constant cache write addr from global scheduler
  input [R_DATA_WIDTH - 1 : 0] cdata_gs;                      // Constant cache write data from global scheduler
  input valid;                                                // There is a valid instruction in the pipeline
  input [R_DATA_WIDTH - 1 : 0] tids [WARP_WIDTH - 1 : 0];     // Thread Ids for each warp
  input [R_DATA_WIDTH - 1 : 0] spec_d;                        // Special data read from block
  
  output [I_ADDR_WIDTH - 1 : 0] label;                        // label bits of instruction for sync pc and branch label
  output exit;                                                // Exit warp
  output [1 : 0] wstate;                                      // Warp state to write, 0 blocked, 1 ready, 2 BAR
  output [WARP_DEPTH - 1 : 0] wid_o;                          // Warp ID to write to.
  output take_branch;                                         // Signal to take the branch
  output ssy_en;                                              // Write enable to synchronous stack point
  output diverge_wb;                                          // Threads diverging
  output contention_wb;                                       // Contention signal from write back
  output [I_ADDR_WIDTH - 1 : 0] pc_p1_o;                      // PC + 1 to store
  output [WARP_WIDTH - 1 : 0] next_mask_o;                    // Next mask to store
  output [WARP_WIDTH - 1 : 0] stack_mask_o;                   // Stack mask to push
  output warp_update;                                         // Signal warp to update
  output bar_o;                                               // Signal block that this is a barrier instruction
  output [SRC_WIDTH - 1 : 0] src1_o;                          // Instruction src1 currently in decode
  output [WARP_DEPTH - 1 : 0] wid_fp_o;                       // Warp id in decode stage for reading thread IDs
  output [BLOCKID_DEPTH - 1 : 0] bid_o;                       // Block ID in pipeline
  output [BLOCKID_DEPTH - 1 : 0] bid_fp_o;                    // Block ID in pipeline at decode stage for reading special value
  output [CONTROL_WIDTH - 1 : 0] control_o;                   // Control signals from write back
  
  //Signals
  wire [SP_PER_MP - 1 : 0] row_wmask;                                              // Warp mask to use for this row

  wire [I_DATA_WIDTH - 1 : 0] instr_f;                                             // Instruction read from fetch
  wire [I_ADDR_WIDTH - 1 : 0] pc_p1;                                               // PC + 1 of this warp, computed in fetch

  reg [I_DATA_WIDTH - 1 : 0] instr_fp;                                             // Piped instruction
  reg [R_ADDR_WIDTH - 1 : 0] base_rval_fp;                                         // Piped Base register
  reg [SP_PER_MP - 1 : 0] wmask_fp;                                                // Piped warp mask for this row
  reg [ROW_DEPTH - 1 : 0] wrow_fp;                                                 // Piped warp row number REMOVE IF NO ROWS
  reg [WARP_DEPTH - 1 : 0] wid_fp;                                                 // Pipied warp id number
  reg [I_ADDR_WIDTH - 1 : 0] pc_p1_fp;                                             // Piped PC + 1
  reg valid_fp;                                                                    // Piped valid bit
  reg [BLOCKID_DEPTH - 1 : 0] bid_fp;                                              // Piped block ID

  wire [R_ADDR_WIDTH - 1 : 0] base_rval;                                           // Base value to choose

  wire [R_DATA_WIDTH - 1 : 0] thread_ids [SP_PER_MP - 1 : 0];                      // Thread Idxs given to decode

  wire [CONTROL_WIDTH - 1 : 0] control_d;                                          // Control signals
  wire [R_DATA_WIDTH - 1 : 0] src1_d [SP_PER_MP - 1 : 0];                          // all read src1 data from each SP
  wire [R_DATA_WIDTH - 1 : 0] src2_d [SP_PER_MP - 1 : 0];                          // all read src2 data from each SP
  wire [R_DATA_WIDTH - 1 : 0] src3_d [SP_PER_MP - 1 : 0];                          // all read src3 data from each SP
  wire [R_ADDR_WIDTH - 1 : 0] rwa_d;                                               // generated register write address
  wire [IMM_WIDTH - 1 : 0] imm_d;                                                  // immediate
  wire [SRC_WIDTH - 1 : 0] src1_instr_d;                                           // Src1 instruction

  reg [CONTROL_WIDTH - 1 : 0] control_dp;                                          // Piped control signals
  reg [R_DATA_WIDTH - 1 : 0] src1_dp [SP_PER_MP - 1 : 0];                          // Piped read src1 signals for each SP
  reg [R_DATA_WIDTH - 1 : 0] src2_dp [SP_PER_MP - 1 : 0];                          // Piped read src2 signals for each SP
  reg [R_DATA_WIDTH - 1 : 0] src3_dp [SP_PER_MP - 1 : 0];                          // Piped read src3 signals for each SP
  reg [R_ADDR_WIDTH - 1 : 0] rwa_dp;                                               // Piped register write address
  reg [IMM_WIDTH - 1 : 0] imm_dp;                                                  // Piped immediate
  reg [SP_PER_MP - 1 : 0] wmask_dp;                                                // Piped warp mask
  reg [ROW_DEPTH - 1 : 0] wrow_dp;                                                 // Piped warp row number DELETE IF NO ROWS
  reg [WARP_DEPTH - 1 : 0] wid_dp;                                                 // Piped warp id number
  reg [I_ADDR_WIDTH - 1 : 0] pc_p1_dp;                                             // Piped PC + 1
  reg valid_dp;                                                                    // Piped valid bit
  reg [BLOCKID_DEPTH - 1 : 0] bid_dp;                                              // Piped block id

  wire [SP_PER_MP - 1 : 0] btake;                                                  // all branch taken signals from each SP
  wire [R_DATA_WIDTH - 1 : 0] mult_e [SP_PER_MP - 1 : 0];                          // all multiplier outputs from each SP
  wire [R_DATA_WIDTH - 1 : 0] shift_e [SP_PER_MP - 1 : 0];                         // all shift outputs from each SP
  wire [R_DATA_WIDTH - 1 : 0] logical_e [SP_PER_MP - 1 : 0];                       // all logical outputs from each SP
  wire [R_DATA_WIDTH - 1 : 0] add_e [SP_PER_MP - 1 : 0];                           // all add outputs from each SP
  wire [R_DATA_WIDTH - 1 : 0] compare_e [SP_PER_MP - 1 : 0];                       // all compare outputs from each SP

  wire [R_DATA_WIDTH - 1 : 0] bank_data [SP_PER_MP - 1 : 0];                       // All L1 read bank data from each bank
  wire [SP_PER_MP - 1 : 0] [SP_PER_MP - 1 : 0] next_mask_l;                        // All next masks from each ldst_evaluation units
  wire [SP_PER_MP - 1 : 0] [SP_PER_MP - 1 : 0] new_mask_l;                         // All new masks from each ldst_evaluation units
  wire [SP_PER_MP - 1 : 0] contention;                                             // All contention signals from each ldst_evaluation units

  reg [SP_PER_MP - 1 : 0] new_mask_l_final;                                        // Combined new mask from ldst_evaluation units
  reg [SP_PER_MP - 1 : 0] next_mask_l_final;                                       // Combined next mask from ldst_evaluation units

  wire [SP_PER_MP - 1 : 0] next_mask_b;                                            // Next mask from branch evaluation unit
  wire [SP_PER_MP - 1 : 0] stack_mask_b;                                           // Stack mask from branch evaluation unit
  wire [1 : 0] diverging;                                                          // Describes diverging behavior of branch evaluation

  reg contention_final;                                                            // Combined contention signal from ldst_evaluation units

  wire [SP_PER_MP - 1 : 0] mux_new_mask_i [1 : 0];                                 // Mux input for selecting new mask
  wire [SP_PER_MP - 1 : 0] wmask_e;                                                // New mask selected

  wire diverge;                                                                    // 1 if threads diverge

  wire [SP_PER_MP - 1 : 0] mux_next_mask_i [3 : 0];                                // Mux input for selecting next mask
  wire [SP_PER_MP - 1 : 0] wmask_next_e;                                           // Next mask selected
  wire [1 : 0] mux_next_mask_s;                                                    // Selector for choosing next mask

  wire [SP_PER_MP - 1 : 0] mux_stack_mask_i [1 : 0];                               // Mux input for selecting stack mask
  wire [SP_PER_MP - 1 : 0] stack_mask_e;                                           // Stack mask selected
  wire [R_DATA_WIDTH - 1 : 0] const_data;                                          // Data read from constant cache

  reg [CONTROL_WIDTH - 1 : 0] control_ep;                                          // Piped control signals
  reg [SP_PER_MP - 1 : 0] wmask_ep;                                                // Piped warp mask
  reg [IMM_WIDTH - 1 : 0] imm_ep;                                                  // Piped immediate
  reg [R_ADDR_WIDTH - 1 : 0] rwa_ep;                                               // Piped register write address
  reg [ROW_DEPTH - 1 : 0] wrow_ep;                                                 // Piped warp row number DELETE IF NO ROWS
  reg [WARP_DEPTH - 1 : 0] wid_ep;                                                 // Piped warp id number
  reg [I_ADDR_WIDTH - 1 : 0] pc_p1_ep;                                             // Piped PC + 1
  reg [R_DATA_WIDTH - 1 : 0] const_data_ep;                                        // Piped read constant data
  reg [R_DATA_WIDTH - 1 : 0] bank_data_ep [SP_PER_MP - 1 : 0];                     // Piped read L1 data
  reg [R_DATA_WIDTH - 1 : 0] src1_ep [SP_PER_MP - 1 : 0];                          // Piped read src1
  reg [R_DATA_WIDTH - 1 : 0] mult_ep [SP_PER_MP - 1 : 0];                          // Piped multiplier outputs
  reg [R_DATA_WIDTH - 1 : 0] shift_ep [SP_PER_MP - 1 : 0];                         // Piped shift outputs
  reg [R_DATA_WIDTH - 1 : 0] logical_ep [SP_PER_MP - 1 : 0];                       // Piped logical outputs
  reg [R_DATA_WIDTH - 1 : 0] add_ep [SP_PER_MP - 1 : 0];                           // Piped add outputs
  reg [R_DATA_WIDTH - 1 : 0] compare_ep [SP_PER_MP - 1 : 0];                       // Piped compare outputs
  reg valid_ep;                                                                    // Piped valid bit
  reg [BLOCKID_DEPTH - 1 : 0] bid_ep;                                              // Piped block id

  wire [R_DATA_WIDTH - 1 : 0] rdata_wb [SP_PER_MP - 1 : 0];                        // selected register data to write back for each SP
  wire [SP_PER_MP - 1 : 0] rwe_wb;                                                 // register write enables for each SP

  reg [ROW_WIDTH - 1 : 0] branches_taken;                                          // Keep track if each row takes a branch.
  reg [ROW_WIDTH - 1 : 0] diverging_row;                                           // Keep track if each row diverges
  reg [ROW_WIDTH - 1 : 0] contention_row;                                          // Keep track if each row has ldst contention
  reg [SP_PER_MP - 1 : 0] next_wmask [ROW_WIDTH - 1 : 0];                          // Keep track of next masks for each row
  reg [SP_PER_MP - 1 : 0] next_stack_mask [ROW_WIDTH - 1 : 0];                     // Keep track of stack masks for each row

  reg warp_update;                                                                 // Signal to update the warp
  
  wire [C_ADDR_WIDTH - 1 : 0] const_addrs [SP_PER_MP - 1 : 0];                     // Addresses for constant cache
  wire [L_ADDR_WIDTH - 1 : 0] l1_addrs [SP_PER_MP - 1 : 0];                        // Addresses for l1 cache

  //Muxes to select data based on warp row
  generate
  if(ROW_WIDTH > 1) begin : row_mask_in
    reg [SP_PER_MP - 1 : 0] row_wmask_i [ROW_WIDTH - 1 : 0];
  
    integer a;
    always @ (wmask_i) begin
      for(a = 0; a < ROW_WIDTH; a = a + 1) begin
        row_wmask_i[a] <= wmask_i[SP_PER_MP*a +: (SP_PER_MP - 1)];
      end
    end
  
    mux_generic #(.INPUT_WIDTH(SP_PER_MP),
                  .NUM_INPUTS(ROW_WIDTH)) mux_wmask(.in(row_wmask_i),
                                                    .sel(wrow),
                                                    .out(row_wmask));
  end
  else begin : row_mask_in
    assign row_wmask = wmask_i;
  end
  endgenerate
  
  //Instantiate Fetch Unit
  fetch #(.I_DATA_WIDTH(I_DATA_WIDTH),
          .I_ADDR_WIDTH(I_ADDR_WIDTH),
          .SP_PER_MP(SP_PER_MP)) fetch_unit(.clk(clk),
                                            .pc_r(pc_r),
                                            .pc_w(pc_w),
                                            .we(instr_we),
                                            .instr_i(instr_i),
                                            .instr_f(instr_f),
                                            .pc_p1(pc_p1));
  

  //Pipeline Fetch to Decode
  always @ (posedge clk or negedge rst) begin
    if(rst == 0) begin
      instr_fp     <= 0;
      base_rval_fp <= 0;
      wmask_fp     <= 0;
      wid_fp       <= 0;
      pc_p1_fp     <= 0;
      valid_fp     <= 0;
      bid_fp       <= 0;
    end
    else begin
      instr_fp     <= instr_f;
      base_rval_fp <= base_rval;
      wmask_fp     <= row_wmask;
      wid_fp       <= wid_i;
      pc_p1_fp     <= pc_p1;
      valid_fp     <= valid;
      bid_fp       <= bid_i;
    end
  end
  
  //Only store wrow if there are rows
  generate
    if(ROW_WIDTH > 1) begin : row_fp
      always @ (posedge clk or negedge rst) begin
        if(rst == 0) begin
          wrow_fp <= 0;
        end
        else begin
          wrow_fp <= wrow;
        end
      end
    end
  endgenerate
  
  //Instantiate an adder to offset the base register value from the previous value
  generate
    if(ROW_WIDTH > 1) begin : base_offset
      wire [R_ADDR_WIDTH - 1 : 0] base_rval_offset;                     //Offset register value
      assign base_rval_offset = base_rval_fp + reg_per_thread;
      
      //On wrow 0 pick base_rval_i, otherwise pick offset value
      assign base_rval = (wrow == 0) ? base_rval_i : base_rval_offset;
      
    end
    else begin : base_offset
      //If there is only one row always grab the base register
      assign base_rval = base_rval_i;
    end
  endgenerate

  //Muxes for selecting thread IDs to give to decode
  genvar gp;
  genvar gq;
  generate
  if(ROW_WIDTH > 1) begin : thread_ids_i
    //Create a mux to choose thread ID for each index
    for(gp = 0; gp < SP_PER_MP; gp = gp + 1) begin
      
      wire [R_DATA_WIDTH - 1 : 0] mux_thread_ids_i [ROW_WIDTH - 1 : 0];

      for(gq = 0; gq < ROW_WIDTH; gq = gq + 1) begin
        assign mux_thread_ids_i[gq] = tids[gq*SP_PER_MP + gp];
      end
      
      mux_generic #(.INPUT_WIDTH(R_DATA_WIDTH),
                    .NUM_INPUTS(ROW_WIDTH))  mux_thread_ids(.in(mux_thread_ids_i),
                                                            .sel(wrow),
                                                            .out(thread_ids[gp]));                                              
    end
  end
  else begin : thread_ids_i
    assign thread_ids = tids;
  end
  endgenerate
  
  //Instantiate decode unit
  decode #(.I_DATA_WIDTH(I_DATA_WIDTH),
           .R_DATA_WIDTH(R_DATA_WIDTH),
           .R_ADDR_WIDTH(R_ADDR_WIDTH),
           .SP_PER_MP(SP_PER_MP),
           .CONTROL_WIDTH(CONTROL_WIDTH),
           .OP_WIDTH(OP_WIDTH),
           .FUNC_WIDTH(FUNC_WIDTH),
           .DEST_WIDTH(DEST_WIDTH),
           .SRC_WIDTH(SRC_WIDTH),
           .IMM_WIDTH(IMM_WIDTH)) decoding_unit(.clk(clk),
                                                .instr_f(instr_fp),
                                                .base_rval_f(base_rval_fp),
                                                .rwe_wb(rwe_wb),
                                                .rdata_wb(rdata_wb),
                                                .rwa_wb(rwa_ep),
                                                .tids(thread_ids),
                                                .spec_d(spec_d),
                                                .control_d(control_d),
                                                .src1_d(src1_d),
                                                .src2_d(src2_d),
                                                .src3_d(src3_d),
                                                .rwa_d(rwa_d),
                                                .imm_d(imm_d),
                                                .src1_o(src1_instr_d));
                                              
  //Pipeline Decode to Execute
  //Store srcs for each SP
  genvar gi;
  generate
    for(gi = 0; gi < SP_PER_MP; gi = gi + 1) begin : src_pipe
      always @ (posedge clk or negedge rst) begin
        if(rst == 0) begin
          src1_dp[gi] <= 0;
          src2_dp[gi] <= 0;
          src3_dp[gi] <= 0;
        end
        else begin
          src1_dp[gi] <= src1_d[gi];
          src2_dp[gi] <= src2_d[gi];
          src3_dp[gi] <= src3_d[gi];
        end
      end
    end
  endgenerate
  
  //Store rest of signals
  always @ (posedge clk or negedge rst) begin
    if(rst == 0) begin
      control_dp <= 0;
      rwa_dp     <= 0;
      imm_dp     <= 0;
      wmask_dp   <= 0;
      wid_dp     <= 0;
      pc_p1_dp   <= 0;
      valid_dp   <= 0;
      bid_dp     <= 0;
    end
    else begin
      control_dp <= control_d;
      rwa_dp     <= rwa_d;
      imm_dp     <= imm_d;
      wmask_dp   <= wmask_fp;
      wid_dp     <= wid_fp;
      pc_p1_dp   <= pc_p1_fp;
      valid_dp   <= valid_fp;
      bid_dp     <= bid_fp;
    end
  end
  
  //Only store wrow if there are rows
  generate
    if(ROW_WIDTH > 1) begin : row_dp
      always @ (posedge clk or negedge rst) begin
        if(rst == 0) begin
          wrow_dp <= 0;
        end
        else begin
          wrow_dp <= wrow_fp;
        end
      end
    end
  endgenerate
  
  //Instantiate Execute Units for each SP
  genvar gj;
  generate
    for(gj = 0; gj < SP_PER_MP; gj = gj + 1) begin : execute_inst
      execute #(.R_DATA_WIDTH(R_DATA_WIDTH),
                .CONTROL_WIDTH(CONTROL_WIDTH),
                .SP_PER_MP(SP_PER_MP),
                .IMM_WIDTH(IMM_WIDTH)) execute_unit(.src1_d(src1_dp[gj]),
                                                    .src2_d(src2_dp[gj]),
                                                    .src3_d(src3_dp[gj]),
                                                    .control_d(control_dp),
                                                    .btake(btake[gj]),
                                                    .mult_e(mult_e[gj]),
                                                    .shift_e(shift_e[gj]),
                                                    .logical_e(logical_e[gj]),
                                                    .add_e(add_e[gj]),
                                                    .compare_e(compare_e[gj]));
    end
  endgenerate
  
  //Instantiate ldst units and L1 banks
  genvar gy;
  generate
    for(gy = 0; gy < SP_PER_MP; gy = gy + 1) begin
      wire [R_DATA_WIDTH - 1 : 0] l1_addr_temp;
      assign l1_addr_temp = src1_dp[gy];
      assign l1_addrs[gy] = l1_addr_temp[L_ADDR_WIDTH - 1 : 0];
    end
  endgenerate
  
  genvar gl;
  generate
    for(gl = 0; gl < SP_PER_MP; gl = gl + 1) begin : ldst_bank
      wire [BANK_WIDTH - 1 : 0] bank_num;

      assign bank_num = gl;
      
      ldst_bank #(.DATA_WIDTH(R_DATA_WIDTH),
                  .ADDR_WIDTH(L_ADDR_WIDTH),
                  .SP_PER_MP(SP_PER_MP),
                  .CONTROL_WIDTH(CONTROL_WIDTH),
                  .SYNTHESIS(SYNTHESIS)) l1_bank(.clk(clk),
                                                 .addrs(l1_addrs),
                                                 .datas(src2_dp),
                                                 .cur_mask(wmask_dp),
                                                 .bank_num(bank_num),
                                                 .control(control_dp),
                                                 .lwe_gs(lwe_gs),
                                                 .addr_gs(addr_gs),
                                                 .ldata_gs(ldata_gs),
                                                 .bank_data(bank_data[gl]),
                                                 .next_mask(next_mask_l[gl]),
                                                 .new_mask(new_mask_l[gl]),
                                                 .contention(contention[gl]));
    end
  endgenerate
  
  //Setup new and next masks, determine if any contention
  //AND all new masks together
  integer i;
  always @ (new_mask_l or wmask_dp or contention_final) begin
    new_mask_l_final <= wmask_dp;
    if(contention_final) begin
      for(i = 0; i < SP_PER_MP; i = i + 1) begin
        new_mask_l_final <= new_mask_l_final & new_mask_l[i];
      end
    end
  end
  
  //OR all next masks together
  integer j;
  always @ (next_mask_l) begin
    next_mask_l_final <= 0;
    for(j = 0; j < SP_PER_MP; j = j + 1) begin
      next_mask_l_final <= next_mask_l_final | next_mask_l[j];
    end
  end
  
  //OR all contention bits together
  integer k;
  always @ (contention) begin
    contention_final <= 0;
    for(k = 0; k < SP_PER_MP; k = k + 1) begin
      contention_final <= contention_final | contention[k];
    end
  end
  
  //Instantiate branch evaluation unit
  branch_eval #(.SP_PER_MP(SP_PER_MP)) branch_eval_unit(.taken(btake),
                                                        .cur_mask(wmask_dp),
                                                        .next_mask(next_mask_b),
                                                        .stack_mask(stack_mask_b),
                                                        .diverging(diverging));
  
  //Pick between current wmask or ldst new mask if there is contention
  assign mux_new_mask_i[0] = wmask_dp;
  assign mux_new_mask_i[1] = new_mask_l_final;
  
  mux_generic #(.INPUT_WIDTH(SP_PER_MP),
                .NUM_INPUTS(2)) mux_new_mask(.in(mux_new_mask_i),
                                             .sel(contention_final),
                                             .out(wmask_e));
                                             
  //Pick between current wmask, ldst next mask or branch next mask for the next wmask
  assign diverge = ~diverging[0] & ~diverging[1];
  
  //Mux for selecting next mask
  assign mux_next_mask_i[0] = wmask_dp;
  assign mux_next_mask_i[1] = next_mask_b;
  assign mux_next_mask_i[2] = next_mask_l_final;
  assign mux_next_mask_i[3] = next_mask_l_final;
  assign mux_next_mask_s[0] = diverge;
  assign mux_next_mask_s[1] = contention_final;
  
  mux_generic #(.INPUT_WIDTH(SP_PER_MP),
                .NUM_INPUTS(4)) mux_next_mask(.in(mux_next_mask_i),
                                              .sel(mux_next_mask_s),
                                              .out(wmask_next_e));
  
  //Mux for selecting stack mask
  assign mux_stack_mask_i[0] = wmask_dp;
  assign mux_stack_mask_i[1] = stack_mask_b;
  
  mux_generic #(.INPUT_WIDTH(SP_PER_MP),
                .NUM_INPUTS(2)) mux_stack_mask(.in(mux_stack_mask_i),
                                               .sel(diverge),
                                               .out(stack_mask_e));
  
  //Instantiate Constant Cache
  //Generate address signals for the cache
  genvar gz;
  generate
    for(gz = 0; gz < SP_PER_MP; gz = gz + 1) begin
      wire [R_DATA_WIDTH - 1 : 0] const_addr_temp;
      assign const_addr_temp = src1_dp[gz];
      assign const_addrs[gz] = const_addr_temp[C_ADDR_WIDTH - 1 : 0];
    end
  endgenerate
  
  ldst_const_cache #(.DATA_WIDTH(C_DATA_WIDTH),
                     .ADDR_WIDTH(C_ADDR_WIDTH),
                     .SP_PER_MP(SP_PER_MP)) const_cache(.clk(clk),
                                                        .addrs(const_addrs),
                                                        .cur_mask(wmask_dp),
                                                        .cwe_gs(cwe_gs),
                                                        .caddr_gs(caddr_gs),
                                                        .cdata_gs(cdata_gs),
                                                        .const_data(const_data));
                     
  //Pipeline Execute to Write Back
  //Store outputs for each SP
  genvar gk;
  generate
    for(gk = 0; gk < SP_PER_MP; gk = gk + 1) begin : exe_out_pipe
      always @ (posedge clk or negedge rst) begin
        if(rst == 0) begin
          bank_data_ep[gk] <= 0;
          src1_ep[gk]      <= 0;
          mult_ep[gk]      <= 0;
          shift_ep[gk]     <= 0;
          logical_ep[gk]   <= 0;
          add_ep[gk]       <= 0;
          compare_ep[gk]   <= 0;
        end
        else begin
          bank_data_ep[gk] <= bank_data[gk];
          src1_ep[gk]      <= src1_dp[gk];
          mult_ep[gk]      <= mult_e[gk];
          shift_ep[gk]     <= shift_e[gk];
          logical_ep[gk]   <= logical_e[gk];
          add_ep[gk]       <= add_e[gk];
          compare_ep[gk]   <= compare_e[gk];
        end
      end
    end
  endgenerate
  
  //Store rest of signals
  always @ (posedge clk or negedge rst) begin
    if(rst == 0) begin
      control_ep    <= 0;
      wmask_ep      <= 0;
      imm_ep        <= 0;
      rwa_ep        <= 0;
      wid_ep        <= 0;
      const_data_ep <= 0;
      pc_p1_ep      <= 0;
      valid_ep      <= 0;
      bid_ep        <= 0;
    end
    else begin
      control_ep    <= control_dp;
      wmask_ep      <= wmask_e;
      imm_ep        <= imm_dp;
      rwa_ep        <= rwa_dp;
      wid_ep        <= wid_dp;
      const_data_ep <= const_data;
      pc_p1_ep      <= pc_p1_dp;
      valid_ep      <= valid_dp;
      bid_ep        <= bid_dp;
    end
  end
  
  //Only store wrow if there are rows
  generate
    if(ROW_WIDTH > 1) begin : row_ep
      always @ (posedge clk or negedge rst) begin
        if(rst == 0) begin
          wrow_ep <= 0;
        end
        else begin
          wrow_ep <= wrow_dp;
        end
      end
    end
  endgenerate
  
  //Instantiate Write Back Unit for each SP
  
  genvar gn;
  generate
    for(gn = 0; gn < SP_PER_MP; gn = gn + 1) begin : write_back_inst
      write_back #(.CONTROL_WIDTH(CONTROL_WIDTH),
                   .R_DATA_WIDTH(R_DATA_WIDTH),
                   .IMM_WIDTH(IMM_WIDTH),
                   .SP_PER_MP(SP_PER_MP)) write_back_unit(.control_e(control_ep),
                                                          .mult_e(mult_ep[gn]),
                                                          .shift_e(shift_ep[gn]),
                                                          .logical_e(logical_ep[gn]),
                                                          .add_e(add_ep[gn]),
                                                          .compare_e(compare_ep[gn]),
                                                          .src1_e(src1_ep[gn]),
                                                          .imm_e(imm_ep),
                                                          .wmask_e(wmask_ep[gn]),
                                                          .l1_e(bank_data_ep),
                                                          .const_e(const_data_ep),
                                                          .rdata_wb(rdata_wb[gn]),
                                                          .rwe_wb(rwe_wb[gn]));
    end
  endgenerate
  
  //Pipe row specific information so we can update the warp all at once
  //Setup first pipe so we can shift others
  always @ (posedge clk or negedge rst) begin
    if(rst == 0) begin
      branches_taken[0]  <= 0;
      diverging_row[0]   <= 0;
      contention_row[0]  <= 0;
      next_wmask[0]      <= 0;
      next_stack_mask[0] <= 0;
    end
    else begin
      branches_taken[0]  <= diverge | diverging[1];
      diverging_row[0]   <= diverge;
      contention_row[0]  <= contention_final;
      next_wmask[0]      <= wmask_next_e;
      next_stack_mask[0] <= stack_mask_e;
    end
  end
                                                        
  //Shift Until last row is finished
  genvar go;
  generate
    if(ROW_WIDTH > 1) begin
    for(go = 1; go < ROW_WIDTH; go = go + 1) begin : shift_warp_info
      always @ (posedge clk or negedge rst) begin
        if(rst == 0) begin
          branches_taken[go]  <= 0;
          diverging_row[go]   <= 0;
          contention_row[go]  <= 0;
          next_wmask[go]      <= 0;
          next_stack_mask[go] <= 0;
        end
        else begin
          branches_taken[go]  <= branches_taken[go - 1];
          diverging_row[go]   <= diverging_row[go - 1];
          contention_row[go]  <= contention_row[go - 1];
          next_wmask[go]      <= next_wmask[go - 1];
          next_stack_mask[go] <= next_stack_mask[go - 1];
        end
      end
    end
    end
  endgenerate
  
  //Write to warp when last row is in write back and theres an instruction in the pipeline
  generate
  if(ROW_WIDTH > 1) begin : warp_update_gen
    always @ (wrow_ep or valid_ep) begin
      if(wrow_ep == (ROW_WIDTH - 1) & valid_ep) begin
        warp_update <= 1;
      end
      else begin
        warp_update <= 0;
      end
    end
  end
  else begin : warp_update_gen
    always @(valid_ep) begin
      warp_update <= valid_ep;
    end 
  end
  endgenerate
  
  //Assign Outputs
  //Take branch if any rows take the branch
  assign take_branch = |branches_taken;
  
  //Diverge if any rows diverge
  assign diverge_wb = |diverging_row;
  
  //Check if any ldst contention on rows
  assign contention_wb = |contention_row;
  
  //Assign next mask and stack mask
  genvar gr;
  generate
  if(ROW_WIDTH > 1) begin : next_mask_out
    for(gr = 0; gr < ROW_WIDTH; gr = gr + 1) begin
      assign next_mask_o[gr*SP_PER_MP +: (SP_PER_MP - 1)] = next_wmask[gr];
      assign stack_mask_o[gr*SP_PER_MP +: (SP_PER_MP - 1)] = next_stack_mask[gr];
    end
  end
  else begin : next_mask_out
    assign next_mask_o = next_wmask[0];
    assign stack_mask_o = next_stack_mask[0];
  end
  endgenerate
  
  //Assign rest of outputs, no need to pipe as same for all rows
  assign label = imm_ep;
  assign exit = control_ep[19];
  assign wstate = {control_ep[17], 1'b1};
  assign wid_o = wid_ep;
  assign ssy_en = control_ep[18];
  assign pc_p1_o = pc_p1_ep;
  assign bar_o = control_ep[17];
  assign bid_o = bid_ep;
  assign src1_o = src1_instr_d;
  assign wid_fp_o = wid_fp;
  assign bid_fp_o = bid_fp;
  assign control_o = control_ep;
  
endmodule
