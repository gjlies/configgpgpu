//************************
// gjlies 04-14-19 Created
// gjlies 04-18-19 Removed bank number address bits from address input to the bank
//************************
//Description:
//This unit combines the ldst units to create a complete bank
`include "../bram/bram_1_1.sv"
`include "../misc/mux_generic.sv"
module ldst_bank (clk, addrs, datas, cur_mask, bank_num, control, lwe_gs, addr_gs, ldata_gs, bank_data, next_mask, new_mask, contention);

  parameter DATA_WIDTH = 32;                                // L1 data width
  parameter ADDR_WIDTH = 10;                                // L1 address width in bits
  parameter SP_PER_MP = 8;                                  // Number of SPs per MP
  parameter BANK_WIDTH = $clog2(SP_PER_MP);                 // Number of bits to represent a bank
  parameter CONTROL_WIDTH = 17;                             // Number of control bits.
  parameter SYNTHESIS = 0;                                  // Set to 1 when synthesizing, 0 for simulation
  
  input clk;                                                // Clock
  input [ADDR_WIDTH - 1 : 0] addrs [SP_PER_MP - 1 : 0];     // Addresses from each SP
  input [DATA_WIDTH - 1 : 0] datas [SP_PER_MP - 1 : 0];     // Store data from each SP
  input [SP_PER_MP - 1 : 0] cur_mask;                       // current mask for enabled threads
  input [BANK_WIDTH - 1 : 0] bank_num;                      // number of current bank
  input [CONTROL_WIDTH - 1 : 0] control;                    // control bits ld and st are indexes 15 and 16
  input lwe_gs;                                             // L1 write enable from global scheduler
  input [ADDR_WIDTH - 1 : 0] addr_gs;                       // L1 write addr from global scheduler
  input [DATA_WIDTH - 1 : 0] ldata_gs;                      // L1 write data from global scheduler
  
  output [DATA_WIDTH - 1 : 0] bank_data;                    // Read data from L1 bank
  output [SP_PER_MP - 1 : 0] next_mask;                     // Next mask if contentions
  output [SP_PER_MP - 1 : 0] new_mask;                      // New mask if contentions
  output contention;                                        // Contention on bank
  
  //Generate the bank values for each address
  wire [BANK_WIDTH - 1 : 0] banks [SP_PER_MP - 1 : 0];
  wire [ADDR_WIDTH - BANK_WIDTH - 1 : 0] l1_addrs [SP_PER_MP - 1 : 0];
  
  genvar gi;
  generate
    for(gi = 0; gi < SP_PER_MP; gi = gi + 1) begin : bank_addr_gi
      wire [ADDR_WIDTH - 1 : 0] addr;
      assign addr = addrs[gi];
      assign l1_addrs[gi] = addr[ADDR_WIDTH - 1 : BANK_WIDTH];
      assign banks[gi] = addr[BANK_WIDTH - 1 : 0];
    end
  endgenerate
  
  //Instantiate the ldst_setup unit
  wire [SP_PER_MP - 1 : 0] match;
  wire [BANK_WIDTH - 1 : 0] addr_sel;
  
  ldst_setup #(.SP_PER_MP(SP_PER_MP),
               .CONTROL_WIDTH(CONTROL_WIDTH)) ldst_addr_setup(.banks(banks),
                                                              .cur_mask(cur_mask),
                                                              .bank_num(bank_num),
                                                              .control(control),
                                                              .match(match),
                                                              .addr_sel(addr_sel));
  
  //Mux for selecting the addresses
  wire [ADDR_WIDTH - BANK_WIDTH - 1 : 0] addr_selected;
  
  mux_generic #(.INPUT_WIDTH(ADDR_WIDTH - BANK_WIDTH),
                .NUM_INPUTS(SP_PER_MP)) mux_addr_sel(.in(l1_addrs),
                                                     .sel(addr_sel),
                                                     .out(addr_selected));
  
  //Mux for selecting the data to store
  wire [DATA_WIDTH - 1 : 0] data_selected;
  mux_generic #(.INPUT_WIDTH(DATA_WIDTH),
                .NUM_INPUTS(SP_PER_MP)) mux_data_sel(.in(datas),
                                                     .sel(addr_sel),
                                                     .out(data_selected));
                                                     
  //Setup writes to L1 for global scheduler
  //Mux to select addr_selected or addr_gs
  wire [ADDR_WIDTH - BANK_WIDTH - 1 : 0] lwa;
  generate
    if(SYNTHESIS == 0) begin : lwa_gen
      wire [ADDR_WIDTH - BANK_WIDTH - 1 : 0] mux_l1_addr_i [1 : 0];
      wire [ADDR_WIDTH - BANK_WIDTH - 1 : 0] l1_addr_gs;
      assign l1_addr_gs = addr_gs[ADDR_WIDTH - 1 : BANK_WIDTH];
      assign mux_l1_addr_i[0] = addr_selected;
      assign mux_l1_addr_i[1] = l1_addr_gs;
  
      mux_generic #(.INPUT_WIDTH(ADDR_WIDTH - BANK_WIDTH),
                    .NUM_INPUTS(2)) mux_l1_addr(.in(mux_l1_addr_i),
                                                .sel(lwe_gs),
                                                .out(lwa));
    end
    else begin : lwa_gen
      assign lwa = addr_selected;
    end
  endgenerate
  
  //L1 write enable 1 whenever global scheduler or store instruction
  wire lwe;
  generate
    if(SYNTHESIS == 0) begin : lwe_gen
      assign lwe = control[16] | (lwe_gs & (addr_gs[BANK_WIDTH - 1 : 0] == bank_num));
    end
    else begin : lwe_gen
      assign lwe = control[16];
    end
  endgenerate
  
  //Mux to select SP data or global scheduler data
  wire [DATA_WIDTH - 1 : 0] ldata;
  generate
    if(SYNTHESIS == 0) begin : ldata_gen
      wire [DATA_WIDTH - 1 : 0] mux_l1_data_i [1 : 0];
      assign mux_l1_data_i[0] = data_selected;
      assign mux_l1_data_i[1] = ldata_gs;
      
      mux_generic #(.INPUT_WIDTH(DATA_WIDTH),
                    .NUM_INPUTS(2)) mux_l1_data(.in(mux_l1_data_i),
                                                .sel(lwe_gs),
                                                .out(ldata));
    end
    else begin : ldata_gen
      assign ldata = data_selected;
    end
  endgenerate
  
  //Instantiate the L1 bank
  bram_1_1 #(.DATA_WIDTH(DATA_WIDTH),
             .ADDR_WIDTH(ADDR_WIDTH - BANK_WIDTH)) l1_bank(.clk(clk),
                                                           .ra(addr_selected),
                                                           .wa(lwa),
                                                           .we(lwe),
                                                           .di(ldata),
                                                           .dout(bank_data));
  
  //Instantiate ldst evaluation unit
  ldst_eval #(.SP_PER_MP(SP_PER_MP),
              .L1_ADDR_WIDTH(ADDR_WIDTH)) ldst_evaluation(.addrs(l1_addrs),
                                                          .selected(addr_selected),
                                                          .match(match),
                                                          .cur_mask(cur_mask),
                                                          .new_mask(new_mask),
                                                          .next_mask(next_mask),
                                                          .contention(contention));
endmodule
