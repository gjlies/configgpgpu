//************************
// gjlies 04-01-19 created
// gjlies 04-03-19 updated control, changed to shift by src2 not amount, updated mux
// gjlies 04-10-19 updated shamt parameter to be log2 of src_width.
//************************
//Description:
//shifts src1 by src2 amount. shift left when control[4] = 0, right when 1
module shift (src1, src2, control, out);

  parameter SRC_WIDTH = 32;                                  // Size of input
  parameter SHAMT_WIDTH = $clog2(SRC_WIDTH);                 // Bits of shift amount
  parameter CONTROL_WIDTH = 11;                              // Number of control bits
  parameter OUT_WIDTH = 32;                                  // Size of output
  
  input [SRC_WIDTH - 1 : 0] src1;                            // input to shift
  input [SHAMT_WIDTH - 1 : 0] src2;                          // amount to shift
  input [CONTROL_WIDTH - 1 : 0] control;                     // control signal, shr index 4
  output [OUT_WIDTH - 1 : 0] out;                            // output
  
  reg [OUT_WIDTH - 1 : 0] out;
  
  //hold temporary shift values
  wire [SRC_WIDTH - 1 : 0] shl;
  wire [SRC_WIDTH - 1 : 0] shr;
  
  assign shl = src1 << src2;
  assign shr = src1 >> src2;
  
  //2:1 mux for selecting shifted output
  always @ (control[4] or shl or shr) begin
    case(control[4])
      0: out <= shl;
      1: out <= shr;
    endcase
  end
  
endmodule
