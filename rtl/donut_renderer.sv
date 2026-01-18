/****************************************************************************
FILENAME     :  donut_renderer.sv
PROJECT      :  Hack-a-Thon 2026
DESCRIPTION  :  3D Donut renderer using lookup tables for trig functions
                Computes 3D donut surface and projects to 2D screen
****************************************************************************/

module donut_renderer (
    input  wire         clk_i,
    input  wire         cen_i,
    input  wire         rst_i,
    
    // Input angles (0-255 representing 0-2π)
    input  wire [7:0]   angleA_i,
    input  wire [7:0]   angleB_i,
    input  wire [7:0]   theta_i,      // Angle index for tube
    input  wire [7:0]   phi_i,        // Angle index for revolution
    
    // Trig values from lookup tables
    input  wire [7:0]   sin_A_i,
    input  wire [7:0]   cos_A_i,
    input  wire [7:0]   sin_B_i,
    input  wire [7:0]   cos_B_i,
    input  wire [7:0]   sin_theta_i,
    input  wire [7:0]   cos_theta_i,
    input  wire [7:0]   sin_phi_i,
    input  wire [7:0]   cos_phi_i,
    
    // Output 3D coordinates and luminance
    output reg  [10:0]  xp_o,        // Screen X (0-1919)
    output reg  [10:0]  yp_o,        // Screen Y (0-1124)
    output reg  [3:0]   lum_o,       // Luminance index (0-11)
    output reg          valid_o      // Valid pixel flag
);

// Constants - using scaled integer math
// Trig values are 0-255, map to -1.0 to ~1.0
// For fixed point: 127 = ~1.0, -128 = -1.0

localparam [7:0] R1 = 1;         // Tube radius
localparam [7:0] R2 = 2;         // Major radius
localparam [10:0] K1 = 600;      // Screen projection factor
localparam [8:0] K2 = 5;         // Z offset

// Convert trig table outputs (0-255) to signed representation
// 0 = -1.0, 128 = 0, 255 = +1.0 (approximately)
function signed [8:0] trig_to_signed(input [7:0] val);
    trig_to_signed = {1'b0, val} - 16'h80;
endfunction

// Multiplier for fixed-point scaling (approximate reciprocal of z)
function [15:0] calc_reciprocal(input signed [15:0] z_val);
    if (z_val <= 0)
        calc_reciprocal = 16'd0;
    else
        calc_reciprocal = 16'd512 / z_val;  // Scaled reciprocal
endfunction

// Pipeline registers for computation
reg [2:0] pipeline_stage;
reg signed [8:0] sinA, cosA, sinB, cosB;
reg signed [8:0] sintheta, costheta, sinphi, cosphi;
reg signed [15:0] circlex, circley;
reg signed [15:0] x, y, z;
reg signed [15:0] lum;
reg [10:0] xp_raw, yp_raw;

always @(posedge clk_i) begin
    if (rst_i) begin
        pipeline_stage <= 3'd0;
        valid_o <= 1'b0;
    end else if (cen_i) begin
        // Pipeline stage 0: Convert trig values
        sinA <= trig_to_signed(sin_A_i);
        cosA <= trig_to_signed(cos_A_i);
        sinB <= trig_to_signed(sin_B_i);
        cosB <= trig_to_signed(cos_B_i);
        sintheta <= trig_to_signed(sin_theta_i);
        costheta <= trig_to_signed(cos_theta_i);
        sinphi <= trig_to_signed(sin_phi_i);
        cosphi <= trig_to_signed(cos_phi_i);
        pipeline_stage <= pipeline_stage + 1;
        
        // Pipeline stage 1: Calculate circle points (before revolution)
        if (pipeline_stage == 0) begin
            // circlex = R2 + R1*cos(theta)
            circlex <= (R2 << 8) + ((R1 * costheta) >> 3);
            // circley = R1*sin(theta)
            circley <= (R1 * sintheta);
        end
        
        // Pipeline stage 2: Calculate 3D coordinates after rotation
        if (pipeline_stage == 1) begin
            // Simplified 3D rotation (reduced precision for hardware)
            // x = circlex*(cosB*cosphi + sinA*sinB*sinphi) - circley*cosA*sinB
            x <= ((circlex * cosB * cosphi) >> 10) + ((circlex * sinA * sinB * sinphi) >> 14) 
                 - ((circley * cosA * sinB) >> 8);
            
            // y = circlex*(sinB*cosphi - sinA*cosB*sinphi) + circley*cosA*cosB
            y <= ((circlex * sinB * cosphi) >> 10) - ((circlex * sinA * cosB * sinphi) >> 14)
                 + ((circley * cosA * cosB) >> 8);
            
            // z = K2 + cosA*circlex*sinphi + circley*sinA
            z <= (K2 << 8) + ((cosA * circlex * sinphi) >> 8) + ((circley * sinA) << 1);
        end
        
        // Pipeline stage 3: Project to 2D and calculate luminance
        if (pipeline_stage == 2) begin
            if (z > (K2 << 7)) begin  // Only show if in front
                // ooz = 1/z as fixed point
                // xp = 960 + K1*(x/z)
                // yp = 562 - K1*(y/z)
                xp_raw <= 960 + ((K1 * x) / (z >> 6));
                yp_raw <= 562 - ((K1 * y) / (z >> 6));
                
                // Calculate luminance
                // L = cosphi*costheta*sinB - cosA*costheta*sinphi - sinA*sintheta + ...
                lum <= ((cosphi * costheta * sinB) >> 6)
                     - ((cosA * costheta * sinphi) >> 6)
                     - ((sinA * sintheta) >> 2)
                     + ((cosB * ((cosA * sintheta) >> 2)) >> 4);
                
                valid_o <= 1'b1;
            end else begin
                valid_o <= 1'b0;
            end
        end
        
        // Pipeline stage 4: Output mapping
        if (pipeline_stage == 3) begin
            xp_o <= (xp_raw < 1920) ? xp_raw : 11'd0;
            yp_o <= (yp_raw < 1125) ? yp_raw : 11'd0;
            
            // Map luminance to 0-11 range
            if (lum > 0) begin
                lum_o <= (lum >> 3) & 4'hF;
            end else begin
                lum_o <= 4'h0;
            end
        end
        
        if (pipeline_stage >= 3) begin
            pipeline_stage <= 3'd0;
        end
    end
end

endmodule

