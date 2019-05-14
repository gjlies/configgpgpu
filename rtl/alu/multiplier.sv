//************************
// gjlies 04-01-19 created
//************************
//Description:
//Multiplies two sources together
module multiplier (src1, src2, out);

  parameter SRC_WIDTH = 32;                                  // Size of input
  parameter OUT_WIDTH = 32;                                  // Size of output
  
  input [SRC_WIDTH - 1 : 0] src1, src2;
  output [OUT_WIDTH - 1 : 0] out;
  
  assign out = src1 * src2;
  
endmodule