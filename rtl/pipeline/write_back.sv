//************************
// gjlies 04-14-19 Created
//************************
//Description:
//The write back stage of the multiprocessor pipeline, instantiated once per SP
`include "../misc/mux_generic.sv"
module write_back (control_e, mult_e, shift_e, logical_e, add_e, compare_e, src1_e, imm_e, wmask_e, l1_e, const_e, rdata_wb, rwe_wb);

  parameter CONTROL_WIDTH = 21;                               // Bits of control signals
  parameter R_DATA_WIDTH = 32;                                // Size of data per register file entry
  parameter IMM_WIDTH = 16;                                   // Number of immediate bits
  parameter SP_PER_MP = 8;                                    // Number of SPs per MP
  parameter BANK_DEPTH = $clog2(SP_PER_MP);                   // Bits to represent Banks
  
  input [CONTROL_WIDTH - 1 : 0] control_e;                    // Control signals from execution
  input [R_DATA_WIDTH - 1 : 0] mult_e;                        // Multiplier output from execution
  input [R_DATA_WIDTH - 1 : 0] shift_e;                       // Shift output from execution
  input [R_DATA_WIDTH - 1 : 0] logical_e;                     // Logical output from execution
  input [R_DATA_WIDTH - 1 : 0] add_e;                         // Add output from execution
  input [R_DATA_WIDTH - 1 : 0] compare_e;                     // Compare output from execution
  input [R_DATA_WIDTH - 1 : 0] src1_e;                        // Src1 output from execution
  input [IMM_WIDTH - 1 : 0] imm_e;                            // Immediate from execution
  input wmask_e;                                              // Warp mask from execution
  input [R_DATA_WIDTH - 1 : 0] l1_e [SP_PER_MP];              // L1 data from execution
  input [R_DATA_WIDTH - 1 : 0] const_e;                       // Constant data from execution
  
  output [R_DATA_WIDTH - 1 : 0] rdata_wb;                     // Register data to write back
  output rwe_wb;                                              // Register write enable
  
  
  //Muxes for selecting data to store
  
  //Mux for selecting ALU output using aluop control signal
  //0 for mult, 1 for add, 2 for shift, 3 for logical
  wire [R_DATA_WIDTH - 1 : 0] mux_aluop_i [3 : 0];
  wire [R_DATA_WIDTH - 1 : 0] mux_aluop_o;
  assign mux_aluop_i[0] = mult_e;
  assign mux_aluop_i[1] = add_e;
  assign mux_aluop_i[2] = shift_e;
  assign mux_aluop_i[3] = logical_e;
  
  mux_generic #(.INPUT_WIDTH(R_DATA_WIDTH),
                .NUM_INPUTS(4)) mux_aluop(.in(mux_aluop_i),
                                          .sel(control_e[10:9]),
                                          .out(mux_aluop_o));
  
  //Mux for choosing src1 or imm for MV or MVI instructions
  //0 for src1, 1 for imm
  wire [R_DATA_WIDTH - 1 : 0] mux_mv_i [1:0];
  wire [R_DATA_WIDTH - 1 : 0] imm_ext;
  wire [R_DATA_WIDTH - 1 : 0] mux_mv_o;
  assign imm_ext = {0,imm_e};
  assign mux_mv_i[0] = src1_e;
  assign mux_mv_i[1] = imm_ext;
  
  mux_generic #(.INPUT_WIDTH(R_DATA_WIDTH),
                .NUM_INPUTS(2)) mux_mv(.in(mux_mv_i),
                                       .sel(control_e[12]),
                                       .out(mux_mv_o));
  
  //Mux for choosing L1 datas from banks
  wire [R_DATA_WIDTH - 1 : 0] mux_l1_o;
  
  mux_generic #(.INPUT_WIDTH(R_DATA_WIDTH),
                .NUM_INPUTS(SP_PER_MP)) mux_l1(.in(l1_e),
                                               .sel(src1_e[BANK_DEPTH - 1 : 0]),
                                               .out(mux_l1_o));
                                               
  //Mux for choosing between L1 data or Constant data
  //0 if L1, 1 if Constant
  wire [R_DATA_WIDTH - 1 : 0] mux_ld_i [1:0];
  wire [R_DATA_WIDTH - 1 : 0] mux_ld_o;
  assign mux_ld_i[0] = mux_l1_o;
  assign mux_ld_i[1] = const_e;
  
  mux_generic #(.INPUT_WIDTH(R_DATA_WIDTH),
                .NUM_INPUTS(2)) mux_ld(.in(mux_ld_i),
                                       .sel(control_e[11]),
                                       .out(mux_ld_o));
                                       
  //Mux for choosing between alu, compare, mv, or ld outputs
  //0 for alu, 1 for compare, 2 for mv, 3 for ld
  wire [R_DATA_WIDTH - 1 : 0] mux_wb_i [3 : 0];
  assign mux_wb_i[0] = mux_aluop_o;
  assign mux_wb_i[1] = compare_e;
  assign mux_wb_i[2] = mux_mv_o;
  assign mux_wb_i[3] = mux_ld_o;
  
  mux_generic #(.INPUT_WIDTH(R_DATA_WIDTH),
                .NUM_INPUTS(4)) mux_wb(.in(mux_wb_i),
                                       .sel(control_e[14:13]),
                                       .out(rdata_wb));
  
  //Output assignments
  assign rwe_wb = control_e[0] & wmask_e;
  
endmodule
