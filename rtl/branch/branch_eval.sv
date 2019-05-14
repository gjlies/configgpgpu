//************************
// gjlies 04-08-19 Created
// gjlies 04-10-19 Added diverging output to determine need for stack entry and PC update.
// gjlies 04-14-19 Fixed diverging assignment bug
//************************
//Description:
//This module is shared between all SPs.  Checks whether branches are
//taken / not taken for each SP and updates the new mask for the next instruction
//as well as the stack mask.
module branch_eval (taken, cur_mask, next_mask, stack_mask, diverging);

  parameter SP_PER_MP = 8;                                  // Number of SPs per MP
  
  input [SP_PER_MP - 1 : 0] taken;                          // branch taken/not taken for each SP
  input [SP_PER_MP - 1 : 0] cur_mask;                       // current mask for each SP
  output [SP_PER_MP - 1 : 0] next_mask;                     // new mask after branch
  output [SP_PER_MP - 1 : 0] stack_mask;                    // stack mask for diverging threads
  output [1 : 0] diverging;                                 // Describes how threads are diverging

  reg all_taken;
  reg none_taken;
  
  //new mask will be the threads which take the branch
  //and are currently enabled
  assign next_mask = cur_mask & taken;
  
  //Stack mask will be the threads which did not
  //take the branch and are currently enabled
  assign stack_mask = cur_mask & ~taken;

  //Check if all the thread are taken or not taken.
  always @ (taken) begin

    if(taken == 0) begin
      none_taken <= 1;
    end
    else begin
      none_taken <= 0;
    end

    if(~taken == 0) begin
      all_taken <= 1;
    end
    else begin
      all_taken <= 0;
    end

  end

  //diverging is 0 if diverging, 1 if all not taken, 2 if all taken.
  assign diverging = {all_taken, none_taken};

endmodule
