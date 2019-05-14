//************************
// gjlies 04-03-19 created
// gjlies 04-10-19 Fixed equal signal
//************************
//Description:
//Compares result of adder to check for less than
//or greater than.
module compare (src1, control, out);

  parameter SRC_WIDTH = 32;                                 // Size of input
  parameter OUT_WIDTH = 32;                                 // Size of output
  parameter CONTROL_WIDTH = 11;                             // Number of control bits
  
  input [SRC_WIDTH - 1 : 0] src1;                           // result to check
  input [CONTROL_WIDTH - 1 : 0] control;                    // controls, slt at bit index 3
  output [OUT_WIDTH - 1 : 0] out;                           // output
  
  reg compare;                                              // evaluation of comparison
  reg equal;                                                // 1 if result is equal (0)
  
  wire choice1;
  wire choice2;
  
  //Check if src1 is equal to 0
  always @ (src1) begin
    if (src1 == 0) begin
      equal <= 1;
    end
    else begin
      equal <= 0;
    end
  end
  
  //output choice1 when not set less than.  choice1 is greater than if not less than & not equal
  assign choice1 = ~src1[SRC_WIDTH - 1] & ~equal;
  //output choice2 when set less than (slt) which is MSB of result (sign bit)
  assign choice2 = src1[SRC_WIDTH - 1];
  
  //evaluate the comparison 2:1 mux
  always @ (control[3] or choice1 or choice2) begin
    case(control[3])
    0: compare <= choice1;
    1: compare <= choice2;
    endcase
  end
    
  //output is compare result extended with 0s.
  assign out = {0,compare};
  
endmodule
