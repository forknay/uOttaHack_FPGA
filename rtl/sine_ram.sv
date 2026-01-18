module sine_ram (
    input  wire         clk_i           ,// clock
    input  wire         cen_i           ,// clock enable
    input  wire [6:0]  addr_rd    ,   
    output wire [7:0]  data_o        // 
); 

reg [7:0] rom [0:32767]; // 32K x 8-bit ROM
reg [7:0] data;
initial begin
    $readmemh("sine.mem", rom);
end
always @(posedge clk_i) begin
    if (cen_i) begin
        data <= rom[addr_rd];
    end
end

assign data_o = data;

endmodule