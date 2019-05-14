//************************
// gjlies 04-20-19 Created
// gjlies 04-26-19 Added WARP instruction
// gjlies 04-26-19 Added REG instruction
//************************
//Description:
//Decodes kernel instruction and outputs control signals
module gs_decode (instr_k, control_k);

  parameter K_OP_WIDTH = 4;                                   // Number of bits of opcode
  parameter K_CONTROL_WIDTH = 9;                              // Number of control bits
  
  input [K_OP_WIDTH - 1 : 0] instr_k;                         // Kernel instruction
  
  output [K_CONTROL_WIDTH - 1 : 0] control_k;                 // Control signals
  reg [K_CONTROL_WIDTH - 1 : 0] control_k;
  
  always @ (instr_k) begin
    case (instr_k)
      0: control_k  <= 0_0000_0001;          //GRID SIZE
      1: control_k  <= 0_0000_0010;          //BLOCK SIZE
      2: control_k  <= 0_0000_0100;          //PARAM
      3: control_k  <= 0_0000_1000;          //INSTR
      4: control_k  <= 0_0001_0000;          //CONST
      5: control_k  <= 0_0010_0000;          //DATA
	  6: control_k  <= 0_0100_0000;          //WARP
	  7: control_k  <= 0_1000_0000;          //REG
      15: control_k <= 1_0000_0000;          //START
      default: control_k <= 0;
    endcase
  end
  
endmodule
