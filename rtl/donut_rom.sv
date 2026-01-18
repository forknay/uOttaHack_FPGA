module donut_rom (
    input  wire         clk_i           ,// clock
    input  wire         cen_i           ,// clock enable
    input  wire [31:0]   addr_rd       ,//
    //input wire [31:0]    addr_wr       ,// 
    //input wire [3:0] data_i,
    output wire [3:0]  data_o        // 
); 

reg [3:0] rom [0:70399]; // 400x176 = 70,400 x 4-bit ROM
reg [3:0] data;
initial begin
    $readmemh("donut_data.mem", rom);
end
always @(posedge clk_i) begin
    if (cen_i) begin
        data <= rom[addr_rd];
    end
end

assign data_o = data;

endmodule