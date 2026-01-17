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

// Screen size
localparam [11:0] SCREEN_WIDTH = 1920;
localparam [11:0] SCREEN_HEIGHT = 1080;

// Donut parameters
localparam [11:0] CENTER_X = 960;      // Center of screen
localparam [11:0] CENTER_Y = 540;      // Center of screen
localparam [11:0] DONUT_OUTER = 300;   // Outer radius
localparam [11:0] DONUT_INNER = 150;   // Inner radius (hole)

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

// Donut rotation counter
reg [15:0] rotation_counter;



always @(posedge clk_i) begin
    // ALL OF OUR CALCULATIONS PER PIXEL
    
    if(cen_i) begin
       //vid_rgb_d1  <= (vid_sel_i)? RGB_COLOUR : vid_rgb_i;
       //dvh_sync_d1 <= dvh_sync_i;
       //my code
       
       Hcount <= (h_f)? (0) : (Hcount + 1);
       if(v_r && h_r) begin
            Vcount <= 0;
            // Increment rotation counter each frame (controls spin speed)
            rotation_counter <= rotation_counter + 1;
        end else if(h_r) begin
            Vcount <= Vcount + 1;
        end
        h_d <= vh_blank_i[0];
        v_d <= vh_blank_i[1];
    
    end
    
    // Calculate distance from center to current pixel
    // Using squared distance to avoid sqrt (saves hardware)
    reg signed [23:0] dx;
    reg signed [23:0] dy;
    reg signed [23:0] dist_sq;
    reg [23:0] dist_sq_abs;
    reg [11:0] radius_sq_outer;
    reg [11:0] radius_sq_inner;
    
    // Distance calculations
    dx = Hcount - CENTER_X;
    dy = Vcount - CENTER_Y;
    dist_sq = (dx * dx) + (dy * dy);
    dist_sq_abs = (dist_sq[23])? (~dist_sq + 1) : dist_sq;  // Absolute value
    
    radius_sq_outer = DONUT_OUTER * DONUT_OUTER;
    radius_sq_inner = DONUT_INNER * DONUT_INNER;
    
    // Draw donut: pixel is white if it's between inner and outer radius
    // The rotation_counter adds a phase shift that creates the spinning effect
    if ((dist_sq_abs <= radius_sq_outer) && (dist_sq_abs >= radius_sq_inner)) begin
        // Add rotation effect by modulating the color based on angle
        // Use rotation_counter to create spinning appearance
        if (((Hcount + Vcount + rotation_counter) % 16) < 8) begin
            vid_rgb_d1 <= RGB_WHITE;
        end else begin
            vid_rgb_d1 <= RGB_COLOUR;
        end
    end else begin
        vid_rgb_d1 <= (vid_sel_i)? RGB_COLOUR : vid_rgb_i;
    end
    
    dvh_sync_d1 <= dvh_sync_i;
    
end

// OUTPUT
assign dvh_sync_o  = dvh_sync_d1;
assign vid_rgb_o   = vid_rgb_d1;

endmodule

