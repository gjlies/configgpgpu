//************************
// gjlies 04-01-19 created
// gjlies 04-08-19 updated to match new ISA
//************************
//Description:
//Determines whether or not to take a branch depending on
//branch type (bne or beq) and src1 input.  Compares src1 to zero.
module branch (src1, control, take);

  parameter SRC_WIDTH = 32;                                  // Size of input
  parameter CONTROL_WIDTH = 11;                              // Number of control bits
  
  input [SRC_WIDTH - 1 : 0] src1;                            // Input to compare to 0
  input [CONTROL_WIDTH - 1 : 0] control;                     // Control bits, bne is index 7, branch is index 8
  output take;
  reg take;
  
  reg equal;
  
  wire bne;
  wire beq;
  
  //check if src1 is equal to 0
  always @ (src1) begin
    if (src1 == 0) begin
      equal <= 1;
    end
    else begin
      equal <= 0;
    end
  end
  
  assign bne = control[8] & ~equal;
  assign beq = control[8] & equal;
  
  //2:1 mux to assign output
  always @ (control[7] or bne or beq) begin
    case(control[7])
      0: take <= beq;
      1: take <= bne;
    endcase
  end
  
endmodule
