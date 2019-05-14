//************************
// gjlies 04-10-19 created
// gjlies 04-11-19 Finished
// gjlies 04-20-19 Added lds control signal
//************************
//Description:
//Decodes instructions and outputs appropriate control signals
module decode_unit (op, func, control);

  parameter OP_WIDTH = 6;                                        // Size of opcode
  parameter FUNC_WIDTH = 6;                                      // Size of function
  parameter CONTROL_WIDTH = 21;                                  // Number of control bits

  input [OP_WIDTH - 1 : 0] op;                                   // opcode
  input [FUNC_WIDTH - 1 : 0] func;                               // function code
  output [CONTROL_WIDTH - 1 : 0] control;                        // control signals

  reg [CONTROL_WIDTH - 1 : 0] control;

  //Set control signals
  always @ (op or func) begin
    //if opcode = 0, check function code
    if(op == 0) begin
      case(func)
        0: control <= 0;                                           //NOP
        1: control <= 'b0_0000_0000_0010_0000_0001;                //MAD
        2: control <= 'b0_0000_0000_0000_0000_0001;                //MUL
        3: control <= 'b0_0000_0000_0010_0000_0011;                //ADD
        4: control <= 'b0_0000_0000_0010_0000_0101;                //SUB
        5: control <= 'b0_0000_0010_0000_0000_1101;                //SLT
        6: control <= 'b0_0000_0010_0000_0000_0101;                //SGT
        7: control <= 'b0_0000_0000_0100_0001_0001;                //SHR
        8: control <= 'b0_0000_0000_0100_0000_0001;                //SHL
        9: control <= 'b0_0000_0000_0110_0000_0001;                //NOT
       10: control <= 'b0_0000_0000_0110_0010_0001;                //AND
       11: control <= 'b0_0000_0000_0110_0100_0001;                //OR
       12: control <= 'b0_0000_0000_0110_0110_0001;                //XOR
        default: control <= 0;
      endcase
    end
    else begin
      case(op)
        1: control <= 'b0_0000_0100_0000_0000_0001;                //MV
        2: control <= 'b0_0000_0101_0000_0000_0001;                //MVI
        3: control <= 'b0_0000_1110_0000_0000_0001;                //LD
        4: control <= 'b0_0000_0110_1000_0000_0001;                //LDC
        5: control <= 'b1_0000_0100_0000_0000_0001;                //LDS
        6: control <= 'b0_0000_0000_0001_0000_0000;                //BEQ
        7: control <= 'b0_0000_0000_0001_1000_0000;                //BNE
        8: control <= 'b0_0001_0000_0000_0000_0000;                //ST
        61: control <= 'b0_0100_0000_0000_0000_0000;               //SSY
        62: control <= 'b0_0010_0000_0000_0000_0000;               //BAR
        63: control <= 'b0_1000_0000_0000_0000_0000;               //EXIT
        default: control <= 0;
      endcase
    end
  end
  
endmodule
