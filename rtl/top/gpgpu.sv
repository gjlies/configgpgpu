//************************
// gjlies 04-24-19 Created
//************************
//Description:
//Top level GPGPU
module gpgpu (clk, rst, any_valid_o);

  parameter SYNTHESIS = 0;                                                      // 1 if synthesizing
  
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
  
  parameter K_DATA_WIDTH = 36;                                                  // Data width of kernel instructions in global scheduler
  parameter K_ADDR_WIDTH = 10;                                                  // Number of bits in kernel address
  parameter K_OP_WIDTH = 4;                                                     // Number of bits in kernel instruction's opcode
  parameter K_CONTROL_WIDTH = 9;                                                // Number of control bits for kernel instructions
  
  parameter MPID_DEPTH = $clog2(NUM_MPS);                                       // Number of bits to represent a MP
  parameter WARPID_DEPTH = $clog2(NUM_WARPS);                                   // Number of bits to represent a warp
  parameter BLOCKID_DEPTH = $clog2(NUM_BLOCKS);                                 // Number of bits to represent a block
  parameter PARAM_DEPTH = $clog2(NUM_PARAMS);                                   // Number of bits to represent a parameter
  parameter NUM_ROWS = WARP_WIDTH / SP_PER_MP;                                  // Number of rows in warp
  parameter ROW_DEPTH = $clog2(NUM_ROWS);                                       // Number of bits to represent a row
  
  input clk;                                                                    // Clock
  input rst;                                                                    // Reset
  
  output any_valid_o;                                                           // Whether or not there are any valid warps
  
  wire iwe;                                                                     // Instruction write enable
  wire cwe;                                                                     // Constant write enable
  wire dwe;                                                                     // L1 write enable
  wire start;                                                                   // Signal Multiprocessors to initialize a block
  wire [MPID_DEPTH - 1 : 0] mpid;                                               // MP selected to initialize block
  wire [BLOCK_DIM - 1 : 0] bdim;                                                // Block dimensions of block to initialize
  wire [GRID_DIM - 1 : 0] gdim;                                                 // Grid dimensions of block to initialize
  wire [R_DATA_WIDTH - 1 : 0] param_o [NUM_PARAMS - 1 : 0];                     // Parameters of block to initialize
  wire [WARPID_DEPTH - 1 : 0] warp_o;                                           // Number of warps belonging to the block
  wire [R_ADDR_WIDTH - 1 : 0] reg_o;                                            // Number of registers required by each thread
  wire [I_ADDR_WIDTH - 1 : 0] instr_wa;                                         // Instruction address to write to
  wire [L_ADDR_WIDTH - 1 : 0] l1_wa;                                            // L1 address to write to
  wire [C_ADDR_WIDTH - 1 : 0] const_wa;                                         // Constant address to write to
  wire [I_DATA_WIDTH - 1 : 0] i_data;                                           // Instruction data to write
  wire [R_DATA_WIDTH - 1 : 0] c_data;                                           // Constant data to write
  wire [R_DATA_WIDTH - 1 : 0] l_data;                                           // L1 data to write
  wire [GRID_DIM - 1 : 0] bidx;                                                 // Block idx of block to initialize

  wire [NUM_MPS - 1 : 0] any_valid;                                             // Whether or not there is a valid warp in the MP
  wire [NUM_MPS - 1 : 0] ready;                                                 // Whether or not the MP is ready for a new block

  //Instantiate the Global Scheduler
  global_scheduler #(.GRID_DIM(GRID_DIM),
                     .BLOCK_DIM(BLOCK_DIM),
                     .NUM_PARAMS(NUM_PARAMS),
                     .GRID_DIM_WIDTH(GRID_DIM_WIDTH),
                     .NUM_MPS(NUM_MPS),
                     .NUM_WARPS(NUM_WARPS),
                     .R_DATA_WIDTH(R_DATA_WIDTH),
                     .R_ADDR_WIDTH(R_ADDR_WIDTH),
                     .I_DATA_WIDTH(I_DATA_WIDTH),
                     .I_ADDR_WIDTH(I_ADDR_WIDTH),
                     .C_ADDR_WIDTH(C_ADDR_WIDTH),
                     .L_ADDR_WIDTH(L_ADDR_WIDTH),
                     .K_DATA_WIDTH(K_DATA_WIDTH),
                     .K_ADDR_WIDTH(K_ADDR_WIDTH),
                     .K_OP_WIDTH(K_OP_WIDTH),
                     .K_CONTROL_WIDTH(K_CONTROL_WIDTH)) global_sched(.clk(clk),
                                                                     .rst(rst),
                                                                     .ready(ready),
                                                                     .iwe(iwe),
                                                                     .cwe(cwe),
                                                                     .dwe(dwe),
                                                                     .start(start),
                                                                     .mpid(mpid),
                                                                     .bdim(bdim),
                                                                     .gdim(gdim),
                                                                     .param_o(param_o),
                                                                     .warp_o(warp_o),
                                                                     .reg_o(reg_o),
                                                                     .instr_wa(instr_wa),
                                                                     .l1_wa(l1_wa),
                                                                     .const_wa(const_wa),
                                                                     .i_data(i_data),
                                                                     .c_data(c_data),
                                                                     .l_data(l_data),
                                                                     .bidx(bidx));
  
  //Instantiate each MP
  genvar gi;
  generate
    for(gi = 0; gi < NUM_MPS; gi = gi + 1) begin
      multiprocessor #(.SYNTHESIS(SYNTHESIS),
                       .GRID_DIM(GRID_DIM),
                       .GRID_DIM_WIDTH(GRID_DIM_WIDTH),
                       .BLOCK_DIM(BLOCK_DIM),
                       .BLOCK_DIM_WIDTH(BLOCK_DIM_WIDTH),
                       .NUM_PARAMS(NUM_PARAMS),
                       .NUM_MPS(NUM_MPS),
                       .NUM_WARPS(NUM_WARPS),
                       .NUM_BLOCKS(NUM_BLOCKS),
                       .SP_PER_MP(SP_PER_MP),
                       .WARP_WIDTH(WARP_WIDTH),
                       .I_DATA_WIDTH(I_DATA_WIDTH),
                       .I_ADDR_WIDTH(I_ADDR_WIDTH),
                       .R_DATA_WIDTH(R_DATA_WIDTH),
                       .R_ADDR_WIDTH(R_ADDR_WIDTH),
                       .C_ADDR_WIDTH(C_ADDR_WIDTH),
                       .L_ADDR_WIDTH(L_ADDR_WIDTH),
                       .CONTROL_WIDTH(CONTROL_WIDTH),
                       .OP_WIDTH(OP_WIDTH),
                       .FUNC_WIDTH(FUNC_WIDTH),
                       .DEST_WIDTH(DEST_WIDTH),
                       .SRC_WIDTH(SRC_WIDTH),
                       .IMM_WIDTH(IMM_WIDTH)) mp_gi(.clk(clk),
                                                    .rst(rst),
                                                    .mpid(gi),
                                                    .gs_iwe(iwe),
                                                    .gs_cwe(cwe),
                                                    .gs_dwe(dwe),
                                                    .gs_start(start),
                                                    .gs_mpid(mpid),
                                                    .gs_bdim(bdim),
                                                    .gs_gdim(gdim),
                                                    .gs_params(param_o),
                                                    .gs_warp(warp_o),
                                                    .gs_reg(reg_o),
                                                    .gs_bidx(bidx),
                                                    .gs_instr_wa(instr_wa),
                                                    .gs_const_wa(const_wa),
                                                    .gs_l1_wa(l1_wa),
                                                    .gs_i_data(i_data),
                                                    .gs_c_data(c_data),
                                                    .gs_l_data(l_data),
                                                    .any_valid(any_valid[gi]),
                                                    .ready(ready[gi]));
                       
    end
  endgenerate
  
  //If there are any warps still going, let user know
  assign any_valid_o = |any_valid;
  
endmodule
