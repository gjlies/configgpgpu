//************************
// gjlies 04-19-19 Created
//************************
//Description:
//Block ram to hold thread Ids, all read constantly
module bram_1 (clk, wa, we, di, dout);

  parameter DATA_WIDTH = 32;                                  // Size of data per entry
  parameter ADDR_WIDTH = 10;                                  // Bits of address
  parameter ADDR_DEPTH = 1 << ADDR_WIDTH;                     // Number of entries
  
  input clk;
  input [ADDR_WIDTH - 1 : 0] wa;
  input we;
  input [DATA_WIDTH - 1 : 0] di;
  output [DATA_WIDTH - 1 : 0] dout [ADDR_DEPTH - 1 : 0];
  
  reg [DATA_WIDTH - 1 : 0] dout [ADDR_DEPTH - 1 : 0];
  
  always @ (posedge clk) begin
    if(we) begin
      dout[wa] <= di;
    end
  end
  
endmodule
