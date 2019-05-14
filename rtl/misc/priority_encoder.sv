//************************
// gjlies 04-08-19 Created
// gjlies 04-10-19 Changed to give LSB priority so lowest thread ID has priority over higher.
//************************
//Description:
//A LSB Priority Encoder
module priority_encoder (in, out);

  parameter INPUT_WIDTH = 32;                               // Size of input
  parameter OUTPUT_WIDTH = $clog2(INPUT_WIDTH);             // Size of output
  
  input [INPUT_WIDTH - 1 : 0] in;                           // input
  output [OUTPUT_WIDTH - 1 : 0] out;                        // output
  reg [OUTPUT_WIDTH - 1: 0] out;
  
  //check MSB down, if bit is 1 set output to i
  //LSB gets priority over MSB
  integer i;
  always @ (in) begin
    out <= 0;
    for (i = INPUT_WIDTH - 1; i >= 0; i = i - 1) begin
      if(in[i] == 1) begin
        out <= i;
      end
    end
  end
  
endmodule
