//************************
// gjlies 04-24-19 Created
//************************
//Description:
//A generic up / down counter with synchronous reset
module counter3 (clk, rst, en, up, count);

  parameter COUNT_WIDTH = 5;                                       // Number of bits for counter
  
  input clk;                                                       // Clock
  input rst;                                                       // Reset
  input en;                                                        // Clock enable
  input up;                                                        // Counts up 1 when, down when 0
  
  output [COUNT_WIDTH - 1 : 0] count;                              // Current Count
  reg [COUNT_WIDTH - 1 : 0] count;                                 // Current count
  
  //Update count
  always @ (posedge clk) begin
    if(rst == 0) begin
      count <= 0;
    end
    else if(en == 1) begin
      if(up == 0) begin
        count <= count - 1;
      end
      else begin
        count <= count + 1;
      end
    end
  end
  
endmodule
