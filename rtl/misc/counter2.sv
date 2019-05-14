//************************
// gjlies 04-16-19 Created
//************************
//Description:
//A generic up / down counter, this counter is reset to 1 not 0
module counter2 (clk, rst, en, up, count);

  parameter COUNT_WIDTH = 5;                                       // Number of bits for counter
  
  input clk;                                                       // Clock
  input rst;                                                       // Reset
  input en;                                                        // Clock enable
  input up;                                                        // Counts up 1 when, down when 0
  
  output [COUNT_WIDTH - 1 : 0] count;                              // Current Count
  reg [COUNT_WIDTH - 1 : 0] count;                                 // Current count
  
  //Update count
  always @ (posedge clk or negedge rst) begin
    if(rst == 0) begin
      count <= 1;
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
