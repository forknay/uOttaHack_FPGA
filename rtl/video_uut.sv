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

// Screen parameters
localparam [11:0] CENTER_X = 960;      // Center of screen
localparam [11:0] CENTER_Y = 540;      // Center of screen
localparam [11:0] SCREEN_WIDTH = 1920;
localparam [11:0] SCREEN_HEIGHT = 1080;

// Torus parameters (R = major radius, r = minor radius)
localparam [15:0] TORUS_R = 200;       // Major radius (distance from center to tube center)
localparam [15:0] TORUS_r = 80;        // Minor radius (tube radius)

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

// Rotation angles (A and B control the rotation like in the C code)
reg [15:0] angle_A;   // X-axis rotation
reg [15:0] angle_B;   // Z-axis rotation

// 3D projection variables
reg signed [31:0] x3d, y3d, z3d;        // 3D coordinates before rotation
reg signed [31:0] x_rot, y_rot, z_rot;  // 3D coordinates after rotation
reg signed [31:0] D;                    // Depth/perspective term
reg signed [15:0] x_proj, y_proj;       // 2D projected coordinates
reg [23:0] shading_val;                 // Shading/brightness



always @(posedge clk_i) begin
    // ALL OF OUR CALCULATIONS PER PIXEL
    
    if(cen_i) begin
       Hcount <= (h_f)? (0) : (Hcount + 1);
       if(v_r && h_r) begin
            Vcount <= 0;
            // Increment rotation angles each frame
            angle_A <= angle_A + 655;  // ~0.01 radians in fixed point (65536 = 2π)
            angle_B <= angle_B + 328;  // ~0.005 radians in fixed point
        end else if(h_r) begin
            Vcount <= Vcount + 1;
        end
        h_d <= vh_blank_i[0];
        v_d <= vh_blank_i[1];
    end
    
end

// Combinational logic for 3D torus rendering
always @(*) begin
    // Calculate distance from center in 2D screen space
    reg signed [31:0] dx, dy;
    reg signed [31:0] dist_sq;
    reg signed [15:0] sin_A, cos_A, sin_B, cos_B;
    reg signed [31:0] temp1, temp2;
    
    dx = Hcount - CENTER_X;
    dy = Vcount - CENTER_Y;
    dist_sq = (dx * dx) + (dy * dy);
    
    // Simplified sine/cosine using angle_A and angle_B
    // Using table-based approximation for FPGA efficiency
    sin_A = ((angle_A >> 8) & 255) < 128 ? 
            (((angle_A >> 8) & 255) - 64) << 7 : 
            ((192 - ((angle_A >> 8) & 255)) << 7);
    cos_A = ((angle_A >> 9) & 255) < 128 ? 
            (((angle_A >> 9) & 255) - 64) << 7 : 
            ((192 - ((angle_A >> 9) & 255)) << 7);
    sin_B = ((angle_B >> 8) & 255) < 128 ? 
            (((angle_B >> 8) & 255) - 64) << 7 : 
            ((192 - ((angle_B >> 8) & 255)) << 7);
    cos_B = ((angle_B >> 9) & 255) < 128 ? 
            (((angle_B >> 9) & 255) - 64) << 7 : 
            ((192 - ((angle_B >> 9) & 255)) << 7);
    
    // Calculate 3D coordinates with rotation
    // Using approximation: check if point is on torus ring at current angle
    temp1 = TORUS_R + (TORUS_r >> 1);  // Approximate major radius with minor
    
    // If distance is within reasonable range of torus, shade it
    if ((dist_sq > ((TORUS_R - TORUS_r - 100) * (TORUS_R - TORUS_r - 100))) &&
        (dist_sq < ((TORUS_R + TORUS_r + 100) * (TORUS_R + TORUS_r + 100)))) begin
        
        // Shading based on angle and rotation
        shading_val = ((angle_A + angle_B + Hcount + Vcount) >> 12) & 8'hFF;
        
        if (shading_val < 64) begin
            vid_rgb_d1 <= 24'hFFFFFF;  // White
        end else if (shading_val < 128) begin
            vid_rgb_d1 <= 24'hFF_FF_88;  // Light
        end else if (shading_val < 192) begin
            vid_rgb_d1 <= 24'hFF_5A_43;  // Orange
        end else begin
            vid_rgb_d1 <= (vid_sel_i)? 24'hFF_5A_43 : vid_rgb_i;  // Background
        end
    end else begin
        vid_rgb_d1 <= (vid_sel_i)? 24'hFF_5A_43 : vid_rgb_i;  // Background
    end
    
    dvh_sync_d1 <= dvh_sync_i;
end

// OUTPUT
assign dvh_sync_o  = dvh_sync_d1;
assign vid_rgb_o   = vid_rgb_d1;

endmodule

