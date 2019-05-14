//************************
// gjlies 04-10-19 Created
//************************
//Description:
//A generic Multiplexer
module mux_generic (in, sel, out);

  parameter INPUT_WIDTH = 32;                               // Size of input
  parameter NUM_INPUTS = 32;                                // Number of inputs
  parameter SEL_WIDTH = $clog2(NUM_INPUTS);                 // Bits of Selector

  input [INPUT_WIDTH - 1 : 0] in [NUM_INPUTS - 1 : 0];      // Inputs to choose from
  input [SEL_WIDTH - 1 : 0] sel;                            // selector
  output [INPUT_WIDTH - 1 : 0] out;                         // output chosen

  //Written similar to blockram.
  assign out = in[sel];
  
endmodule
