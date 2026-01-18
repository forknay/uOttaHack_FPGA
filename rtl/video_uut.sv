/****************************************************************************
FILENAME     :  video_uut_donut.sv
PROJECT      :  Hack-a-Thon 2026
DESCRIPTION  :  Hardware implementation of donut.c spinning torus
****************************************************************************/

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

// ============================================================================
// PARAMETERS
// ============================================================================
localparam [23:0] RGB_BG = 24'h00_00_00;      // Black background

// Screen parameters
localparam signed [12:0] CENTER_X = 960;
localparam signed [12:0] CENTER_Y = 540;

// Torus parameters (fixed-point Q8.8 format for some)
// R1 = major radius (donut hole to center of tube)
// R2 = minor radius (tube thickness)
localparam signed [15:0] R1 = 200;  // Major radius
localparam signed [15:0] R2 = 80;   // Minor radius  
localparam signed [15:0] K2 = 400;  // Distance from viewer
localparam signed [15:0] K1 = 300;  // Screen scaling factor

// ============================================================================
// SINE/COSINE LOOKUP TABLE (64 entries, Q1.14 fixed-point)
// Values from 0 to π/2, use symmetry for full circle
// sin(x) where x = index * (π/2) / 64
// Stored as 15-bit signed: range -16384 to +16384 represents -1.0 to +1.0
// ============================================================================
reg signed [15:0] sin_lut [0:63];
initial begin
    sin_lut[0]  = 16'd0;      sin_lut[1]  = 16'd804;    sin_lut[2]  = 16'd1608;   sin_lut[3]  = 16'd2410;
    sin_lut[4]  = 16'd3212;   sin_lut[5]  = 16'd4011;   sin_lut[6]  = 16'd4808;   sin_lut[7]  = 16'd5602;
    sin_lut[8]  = 16'd6393;   sin_lut[9]  = 16'd7179;   sin_lut[10] = 16'd7962;   sin_lut[11] = 16'd8739;
    sin_lut[12] = 16'd9512;   sin_lut[13] = 16'd10278;  sin_lut[14] = 16'd11039;  sin_lut[15] = 16'd11793;
    sin_lut[16] = 16'd12539;  sin_lut[17] = 16'd13279;  sin_lut[18] = 16'd14010;  sin_lut[19] = 16'd14732;
    sin_lut[20] = 16'd15446;  sin_lut[21] = 16'd16151;  sin_lut[22] = 16'd16846;  sin_lut[23] = 16'd17530;
    sin_lut[24] = 16'd18204;  sin_lut[25] = 16'd18868;  sin_lut[26] = 16'd19519;  sin_lut[27] = 16'd20159;
    sin_lut[28] = 16'd20787;  sin_lut[29] = 16'd21403;  sin_lut[30] = 16'd22005;  sin_lut[31] = 16'd22594;
    sin_lut[32] = 16'd23170;  sin_lut[33] = 16'd23731;  sin_lut[34] = 16'd24279;  sin_lut[35] = 16'd24811;
    sin_lut[36] = 16'd25329;  sin_lut[37] = 16'd25832;  sin_lut[38] = 16'd26319;  sin_lut[39] = 16'd26790;
    sin_lut[40] = 16'd27245;  sin_lut[41] = 16'd27683;  sin_lut[42] = 16'd28105;  sin_lut[43] = 16'd28510;
    sin_lut[44] = 16'd28898;  sin_lut[45] = 16'd29268;  sin_lut[46] = 16'd29621;  sin_lut[47] = 16'd29956;
    sin_lut[48] = 16'd30273;  sin_lut[49] = 16'd30571;  sin_lut[50] = 16'd30852;  sin_lut[51] = 16'd31113;
    sin_lut[52] = 16'd31356;  sin_lut[53] = 16'd31580;  sin_lut[54] = 16'd31785;  sin_lut[55] = 16'd31971;
    sin_lut[56] = 16'd32137;  sin_lut[57] = 16'd32285;  sin_lut[58] = 16'd32412;  sin_lut[59] = 16'd32521;
    sin_lut[60] = 16'd32609;  sin_lut[61] = 16'd32678;  sin_lut[62] = 16'd32728;  sin_lut[63] = 16'd32757;
end

