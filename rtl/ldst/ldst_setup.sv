//************************
// gjlies 04-09-19 Created
// gjlies 04-10-19 Code for setup and eval were switched, replaced them.
// gjlies 04-10-19 Added matches output to be forwarded to ldst_eval.
// gjlies 04-14-19 Changed indexing for banks
// gjlies 04-30-19 Changed is_match assignment to use a generate loop
//************************
//Description:
//This unit is specific to each bank.  Determines which addr should
//be selected by the L1 Banks by checking which bank each SP is loading/storing
`include "../misc/priority_encoder.sv"
module ldst_setup (banks, cur_mask, bank_num, control, match, addr_sel);

  parameter SP_PER_MP = 8;                                  // Number of SPs per MP
  parameter BANK_WIDTH = $clog2(SP_PER_MP);                 // Number of bits to represent a bank
  parameter CONTROL_WIDTH = 17;                             // Number of control bits.
  
  input [BANK_WIDTH - 1 : 0] banks [SP_PER_MP - 1 : 0];     // bank selection for each SP, lower value is lower thread ID.
  input [SP_PER_MP - 1 : 0] cur_mask;                       // current mask for enabled threads
  input [BANK_WIDTH - 1 : 0] bank_num;                      // number of current bank
  input [CONTROL_WIDTH - 1 : 0] control;                    // control bits ld and st are indexes 15 and 16
  output [SP_PER_MP - 1 : 0] match;                         // whether or not the SP matches the bank.
  output [BANK_WIDTH - 1 : 0] addr_sel;                     // selector to choose addr for this bank.
  
  //input to priority encoder, checks each SP bank
  //for a match with this bank_num
  reg [SP_PER_MP - 1 : 0] is_match;
  
  //Compare each SP's bank addr with this bank_num
  //if it matches, this SP is enabled, and this is a ld or st instruction,
  //then set the match bit to 1, otherwise 0.
  genvar gi;
  generate
    for(gi = 0; gi < SP_PER_MP; gi = gi + 1) begin : match_gi
      always @ (banks[gi] or cur_mask[gi] or bank_num or control[15] or control[16]) begin
        if(banks[gi] == bank_num) begin
          is_match[gi] <= cur_mask[gi] & (control[15] | control[16]);
        end
        else begin
          is_match[gi] <= 1'b0;
        end
      end
    end
  endgenerate

  //Instantiate the priority encoder using the matches
  //as inputs, the output is the addr_sel.
  priority_encoder #(.INPUT_WIDTH(SP_PER_MP)) pri_enc(match, addr_sel);

  //Output the matches for the evaluation unit.
  assign match = is_match;

endmodule
