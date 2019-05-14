//************************
// gjlies 03-29-19 created
// gjlies 04-09-19 flipped data_width and addr_width in ram declaration
//************************
//Description:
//Block ram with 1 read and 1 write port
//Uses: Instruction Cache
module bram_1_1 (clk, ra, wa, we, di, dout);

  parameter DATA_WIDTH = 32;                                  // Size of data per entry
  parameter ADDR_WIDTH = 10;                                  // Bits of address
  parameter ADDR_DEPTH = 1 << ADDR_WIDTH;                     // Number of entries
  
  input clk;
  input [ADDR_WIDTH - 1 : 0] ra;
  input [ADDR_WIDTH - 1 : 0] wa;
  input we;
  input [DATA_WIDTH - 1 : 0] di;
  output [DATA_WIDTH - 1 : 0] dout;
  
  reg [DATA_WIDTH - 1 : 0] ram [ADDR_DEPTH - 1 : 0];
  
  always @ (posedge clk) begin
    if(we) begin
      ram[wa] <= di;
    end
  end
  
  assign dout = ram[ra];
  
endmodule