// ============================================================================
// REGISTERS
// ============================================================================
reg [23:0] vid_rgb_d1;
reg [2:0]  dvh_sync_d1;

// Edge detection
reg h_d, v_d;
wire h_r = vh_blank_i[0] & ~h_d;
wire h_f = ~vh_blank_i[0] & h_d;
wire v_r = vh_blank_i[1] & ~v_d;

// Counters
reg [11:0] Hcount;
reg [11:0] Vcount;

// Rotation angles (8-bit, 256 = full circle)
reg [7:0] angle_A;  // X-axis rotation
reg [7:0] angle_B;  // Z-axis rotation

// Trig values for current frame (Q1.15 fixed point, <<15 = 1.0)
reg signed [15:0] sinA, cosA, sinB, cosB;

// Calculation intermediates
reg signed [31:0] dx, dy;
reg signed [31:0] dist_from_center;
reg signed [31:0] x_screen, y_screen;

// Donut shading calculation variables
reg signed [15:0] theta_approx;
reg signed [31:0] phi_factor;
reg signed [31:0] luminance;
reg [7:0] L;
reg signed [31:0] dist_from_ring;
reg signed [31:0] dist_sqrt_approx;

// ============================================================================
// SINE/COSINE FUNCTION - Uses LUT with quadrant logic
// Input: 8-bit angle (0-255 = 0 to 2π)
// Output: Q1.15 fixed-point (-32768 to 32767 = -1.0 to 1.0)
// ============================================================================
function signed [15:0] get_sin;
    input [7:0] angle;
    reg [5:0] lut_idx;
    reg [1:0] quadrant;
    reg signed [15:0] lut_val;
    begin
        quadrant = angle[7:6];
        case (quadrant)
            2'b00: begin lut_idx = angle[5:0];        lut_val =  sin_lut[lut_idx]; get_sin =  lut_val; end
            2'b01: begin lut_idx = 6'd63 - angle[5:0]; lut_val =  sin_lut[lut_idx]; get_sin =  lut_val; end
            2'b10: begin lut_idx = angle[5:0];        lut_val =  sin_lut[lut_idx]; get_sin = -lut_val; end
            2'b11: begin lut_idx = 6'd63 - angle[5:0]; lut_val =  sin_lut[lut_idx]; get_sin = -lut_val; end
        endcase
    end
endfunction

