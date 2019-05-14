//************************
// gjlies 04-01-19 created
// gjlies 04-03-19 updated control signal, changed mux inputs
//************************
//Description:
//Applies logical operators between operands
//control chooses between NOT, AND, OR, XOR
module logical (src1, src2, control, out);

  parameter SRC_WIDTH = 32;                                  // Size of input
  parameter OUT_WIDTH = 32;                                  // Size of output
  parameter CONTROL_WIDTH = 11;                              // Number of control bits
  
  input [SRC_WIDTH - 1 : 0] src1, src2;                      // inputs
  input [CONTROL_WIDTH - 1 : 0] control;                     // control bits logic at index 6:5
  output [OUT_WIDTH - 1 : 0] out;                            // result
  
  reg [OUT_WIDTH -1 : 0] out;
  
  wire [OUT_WIDTH - 1 : 0] and_out;
  wire [OUT_WIDTH - 1 : 0] or_out;
  wire [OUT_WIDTH - 1 : 0] xor_out;
  wire [OUT_WIDTH - 1 : 0] not_out;
  
  //Perform all operators
  assign and_out = src1 & src2;
  assign or_out = src1 | src2;
  assign xor_out = src1 ^ src2;
  assign not_out = ~src2;
  
  //4:1 mux to select between outputs
  always @ (control[6:5] or and_out or or_out or xor_out or not_out) begin
    case(control[6:5])
    0: out <= not_out;
    1: out <= and_out;
    2: out <= or_out;
    3: out <= xor_out;
    endcase
  end
  
endmodule
