//************************
// gjlies 04-12-19 Created
// gjlies 04-14-19 Removed / Updated inputs
// gjlies 04-20-19 Added ability to grab special register values and thread IDs
//************************
//Description:
//The decode stage of the multiprocessor pipeline
`include "../decode/decode_unit.sv"
`include "../alu/adder.sv"
`include "../bram/bram_3_1.sv"
`include "../misc/mux_generic.sv"
module decode (clk, instr_f, base_rval_f, rwe_wb, rdata_wb, rwa_wb, tids, spec_d, control_d, src1_d, src2_d, src3_d, rwa_d, imm_d, src1_o);

  parameter I_DATA_WIDTH = 32;                                // Number of bits in an instruction
  parameter R_DATA_WIDTH = 32;                                // Size of data per register file entry
  parameter R_ADDR_WIDTH = 10;                                // Bits of address for register file (PER SP)
  parameter SP_PER_MP = 8;                                    // Number of SPs per MP
  parameter CONTROL_WIDTH = 21;                               // Number of bits for control signals
  parameter OP_WIDTH = 6;                                     // Size of opcode
  parameter FUNC_WIDTH = 6;                                   // Size of function
  parameter DEST_WIDTH = 5;                                   // Size of destination
  parameter SRC_WIDTH = 5;                                    // Size of sources
  parameter IMM_WIDTH = 16;                                   // Number of immediate bits
  
  input clk;                                                  // Clock
  input [I_DATA_WIDTH - 1 : 0] instr_f;                       // Instruction to write
  
  input [R_ADDR_WIDTH - 1 : 0] base_rval_f;                   // Pointer to base register value of the warp.
  
  //Inputs from Write Back
  input [SP_PER_MP - 1 : 0] rwe_wb;                           // Register write enables from write back
  input [R_DATA_WIDTH - 1 : 0] rdata_wb [SP_PER_MP - 1 : 0];  // Data to write from Write Back
  input [R_ADDR_WIDTH - 1 : 0] rwa_wb;                        // Register write addr from write back
  input [R_DATA_WIDTH - 1 : 0] tids [SP_PER_MP - 1 : 0];      // Thread IDs read from warp
  input [R_DATA_WIDTH - 1 : 0] spec_d;                        // Special data from block
  
  output [CONTROL_WIDTH - 1 : 0] control_d;                   // Piped Control Signals
  output [R_DATA_WIDTH - 1 : 0] src1_d [SP_PER_MP - 1 : 0];   // Piped Source1
  output [R_DATA_WIDTH - 1 : 0] src2_d [SP_PER_MP - 1 : 0];   // Piped Source2
  output [R_DATA_WIDTH - 1 : 0] src3_d [SP_PER_MP - 1 : 0];   // Piped Source3
  output [R_ADDR_WIDTH - 1 : 0] rwa_d;                        // Register write address for instruction currently in decode
  output [IMM_WIDTH - 1 : 0] imm_d;                           // immediate for MVI
  output [SRC_WIDTH - 1 : 0] src1_o;                          //Src1 instruction out for load special
  
  wire [CONTROL_WIDTH - 1 : 0] control;                       // control signals
  wire [R_ADDR_WIDTH - 1 : 0] src1_addr;                      // Src1 addr for register files
  wire [R_ADDR_WIDTH - 1 : 0] src2_addr;                      // Src2 addr for register files
  wire [R_ADDR_WIDTH - 1 : 0] src3_addr;                      // Src3 addr for register files
  wire [R_ADDR_WIDTH - 1 : 0] rwa;                            // Write addr for register files
  
  //Instantiate the Decode Unit for decoding instructions
  decode_unit #(.OP_WIDTH(OP_WIDTH),
                .FUNC_WIDTH(FUNC_WIDTH),
                .CONTROL_WIDTH(CONTROL_WIDTH)) instr_decode(.op(instr_f[FUNC_WIDTH + 3*SRC_WIDTH + DEST_WIDTH + OP_WIDTH - 1 : FUNC_WIDTH + 3*SRC_WIDTH + DEST_WIDTH]),
                                                            .func(instr_f[FUNC_WIDTH - 1 : 0]),
                                                            .control(control));

  //Instantiate adders for offsetting regfile address
  adder #(.SRC_WIDTH(R_ADDR_WIDTH),
          .OUT_WIDTH(R_ADDR_WIDTH)) raddr_dest(.src1(base_rval_f),
                                               .src2(instr_f[FUNC_WIDTH + 3*SRC_WIDTH + DEST_WIDTH - 1 : FUNC_WIDTH + 3*SRC_WIDTH]),
                                               .cin(1'b0),
                                               .out(rwa));
                                               
  adder #(.SRC_WIDTH(R_ADDR_WIDTH),
          .OUT_WIDTH(R_ADDR_WIDTH)) raddr_src1(.src1(base_rval_f),
                                               .src2(instr_f[FUNC_WIDTH + 3*SRC_WIDTH - 1 : FUNC_WIDTH + 2*SRC_WIDTH]),
                                               .cin(1'b0),
                                               .out(src1_addr));
                                               
  adder #(.SRC_WIDTH(R_ADDR_WIDTH),
          .OUT_WIDTH(R_ADDR_WIDTH)) raddr_src2(.src1(base_rval_f),
                                               .src2(instr_f[FUNC_WIDTH + 2*SRC_WIDTH - 1 : FUNC_WIDTH + 1*SRC_WIDTH]),
                                               .cin(1'b0),
                                               .out(src2_addr));
                                               
  adder #(.SRC_WIDTH(R_ADDR_WIDTH),
          .OUT_WIDTH(R_ADDR_WIDTH)) raddr_src3(.src1(base_rval_f),
                                               .src2(instr_f[FUNC_WIDTH + 1*SRC_WIDTH - 1 : FUNC_WIDTH]),
                                               .cin(1'b0),
                                               .out(src3_addr));
  
  //Instantiate the Register Files.  One for each SP.
  wire [R_DATA_WIDTH - 1 : 0] src1_data [SP_PER_MP - 1 : 0];
  genvar gi;
  generate
    for(gi = 0; gi < SP_PER_MP; gi = gi + 1) begin : rfile
      //Instantiate the register file for this SP
      bram_3_1 #(.DATA_WIDTH(R_DATA_WIDTH),
                 .ADDR_WIDTH(R_ADDR_WIDTH)) regfile(.clk(clk),
                                                    .ra1(src1_addr),
                                                    .ra2(src2_addr),
                                                    .ra3(src3_addr),
                                                    .wa(rwa_wb),
                                                    .we(rwe_wb[gi]),
                                                    .di(rdata_wb[gi]),
                                                    .do1(src1_data[gi]),
                                                    .do2(src2_d[gi]),
                                                    .do3(src3_d[gi]));
                                                    
    end
  endgenerate
  
  //Mux to select between src1 data, special, or thread IDs
  wire [1 : 0] mux_src1_data_sel;                           //Selector for choosing src1 data
  wire max_src1;                                            //1 when src1 instr is max value
  
  //check if src1 instruction value is max, if so set signal so we can grab thread IDs
  assign max_src1 = (~instr_f[SRC_WIDTH*3 + FUNC_WIDTH - 1 : SRC_WIDTH*2 + FUNC_WIDTH] == 0);
  
  //Load src1 data when not lds instruction, special when lds but not max src value, 
  assign mux_src1_data_sel[1] = control_d[20]; 
  assign mux_src1_data_sel[0] = max_src1;
  
  genvar gj;
  generate
    for(gj = 0; gj < SP_PER_MP; gj = gj + 1) begin : src1_data_gj
      wire [R_DATA_WIDTH - 1 : 0] mux_src1_data_i [3 : 0];
      assign mux_src1_data_i[0] = src1_data[gj];
      assign mux_src1_data_i[1] = src1_data[gj];
      assign mux_src1_data_i[2] = spec_d;
      assign mux_src1_data_i[3] = tids[gj];
      
      mux_generic #(.INPUT_WIDTH(R_DATA_WIDTH),
                    .NUM_INPUTS(4)) mux_scr1_data(.in(mux_src1_data_i),
                                                  .sel(mux_src1_data_sel),
                                                  .out(src1_d[gj]));
    end
  endgenerate
    
  assign control_d = control;
  assign rwa_d = rwa;
  assign imm_d = instr_f[IMM_WIDTH - 1 : 0];
  assign src1_o = instr_f[SRC_WIDTH*3 + FUNC_WIDTH - 1 : SRC_WIDTH*2 + FUNC_WIDTH];
  
endmodule