function signed [15:0] get_cos;
    input [7:0] angle;
    begin
        get_cos = get_sin(angle + 8'd64);  // cos(x) = sin(x + π/2)
    end
endfunction

// ============================================================================
// DONUT RENDERING - Simplified ray-marching approach
// For each pixel, check if it's on the torus surface
// ============================================================================

// Precompute squared radii
wire signed [31:0] R1_sq = R1 * R1;
wire signed [31:0] R2_sq = R2 * R2;
wire signed [31:0] outer_sq = (R1 + R2) * (R1 + R2);
wire signed [31:0] inner_sq = (R1 - R2) * (R1 - R2);

always @(posedge clk_i) begin
    if (cen_i) begin
        // Update counters
        Hcount <= (h_f) ? 12'd0 : (Hcount + 12'd1);
        
        if (v_r && h_r) begin
            Vcount <= 12'd0;
            // Update rotation angles each frame
            angle_A <= angle_A + 8'd2;  // Rotation speed around X
            angle_B <= angle_B + 8'd1;  // Rotation speed around Z
        end else if (h_r) begin
            Vcount <= Vcount + 12'd1;
        end
        
        h_d <= vh_blank_i[0];
        v_d <= vh_blank_i[1];
        
        // Get current sin/cos values
        sinA = get_sin(angle_A);
        cosA = get_cos(angle_A);
        sinB = get_sin(angle_B);
        cosB = get_cos(angle_B);
        
        // Calculate pixel distance from screen center
        dx = $signed({1'b0, Hcount}) - CENTER_X;
        dy = $signed({1'b0, Vcount}) - CENTER_Y;
        
        // Distance squared from center
        dist_from_center = (dx * dx) + (dy * dy);
        
        // ================================================================
        // TORUS RENDERING - 2D projection of spinning donut
        // The torus appears as a ring between inner_sq and outer_sq
        // Shading creates the 3D illusion
        // ================================================================
        
        // Check if pixel is within the torus bounds (between inner and outer radius)
        if (dist_from_center >= inner_sq && dist_from_center <= outer_sq) begin
            // We're on the visible torus surface - calculate shading
            
            // Calculate how far into the tube we are (0 at edges, max at center)
            // tube_depth represents position within the tube cross-section
            // At outer edge: dist_from_center = outer_sq, depth = 0
            // At tube center: dist_from_center = R1_sq, depth = max
            // At inner edge: dist_from_center = inner_sq, depth = 0
            
            // Approximate radial position (0-255 representing angle around tube)
            if (dist_from_center > R1_sq) begin
                // Outer half of tube
                dist_from_ring = (dist_from_center - R1_sq) >>> 10;
            end else begin
                // Inner half of tube  
                dist_from_ring = (R1_sq - dist_from_center) >>> 10;
            end
            
            // Calculate theta (angle around the ring) from screen position
            // Simple approximation using quadrant detection
            if (dx >= 0 && dy >= 0)
                theta_approx = (dx + dy) & 16'hFF;
            else if (dx < 0 && dy >= 0)
                theta_approx = 16'd64 + ((-dx) + dy) & 16'hFF;
            else if (dx < 0 && dy < 0)
                theta_approx = 16'd128 + ((-dx) + (-dy)) & 16'hFF;
            else
                theta_approx = 16'd192 + (dx + (-dy)) & 16'hFF;
            
            // Calculate luminance with rotation influence
            // Mix of: tube position (phi), ring position (theta), and rotation angles
            
            // Base luminance from position around the tube
            phi_factor = dist_from_ring[15:0];
            
            // Add rotation-based shading for 3D effect
            // sinA/cosA rotate around X-axis (tilting donut)
            // sinB/cosB rotate around Z-axis (spinning donut)
            luminance = 128;  // Base brightness
            
            // Add shading based on surface normal approximation
            // Top of torus is brighter (light from above)
            luminance = luminance + ((cosA * (256 - phi_factor)) >>> 16);
            
            // Front/back shading based on rotation B
            luminance = luminance + ((sinB * theta_approx) >>> 12);
            
            // Side shading based on horizontal position  
            luminance = luminance + ((cosB * dx) >>> 12);
            
            // Tube curvature shading
            luminance = luminance - (phi_factor >>> 2);
            
            // Clamp to 0-255
            if (luminance < 0) luminance = 32'd0;
            if (luminance > 255) luminance = 32'd255;
            
            L = luminance[7:0];
            
            // 12 shading levels like ".,-~:;=!*#$@"
            if (L < 21) begin
                vid_rgb_d1 <= 24'h1A_1A_1A;  // Very dark
            end else if (L < 42) begin
                vid_rgb_d1 <= 24'h33_33_33;
            end else if (L < 63) begin
                vid_rgb_d1 <= 24'h4D_4D_4D;
            end else if (L < 84) begin
                vid_rgb_d1 <= 24'h66_66_66;
            end else if (L < 105) begin
                vid_rgb_d1 <= 24'h80_80_80;
            end else if (L < 126) begin
                vid_rgb_d1 <= 24'h99_99_99;
            end else if (L < 147) begin
                vid_rgb_d1 <= 24'hB3_B3_B3;
            end else if (L < 168) begin
                vid_rgb_d1 <= 24'hCC_CC_CC;
            end else if (L < 189) begin
                vid_rgb_d1 <= 24'hE6_E6_E6;
            end else if (L < 210) begin
                vid_rgb_d1 <= 24'hFF_DD_AA;  // Warm highlight
            end else if (L < 231) begin
                vid_rgb_d1 <= 24'hFF_EE_CC;
            end else begin
                vid_rgb_d1 <= 24'hFF_FF_FF;  // Brightest
            end
            
        end else begin
            // Outside torus bounds OR inside the donut hole - show background
            vid_rgb_d1 <= (vid_sel_i) ? vid_rgb_i : RGB_BG;
        end
        
        dvh_sync_d1 <= dvh_sync_i;
    end
end

// ============================================================================
// OUTPUT ASSIGNMENTS
// ============================================================================
assign dvh_sync_o = dvh_sync_d1;
assign vid_rgb_o  = vid_rgb_d1;

endmodule
