//************************
// gjlies 04-08-19 Created
// gjlies 04-10-19 Code for setup and eval were switched, replaced them.
// gjlies 04-10-19 Fixed declaration of addrs.
// gjlies 04-30-19 Changed next mask assignment to use a generate loop
//************************
//Description:
//This unit is shared among SPs, and unique per bank.  This unit checks for read and write
//conflicts between threads, and outputs a new mask and stack mask to handle them
module ldst_eval (addrs, selected, match, cur_mask, new_mask, next_mask, contention);

  parameter SP_PER_MP = 8;                                               // Number of SPs per MP
  parameter L1_ADDR_WIDTH = 10;                                          // Number of address bits in L1
  parameter BANK_WIDTH = $clog2(SP_PER_MP);                              // Number of bits to represent a bank
  
  input [L1_ADDR_WIDTH - BANK_WIDTH - 1 : 0] addrs [SP_PER_MP - 1 : 0];  // Read/Write Addresses from SPs
  input [L1_ADDR_WIDTH - BANK_WIDTH - 1 : 0] selected;                   // Selected address to use
  input [SP_PER_MP - 1 : 0] match;                                     // Whether or not SP needs this bank
  input [SP_PER_MP - 1 : 0] cur_mask;                                    // Current thread mask
  output [SP_PER_MP - 1 : 0] new_mask;                                   // Update current mask if contentions
  output [SP_PER_MP - 1 : 0] next_mask;                                  // Next mask to take if contentions
  output contention;                                                     // Whether or not this is contention
  
  reg [SP_PER_MP - 1 : 0] next_mask;
  reg contention;
  
  //If SP needs the bank, check the addr.
  //If there is a mismatch update next mask
  //so it can execute next time.
  genvar gi;
  generate
    for(gi = 0; gi < SP_PER_MP; gi = gi + 1) begin : next_mask_gi
      always @ (addrs[gi] or match[gi] or selected) begin
        if((match[gi] == 1) & (addrs[gi] != selected)) begin
          next_mask[gi] <= 1'b1;
        end
        else begin
          next_mask[gi] <= 1'b0;
        end
      end
    end
  endgenerate

  //new_mask will replace cur_mask on contention
  //mask away threads which can't get their data.
  assign new_mask = cur_mask & ~(next_mask);
  
  //check for contentions.  If next_mask is 0, no contention.
  always @ (next_mask) begin
    if(next_mask == 0) begin
      contention <= 0;
    end
    else begin
      contention <= 1;
    end
  end
  
endmodule


