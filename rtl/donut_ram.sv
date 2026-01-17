
module donut_ram (
    input  wire         clk_i           ,// clock
    input  wire         cen_i           ,// clock enable
    input  wire [14:0]        addr_rd       ,//
    input wire [14:0]        addr_wr       ,// 
    input wire [3:0] data_i,
    output wire [3:0]  data_o        // 
); 

reg [3:0] ram [0:32767]; // 32K x 4-bit ROM
reg [3:0] data;
initial begin
    $readmemh("donut_data.mem", ram);
end
always @(posedge clk_i) begin
    if (cen_i) begin
        ram[addr_wr] <= data_i;
        data <= ram[addr_rd];
    end
end