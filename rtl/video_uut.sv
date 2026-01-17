/****************************************************************************
FILENAME     :  video_uut.sv
PROJECT      :  Hack-a-Thon 2026
****************************************************************************/

/*  INSTANTIATION TEMPLATE  -------------------------------------------------

video_uut video_uut (       
    .clk_i          ( ),//               
    .cen_i          ( ),// video clock enable
    .rst_i          ( ),//
    .vid_sel_i      ( ),//
    .vid_rgb_i      ( ),//[23:0] = R[23:16], G[15:8], B[7:0]
    .vh_blank_i     ( ),//[ 1:0] = {Vblank, Hblank}
    .dvh_sync_i     ( ),//[ 2:0] = {D_sync, Vsync , Hsync }
    // Output signals
    .dvh_sync_o     ( ),//[ 2:0] = {D_sync, Vsync , Hsync }  delayed
    .vid_rgb_o      ( ) //[23:0] = R[23:16], G[15:8], B[7:0] delayed
);

-------------------------------------------------------------------------- */


module video_uut (
    (* mark_debug = "true", keep = "true" *)
    input  wire         clk_i           ,// clock
    (* mark_debug = "true", keep = "true" *)
    input  wire         cen_i           ,// clock enable
    (* mark_debug = "true", keep = "true" *)
    input  wire         rst_i           ,// reset
    (* mark_debug = "true", keep = "true" *)
    input  wire         vid_sel_i       ,// select between video sources
    (* mark_debug = "true", keep = "true" *)
    input  wire [23:0]  vid_rgb_i       ,// [23:0] = R[23:16], G[15:8], B[7:0]
    (* mark_debug = "true", keep = "true" *)
    input  wire [1:0]   vh_blank_i      ,// input  video timing signals
    (* mark_debug = "true", keep = "true" *)
    input  wire [2:0]   dvh_sync_i      ,// HDMI timing signals
    (* mark_debug = "true", keep = "true" *)
    output wire [2:0]   dvh_sync_o      ,// HDMI timing signals delayed
    (* mark_debug = "true", keep = "true" *)
    output wire [23:0]  vid_rgb_o        // [23:0] = R[23:16], G[15:8], B[7:0]
); 
 
localparam [23:0] RGB_COLOUR = 24'hFF_5A_43; // R=128, G=16,  B=128
localparam [23:0] RGB_WHITE = 24'hFF_FF_FF; // R=255, G=255, B=255

// Square dimensions and screen size
localparam [11:0] SQUARE_WIDTH = 320;
localparam [11:0] SQUARE_HEIGHT = 320;
localparam [11:0] SCREEN_WIDTH = 1920;
localparam [11:0] SCREEN_HEIGHT = 1125;

reg [23:0]  vid_rgb_d1;
reg [2:0]   dvh_sync_d1;

// my wires
(* mark_debug = "true", keep = "true" *)
wire h_r = vh_blank_i[0] & ~h_d;  // horizontal blank rising edge
(* mark_debug = "true", keep = "true" *)
wire h_f = ~vh_blank_i[0] & h_d;  // horizontal blank falling edge
(* mark_debug = "true", keep = "true" *)
wire v_r = vh_blank_i[1] & ~v_d;  // vertical blank rising edge
(* mark_debug = "true", keep = "true" *)
wire v_f = ~vh_blank_i[1] & v_d;  // vertical blank falling edge

// my regs
reg h_d;
reg v_d;
reg [11:0] Hcount;
reg [11:0] Vcount;

// Bouncing square position and direction
reg [11:0] sq_x;  // Square X position (left edge)
reg [11:0] sq_y;  // Square Y position (top edge)
reg dir_x;        // X direction: 0=left, 1=right
reg dir_y;        // Y direction: 0=up, 1=down

// RAM interface signals
wire [14:0] addr_rd;
wire [14:0] addr_wr;
wire [3:0] data_i;
wire [3:0] data_o;

// RAM address calculation: row * width + column (120 x 160 image)
assign addr_rd = Vcount * 12'd120 + Hcount;
assign addr_wr = 15'd0;  // Not writing
assign data_i = 4'd0;    // Not writing

donut_ram donut_ram_inst(
    .clk_i (clk_i)           ,// clock
    .cen_i (cen_i)           ,// clock enable
    .addr_rd (addr_rd)       ,// Reading Address
    .addr_wr (addr_wr)       ,// Writing Address
    .data_i (data_i)        ,// Data Input
    .data_o (data_o)        //Data output
); 

always @(posedge clk_i) begin
    // ALL OF OUR CALCULATIONS PER PIXEL
    
    if(cen_i) begin
       //vid_rgb_d1  <= (vid_sel_i)? RGB_COLOUR : vid_rgb_i;
       //dvh_sync_d1 <= dvh_sync_i;
       //my code
       
       Hcount <= (h_f)? (0) : (Hcount + 1);
       if(v_r && h_r) begin
            Vcount <= 0;
            
            // Update square position once per frame
            // Update X position
            if (dir_x) begin  // Moving right
                if (sq_x + SQUARE_WIDTH >= SCREEN_WIDTH - 1)
                    dir_x <= 0;  // Hit right edge, go left
                else
                    sq_x <= sq_x + 5;  // Move right by 5 pixels
            end else begin  // Moving left
                if (sq_x <= 0)
                    dir_x <= 1;  // Hit left edge, go right
                else
                    sq_x <= sq_x - 5;  // Move left by 5 pixels
            end
            
            // Update Y position
            if (dir_y) begin  // Moving down
                if (sq_y + SQUARE_HEIGHT >= SCREEN_HEIGHT - 1)
                    dir_y <= 0;  // Hit bottom edge, go up
                else
                    sq_y <= sq_y + 5;  // Move down by 5 pixels
            end else begin  // Moving up
                if (sq_y <= 42)
                    dir_y <= 1;  // Hit top edge, go down
                else
                    sq_y <= sq_y - 5;  // Move up by 5 pixels
            end
            
        end else if(h_r) begin
            Vcount <= Vcount + 1;
        end
        h_d <= vh_blank_i[0];
        v_d <= vh_blank_i[1];
    
    end
    // Currently still base condition, so will always display "background bars"
    // Basically depending on the Vcount and Hcount, we can decide whether
    // to show the background or our own calculated pixel color
    
    // Draw white bouncing square
    if ((Hcount >= sq_x && Hcount < sq_x + SQUARE_WIDTH) && 
        (Vcount >= sq_y && Vcount < sq_y + SQUARE_HEIGHT)) begin
        vid_rgb_d1 <= RGB_WHITE;
    end else begin
        vid_rgb_d1 <= (vid_sel_i)? RGB_COLOUR : vid_rgb_i;
    end
    
    dvh_sync_d1 <= dvh_sync_i;
    
end

// OUTPUT
assign dvh_sync_o  = dvh_sync_d1;
assign vid_rgb_o   = vid_rgb_d1;

endmodule

