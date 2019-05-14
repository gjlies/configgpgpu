//************************
// gjlies 04-14-19 Created
// gjlies 04-14-19 Removed inputs / outputs that were just being piped
//************************
//Description:
//The execute stage of the multiprocessor pipeline, generated per SP.
`include "../alu/multiplier.sv"
`include "../alu/shift.sv"
`include "../alu/adder.sv"
`include "../alu/logical.sv"
`include "../alu/compare.sv"
`include "../misc/mux_generic.sv"
module execute (src1_d, src2_d, src3_d, control_d, btake, mult_e, shift_e, logical_e, add_e, compare_e);

  parameter R_DATA_WIDTH = 32;                                // Size of data per register file entry
  parameter CONTROL_WIDTH = 21;                               // Bits of control signals
  parameter SP_PER_MP = 8;                                    // Number of SPs per MP
  parameter IMM_WIDTH = 16;                                   // Number of immediate bits
  
  input [R_DATA_WIDTH - 1 : 0] src1_d;                        // Source 1 from decode
  input [R_DATA_WIDTH - 1 : 0] src2_d;                        // Source 2 from decode
  input [R_DATA_WIDTH - 1 : 0] src3_d;                        // Source 3 from decode
  input [CONTROL_WIDTH - 1 : 0] control_d;                    // Control signals from decode
  
  output btake;                                               // Whether or not to take the branch
  output [R_DATA_WIDTH - 1 : 0] mult_e;                       // Multiplier output
  output [R_DATA_WIDTH - 1 : 0] shift_e;                      // Shift output
  output [R_DATA_WIDTH - 1 : 0] logical_e;                    // Logical output
  output [R_DATA_WIDTH - 1 : 0] add_e;                        // Adder output
  output [R_DATA_WIDTH - 1 : 0] compare_e;                    // Compare output
  
  wire [R_DATA_WIDTH - 1 : 0] mult_out;                       // output of multiplier
  wire [R_DATA_WIDTH - 1 : 0] shift_out;                      // output of shifter
  wire [R_DATA_WIDTH - 1 : 0] logical_out;                    // output of logical unit
  wire [R_DATA_WIDTH - 1 : 0] add_out;                        // output of adder
  wire [R_DATA_WIDTH - 1 : 0] compare_out;                    // output of compare unit
  wire [R_DATA_WIDTH - 1 : 0] src2_add;                       // Src2 input to adder

  //Instantiate Multiplier
  multiplier #(.SRC_WIDTH(R_DATA_WIDTH),
               .OUT_WIDTH(R_DATA_WIDTH)) mult(.src1(src2_d),
                                              .src2(src3_d),
                                              .out(mult_out));
  
  //Instantiate shift unit
  shift #(.SRC_WIDTH(R_DATA_WIDTH),
          .CONTROL_WIDTH(CONTROL_WIDTH),
          .OUT_WIDTH(R_DATA_WIDTH)) shifter(.src1(src1_d),
                                            .src2(src2_d),
                                            .control(control_d),
                                            .out(shift_out));
  
  //Instantiate logical unit
  logical #(.SRC_WIDTH(R_DATA_WIDTH),
            .OUT_WIDTH(R_DATA_WIDTH),
            .CONTROL_WIDTH(CONTROL_WIDTH)) logic_unit(.src1(src1_d),
                                                      .src2(src2_d),
                                                      .control(control_d),
                                                      .out(logical_out));
  
  //Instantiate branch unit
  branch #(.SRC_WIDTH(R_DATA_WIDTH),
           .CONTROL_WIDTH(CONTROL_WIDTH)) branch_unit(.src1(src1_d),
                                                      .control(control_d),
                                                      .take(btake));
  
  //Instantiate adder
  adder #(.SRC_WIDTH(R_DATA_WIDTH),
          .OUT_WIDTH(R_DATA_WIDTH)) add_unit(.src1(src1_d),
                                             .src2(src2_add),
                                             .cin(control_d[2]),
                                             .out(add_out));
  
  //Instantiate compare unit
  compare #(.SRC_WIDTH(R_DATA_WIDTH),
            .OUT_WIDTH(R_DATA_WIDTH),
            .CONTROL_WIDTH(CONTROL_WIDTH)) compare_unit(.src1(add_out),
                                                        .control(control_d),
                                                        .out(compare_out));
  
  //MUXES
  
  //Mux for adder input
  wire [R_DATA_WIDTH - 1 : 0] mux_add_i [3 : 0];
  
  assign mux_add_i[0] = mult_out;
  assign mux_add_i[1] = src2_d;
  assign mux_add_i[2] = logical_out;
  assign mux_add_i[3] = logical_out;
  
  mux_generic #(.INPUT_WIDTH(R_DATA_WIDTH),
                .NUM_INPUTS(4)) mux_add(.in(mux_add_i),
                                        .sel(control_d[2:1]),
                                        .out(src2_add));
                                        
  //Output assignments
  assign mult_e = mult_out;
  assign shift_e = shift_out;
  assign logical_e = logical_out;
  assign add_e = add_out;
  assign compare_e = compare_out;
  
endmodule
