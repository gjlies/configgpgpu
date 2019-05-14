//************************
// gjlies 04-03-19 created
//************************
//Description:
//Implements an adder
module adder (src1, src2, cin, out);

  parameter SRC_WIDTH = 32;                                 // Size of input
  parameter OUT_WIDTH = 32;                                 // Size of output
  
  input [SRC_WIDTH - 1 : 0] src1;                           // inputs to adder
  input [SRC_WIDTH - 1 : 0] src2;                     
  input cin;                                                // carry in to adder for subtraction
  output [OUT_WIDTH - 1 : 0] out;                           // output
  
  // add sub for 2's comp
  assign out = src1 + src2 + cin;
  
endmodule
