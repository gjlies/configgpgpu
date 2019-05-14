//************************
// gjlies 04-14-19 Created
//************************
//Description:
//This unit instantiates the constant cache and uses the lowest thread id
//which is enabled to provide the read address
`include "../bram/bram_1_1.sv"
`include "../misc/mux_generic.sv"
`include "../misc/priority_encoder.sv"
module ldst_const_cache (clk, addrs, cur_mask, cwe_gs, caddr_gs, cdata_gs, const_data);

  parameter DATA_WIDTH = 32;                                // L1 data width
  parameter ADDR_WIDTH = 10;                                // L1 address width in bits
  parameter SP_PER_MP = 8;                                  // Number of SPs per MP
  parameter SP_DEPTH = $clog2(SP_PER_MP);                   // Number of bits to represent an SP
  
  input clk;                                                // Clock
  input [ADDR_WIDTH - 1 : 0] addrs [SP_PER_MP - 1 : 0];     // Addresses from each SP
  input [SP_PER_MP - 1 : 0] cur_mask;                       // Current warp mask
  input cwe_gs;                                             // Constant write enable from global scheduler
  input [ADDR_WIDTH - 1 : 0] caddr_gs;                      // Constant write addr from global scheduler
  input [DATA_WIDTH - 1 : 0] cdata_gs;                      // Constant write data from global scheduler
  
  output [DATA_WIDTH - 1 : 0] const_data;                   // Read data from constant cache
  
  //Instantiate the priority encoder for picking address
  wire [SP_DEPTH - 1 : 0] sp_sel;
  priority_enconder #(.INPUT_WIDTH(SP_PER_MP)) addr_sel(.in(cur_mask),
                                                        .out(sp_sel));
  
  //Mux for selecting the addresses
  wire [ADDR_WIDTH - 1 : 0] addr_selected;
  
  mux_generic #(.INPUT_WIDTH(ADDR_WIDTH),
                .NUM_INPUTS(SP_PER_MP)) mux_addr_sel(.in(addrs),
                                                     .sel(sp_sel),
                                                     .out(addr_selected));
  
  //Instantiate the L1 bank
  bram_1_1 #(.DATA_WIDTH(DATA_WIDTH),
             .ADDR_WIDTH(ADDR_WIDTH)) const_cache(.clk(clk),
                                                  .ra(addr_selected),
                                                  .wa(caddr_gs),
                                                  .we(cwe_gs),
                                                  .di(cdata_gs),
                                                  .dout(const_data));
endmodule
