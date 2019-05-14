//************************
// gjlies 04-01-19 created
//************************
//Description:
//Block ram with 3 read and 1 write port
//Uses: Register File
module bram_3_1 (clk, ra1, ra2, ra3, wa, we, di, do1, do2, do3);

  parameter DATA_WIDTH = 32;                                  // Size of data per entry
  parameter ADDR_WIDTH = 10;                                  // Bits of address
  parameter ADDR_DEPTH = 1 << ADDR_WIDTH;                     // Number of entries
  
  input clk;
  input [ADDR_WIDTH - 1 : 0] ra1;
  input [ADDR_WIDTH - 1 : 0] ra2;
  input [ADDR_WIDTH - 1 : 0] ra3;
  input [ADDR_WIDTH - 1 : 0] wa;
  input we;
  input [DATA_WIDTH - 1 : 0] di;

  output [DATA_WIDTH - 1 : 0] do1;
  output [DATA_WIDTH - 1 : 0] do2;
  output [DATA_WIDTH - 1 : 0] do3;  

  reg [DATA_WIDTH - 1 : 0] ram [ADDR_DEPTH - 1 : 0];
  
  always @ (posedge clk) begin
    if(we) begin
      ram[wa] <= di;
    end
  end
  
  assign do1 = ram[ra1];
  assign do2 = ram[ra2];
  assign do3 = ram[ra3];
  
endmodule
