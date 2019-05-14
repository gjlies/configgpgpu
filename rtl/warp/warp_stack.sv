//************************
// gjlies 04-16-19 created
// gjlies 04-19-19 Changed stack mask to come from pipeline as single signal
//************************
//Description:
//All stack information needed for diverging cases.  Instantiated per warp
`include "../bram/bram_1_1.sv"
`include "../misc/counter.sv"
`include "../misc/counter2.sv"
`include "../misc/mux_generic.sv"
module warp_stack (clk, rst, wup, contention, control, diverge, cur_pc, cur_pc_p1, ssy_en, ssy_pc_i, cur_mask,
                   stack_mask_i, pc_o, smask_o, mask_update, converge, pc_update);

  parameter CONTROL_WIDTH = 20;                            // Number of bits of control signals
  parameter I_ADDR_WIDTH = 10;                             // Number of bits in instruction address
  parameter WARP_WIDTH = 32;                               // Number of threads per warp
  parameter WARP_DEPTH = $clog2(WARP_WIDTH);               // Number of bits to represent thread in warp
  
  input clk;                                               // Clock
  input rst;                                               // Reset
  input wup;                                               // Signal to update the warp
  input contention;                                        // LDST contention in pipeline
  input [CONTROL_WIDTH - 1 : 0] control;                   // Control signals from pipeline
  input diverge;                                           // Threads diverging in pipeline
  input [I_ADDR_WIDTH - 1 : 0] cur_pc;                     // Current PC
  input ssy_en;                                            // Signal from pipeline to push synchronous pc
  input [WARP_WIDTH - 1 : 0] stack_mask_i;                 // Mask to push on stack
  input [I_ADDR_WIDTH - 1 : 0] ssy_pc_i;                   // Synchronous PC to write
  input [I_ADDR_WIDTH - 1 : 0] cur_pc_p1;                  // Current PC + 1 in pipeline
  input [WARP_WIDTH - 1 : 0] cur_mask;                     // Current warp mask
  
  output [I_ADDR_WIDTH - 1 : 0] pc_o;                      // PC of not taken path
  output [WARP_WIDTH - 1 : 0] smask_o;                     // Mask on stack
  output mask_update;                                      // Signal to update warp mask
  output converge;                                         // Signal to converge thread mask
  output pc_update;                                        // Signal to update pc to not taken path
  
  wire increase_pointer;                                   // Signal to increase the stack pointer
  wire decrease_pointer;                                   // Signal to decrease the stack pointer
  wire stack_pointer_en;                                   // Stack pointer enable
  wire [WARP_DEPTH - 1 : 0] stack_pointer;                 // Stack pointer address

  wire [WARP_DEPTH - 1 : 0] stack_pointer_p1;              // Stack pointer address + 1

  wire [1 : 0] stack_state;                                // Current stack state

  wire [WARP_DEPTH - 1 : 0] mux_stack_state_wa_i [1 : 0];  // Input to state wa mux
  wire mux_stack_state_wa_sel;                             // Select to state wa mux
  wire [WARP_DEPTH - 1 : 0] stack_state_wa;                // Write address to state stack

  wire stack_state_en;                                     // Enable to state stack

  wire [1 : 0] mux_stack_state_di_i [3 : 0];               // Mux input for state stack data
  wire [1 : 0] mux_stack_state_di_sel;                     // Mux select for state stack data
  wire [1 : 0] mux_stack_state_di;                         // Selected state data

  wire [I_ADDR_WIDTH - 1 : 0] stack_sync;                  // Stack synchronization point

  wire [WARP_DEPTH - 1 : 0] mux_stack_sync_wa_i [1 : 0];   // Input to mux to select write address for sync stack
  wire mux_stack_sync_wa_sel;                              // Selector to mux to select write address for sync stack
  wire [WARP_DEPTH - 1 : 0] mux_stack_sync_wa;             // Selected write address for sync stack

  wire stack_sync_en;                                      // Enable for writing to stack synchronous point

  wire [I_ADDR_WIDTH - 1 : 0] stack_pc;                    // Stack PC value
  
  wire stack_pc_en;                                        // Enable for writing new stack PC

  wire [WARP_WIDTH - 1 : 0] stack_mask;                    // Stack mask value

  wire [WARP_DEPTH - 1 : 0] mux_stack_mask_wa_i [1 : 0];   // write address for mask stack
  wire mux_stack_mask_wa_sel;                              // Select for choosing mask write address
  wire [WARP_DEPTH - 1 : 0] mux_stack_mask_wa;             // Write address for mask push

  wire stack_mask_we;                                      // Mask stack write enable

  wire [WARP_WIDTH - 1 : 0] mux_stack_mask_di_i [1 : 0];   // Choose mask to push onto stack
  wire [WARP_WIDTH - 1 : 0] mux_stack_mask_di;             // Mask to push onto stack
  wire mux_stack_mask_di_sel;                              // Select for choosing stack mask

  reg sync_match;                                          // Whether or not this PC matches synchronous PC
  reg sync_match_p1;                                       // Whether or not this PC + 1 matches synchronous PC

  wire state_empty;                                        // Stack entry is empty
  wire state_taken;                                        // Stack entry is state taken
  wire state_ntaken;                                       // Stack entry is state not taken
  wire state_ldst;                                         // Stack entry is state ldst

  wire ldst;                                               // LDST instruction in pipeline

  //Instantiate two counters, one to point to stack
  //One at stack pointer + 1 as some writes happen during counter update
  //Increase pointer if setting synchronous point and the current state is not empty, 
  //or if there is ldst contention and the current state is not a ldst issue
  assign increase_pointer = wup & ((ssy_en & ~state_empty) | (contention & ~state_ldst));
  
  //Decrease pointer if the synchronous PC is this PC and the state is 2 (not taken path),
  //or if it is a ldst instruction and there is no contention, but the current state is a ldst issue
  assign decrease_pointer = (sync_match & state_ntaken) | (ldst & ~contention & state_ldst & wup);
  
  //Enable the stack pointer whenever we want to increase or decrease
  assign stack_pointer_en = increase_pointer | decrease_pointer;
  
  counter #(.COUNT_WIDTH(WARP_DEPTH)) stack_point(.clk(clk),
                                                  .rst(rst),
                                                  .en(stack_pointer_en),
                                                  .up(increase_pointer),
                                                  .count(stack_pointer));
  
  //Setup the other counter to be stack pointer + 1
  counter2 #(.COUNT_WIDTH(WARP_DEPTH)) stack_point_p1(.clk(clk),
                                                      .rst(rst),
                                                      .en(stack_pointer_en),
                                                      .up(increase_pointer),
                                                      .count(stack_pointer_p1));
  
  //Instantiate stack for states
  //State write address may be pointer or pointer + 1
  //Mux for selecting write address to state stack
  assign mux_stack_state_wa_i[0] = stack_pointer;
  assign mux_stack_state_wa_i[1] = stack_pointer_p1;
  
  //Select pointer + 1 when there is contention, but the current state is not a ldst issue
  assign mux_stack_state_wa_sel = wup & contention & ~state_ldst;
  
  mux_generic #(.INPUT_WIDTH(WARP_DEPTH),
                .NUM_INPUTS(2)) multiplex_stack_state_wa(.in(mux_stack_state_wa_i),
                                                         .sel(mux_stack_state_wa_sel),
                                                         .out(stack_state_wa));
    
  //Setup stack state write enable
  //Write to state stack if pointer is decreasing, if threads diverging,
  //if sync_pc match and in state taken, or if ldst contention and not in state ldst.
  assign stack_state_en = decrease_pointer | (sync_match & state_taken) | (((contention & ~state_ldst) | diverge) & wup);
  
  //Mux for selecting data input to state stack
  assign mux_stack_state_di_i[0] = 0;
  assign mux_stack_state_di_i[1] = 1;
  assign mux_stack_state_di_i[2] = 2;
  assign mux_stack_state_di_i[3] = 3;
  
  //select 0 if decreasing, 1 if diverging, 2 if sync pc = this pc and at state taken,
  //or if sync pc = PC + 1 and diverging, 3 if ldst contention
  assign mux_stack_state_di_sel[0] = (diverge & ~sync_match_p1 | contention) & wup;
  assign mux_stack_state_di_sel[1] = (sync_match & state_taken) | (((sync_match_p1 & diverge) | (contention)) & wup);
  
  mux_generic #(.INPUT_WIDTH(2),
                .NUM_INPUTS(4)) multiplex_stack_state_di(.in(mux_stack_state_di_i),
                                                         .sel(mux_stack_state_di_sel),
                                                         .out(mux_stack_state_di));
  bram_1_1 #(.DATA_WIDTH(2),
             .ADDR_WIDTH(WARP_DEPTH)) state_stack(.clk(clk),
                                                  .ra(stack_pointer),
                                                  .wa(stack_state_wa),
                                                  .we(stack_state_en),
                                                  .di(mux_stack_state_di),
                                                  .dout(stack_state));
                                                  
  //Instantiate stack for the synchronous PC
  //Mux for selecting write address to sync stack
  assign mux_stack_sync_wa_i[0] = stack_pointer;
  assign mux_stack_sync_wa_i[1] = stack_pointer_p1;
  
  //If current state is not empty, then always write to next entry
  assign mux_stack_sync_wa_sel = ~state_empty;
  
  assign stack_sync_en = ssy_en & wup;
  
  mux_generic #(.INPUT_WIDTH(WARP_DEPTH),
                .NUM_INPUTS(2)) multiplex_stack_sync_wa(.in(mux_stack_sync_wa_i),
                                                        .sel(mux_stack_sync_wa_sel),
                                                        .out(mux_stack_sync_wa));
  bram_1_1 #(.DATA_WIDTH(I_ADDR_WIDTH),
             .ADDR_WIDTH(WARP_DEPTH)) sync_stack(.clk(clk),
                                                 .ra(stack_pointer),
                                                 .wa(mux_stack_sync_wa),
                                                 .we(stack_sync_en),
                                                 .di(ssy_pc_i),
                                                 .dout(stack_sync));
                                                 
  //Instantiate stack for not taken PC
  assign stack_pc_en = diverge & wup;
  
  bram_1_1 #(.DATA_WIDTH(I_ADDR_WIDTH),
             .ADDR_WIDTH(WARP_DEPTH)) pc_stack(.clk(clk),
                                               .ra(stack_pointer),
                                               .wa(stack_pointer),
                                               .we(stack_pc_en),
                                               .di(cur_pc_p1),
                                               .dout(stack_pc));
                                               
  //Instantiate stack for mask
  //Mux to choose write address for the mask stack
  assign mux_stack_mask_wa_i[0] = stack_pointer;
  assign mux_stack_mask_wa_i[1] = stack_pointer_p1;
  
  //Select stack pointer + 1 only when there is contention and we are not in ldst state
  assign mux_stack_mask_wa_sel = wup & contention & ~state_ldst;
  
  mux_generic #(.INPUT_WIDTH(WARP_DEPTH),
                .NUM_INPUTS(2)) multiplex_stack_mask_wa(.in(mux_stack_mask_wa_i),
                                                        .sel(mux_stack_mask_wa_sel),
                                                        .out(mux_stack_mask_wa));
  
  //Write to mask stack whenever diverging, ssy_pc match and state taken,
  //Or if ldtst contention and not state ldst
  assign stack_mask_we = (sync_match & state_taken) | (((contention & ~state_ldst) | diverge) & wup);
  
  //Mux for selecting stack_mask or warp's cur_mask when sync match and state taken
  assign mux_stack_mask_di_i[0] = stack_mask_i;
  assign mux_stack_mask_di_i[1] = cur_mask;
  
  assign mux_stack_mask_di_sel = sync_match & state_taken;
  
  mux_generic #(.INPUT_WIDTH(WARP_WIDTH),
                .NUM_INPUTS(2)) multiplex_stack_mask_di(.in(mux_stack_mask_di_i),
                                                        .sel(mux_stack_mask_di_sel),
                                                        .out(mux_stack_mask_di));
                                                  
  bram_1_1 #(.DATA_WIDTH(WARP_WIDTH),
             .ADDR_WIDTH(WARP_DEPTH)) mask_stack(.clk(clk),
                                                 .ra(stack_pointer),
                                                 .wa(mux_stack_mask_wa),
                                                 .we(stack_mask_we),
                                                 .di(mux_stack_mask_di),
                                                 .dout(stack_mask));
  
  //Compare stack synchronous pc to cur_pc
  always @ (cur_pc or stack_sync) begin
    if(cur_pc == stack_sync) begin
      sync_match <= 1;
    end
    else begin
      sync_match <= 0;
    end
  end
  
  always @ (cur_pc_p1 or stack_sync) begin
    if(cur_pc_p1 == stack_sync) begin
      sync_match_p1 <= 1;
    end
    else begin
      sync_match_p1 <= 0;
    end
  end
  
  //Check for state
  assign state_empty = ~stack_state[1] & ~stack_state[0];
  assign state_taken = ~stack_state[1] & stack_state[0];
  assign state_ntaken = stack_state[1] & ~stack_state[0];
  assign state_ldst = stack_state[1] & stack_state[0];
  
  //Check for ldst instruction
  assign ldst = control[15] | control[16];
  
  //Output signals to let warp know to update mask
  assign mask_update = (sync_match & state_taken) | (state_ldst & ldst & ~contention & wup);
  assign converge = sync_match & state_ntaken;
  assign pc_update = sync_match & state_taken;
  
  assign pc_o = stack_pc;
  assign smask_o = stack_mask;
  
endmodule
