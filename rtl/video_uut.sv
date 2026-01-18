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

// Color definitions
localparam [23:0] RGB_COLOUR = 24'hFF_5A_43;
localparam [23:0] RGB_WHITE = 24'hFF_FF_FF;
localparam [23:0] RGB_BLACK = 24'h00_00_00;

// Screen size
localparam [11:0] SCREEN_WIDTH = 1920;
localparam [11:0] SCREEN_HEIGHT = 1125;

// Delayed output registers
reg [23:0]  vid_rgb_d1;
reg [2:0]   dvh_sync_d1;

// Pixel tracking
(* mark_debug = "true", keep = "true" *)
wire h_r = vh_blank_i[0] & ~h_d;
(* mark_debug = "true", keep = "true" *)
wire h_f = ~vh_blank_i[0] & h_d;
(* mark_debug = "true", keep = "true" *)
wire v_r = vh_blank_i[1] & ~v_d;
(* mark_debug = "true", keep = "true" *)
wire v_f = ~vh_blank_i[1] & v_d;

reg h_d;
reg v_d;
reg [11:0] Hcount;
reg [11:0] Vcount;

// Donut rendering parameters
localparam [7:0] THETA_MAX = 51;      // ~360/7 steps
localparam [7:0] PHI_MAX = 179;       // ~360/2 steps
localparam [7:0] R1 = 1;
localparam [7:0] R2 = 2;
localparam [13:0] K1 = 1200;
localparam [8:0] K2 = 5;

// Rotation angles
reg [7:0] angleA;
reg [7:0] angleB;

// Rendering state
reg [1:0] render_state;  // 0=idle, 1=rendering, 2=computing
reg [7:0] theta_idx;
reg [7:0] phi_idx;

// Trig lookup table addresses for all 8 trig values needed
reg [7:0] addr_sinA, addr_cosA, addr_sinB, addr_cosB;
reg [7:0] addr_sintheta, addr_costheta, addr_sinphi, addr_cosphi;

// Trig value outputs from lookup tables
wire [7:0] sin_A_val, cos_A_val, sin_B_val, cos_B_val;
wire [7:0] sin_theta_val, cos_theta_val, sin_phi_val, cos_phi_val;

// Donut renderer outputs
wire [10:0] donut_xp, donut_yp;
wire [3:0]  donut_lum;
wire        donut_valid;

// RAM signals
wire [14:0] addr_rd;
wire [14:0] addr_wr;
wire [3:0] data_i;
wire [3:0] data_o;

// Frame buffer address calculation
assign addr_rd = Vcount * 12'd1920 + Hcount;
assign addr_wr = donut_valid ? (donut_yp * 12'd1920 + donut_xp) : 15'd0;
assign data_i = donut_lum;

// Instantiate sine and cosine RAMs
sine_ram sine_ram_A(
    .clk_i (clk_i),
    .cen_i (cen_i),
    .addr_rd (addr_sinA),
    .data_o (sin_A_val)
);

cosine_ram cosine_ram_A(
    .clk_i (clk_i),
    .cen_i (cen_i),
    .addr_rd (addr_cosA),
    .data_o (cos_A_val)
);

sine_ram sine_ram_B(
    .clk_i (clk_i),
    .cen_i (cen_i),
    .addr_rd (addr_sinB),
    .data_o (sin_B_val)
);

cosine_ram cosine_ram_B(
    .clk_i (clk_i),
    .cen_i (cen_i),
    .addr_rd (addr_cosB),
    .data_o (cos_B_val)
);

sine_ram sine_ram_theta(
    .clk_i (clk_i),
    .cen_i (cen_i),
    .addr_rd (addr_sintheta),
    .data_o (sin_theta_val)
);

cosine_ram cosine_ram_theta(
    .clk_i (clk_i),
    .cen_i (cen_i),
    .addr_rd (addr_costheta),
    .data_o (cos_theta_val)
);

sine_ram sine_ram_phi(
    .clk_i (clk_i),
    .cen_i (cen_i),
    .addr_rd (addr_sinphi),
    .data_o (sin_phi_val)
);

cosine_ram cosine_ram_phi(
    .clk_i (clk_i),
    .cen_i (cen_i),
    .addr_rd (addr_cosphi),
    .data_o (cos_phi_val)
);

// Donut renderer instance
donut_renderer donut_renderer_inst(
    .clk_i (clk_i),
    .cen_i (cen_i),
    .rst_i (rst_i),
    .angleA_i (angleA),
    .angleB_i (angleB),
    .theta_i (theta_idx),
    .phi_i (phi_idx),
    .sin_A_i (sin_A_val),
    .cos_A_i (cos_A_val),
    .sin_B_i (sin_B_val),
    .cos_B_i (cos_B_val),
    .sin_theta_i (sin_theta_val),
    .cos_theta_i (cos_theta_val),
    .sin_phi_i (sin_phi_val),
    .cos_phi_i (cos_phi_val),
    .xp_o (donut_xp),
    .yp_o (donut_yp),
    .lum_o (donut_lum),
    .valid_o (donut_valid)
);

donut_ram donut_ram_inst(
    .clk_i (clk_i),
    .cen_i (cen_i),
    .addr_rd (addr_rd),
    .addr_wr (addr_wr),
    .data_i (data_i),
    .data_o (data_o)
); 

always @(posedge clk_i) begin
    if(cen_i) begin
        // Track horizontal and vertical counters
        Hcount <= (h_f) ? 12'd0 : (Hcount + 1);
        
        if (v_r && h_r) begin
            // New frame started
            Vcount <= 12'd0;
            render_state <= 1;  // Start rendering donut
            theta_idx <= 8'd0;
            phi_idx <= 8'd0;
            
            // Update rotation angles for animation
            angleA <= angleA + 8'd1;
            angleB <= angleB + 8'd2;
            
        end else if (h_r) begin
            Vcount <= Vcount + 1;
        end
        
        h_d <= vh_blank_i[0];
        v_d <= vh_blank_i[1];
        
        // ===== DONUT RENDERING STATE MACHINE =====
        case (render_state)
            1: begin  // Rendering state - compute next pixel
                // Request trig values for current angles and indices
                addr_sinA <= angleA;
                addr_cosA <= angleA;
                addr_sinB <= angleB;
                addr_cosB <= angleB;
                addr_sintheta <= theta_idx;
                addr_costheta <= theta_idx;
                addr_sinphi <= phi_idx;
                addr_cosphi <= phi_idx;
                
                render_state <= 2;  // Move to compute stage
            end
            
            2: begin  // Compute stage - wait for donut renderer output
                // Increment indices after requesting computation
                if (phi_idx < PHI_MAX) begin
                    phi_idx <= phi_idx + 1;
                end else begin
                    phi_idx <= 8'd0;
                    if (theta_idx < THETA_MAX) begin
                        theta_idx <= theta_idx + 1;
                        render_state <= 1;  // Continue rendering
                    end else begin
                        render_state <= 0;  // Frame complete
                    end
                end
            end
            
            default: begin
                render_state <= 0;  // Idle
            end
        endcase
    end
    
    // Simple color mapping for display
    // If data_o is non-zero, show donut; otherwise show background
    if (data_o == 4'b0000) begin
        vid_rgb_d1 <= RGB_BLACK;
    end else begin
        // Map luminance index to grayscale
        case (data_o)
            4'd1:      vid_rgb_d1 <= 24'h11_11_11;
            4'd2:      vid_rgb_d1 <= 24'h22_22_22;
            4'd3:      vid_rgb_d1 <= 24'h33_33_33;
            4'd4:      vid_rgb_d1 <= 24'h44_44_44;
            4'd5:      vid_rgb_d1 <= 24'h55_55_55;
            4'd6:      vid_rgb_d1 <= 24'h66_66_66;
            4'd7:      vid_rgb_d1 <= 24'h77_77_77;
            4'd8:      vid_rgb_d1 <= 24'h88_88_88;
            4'd9:      vid_rgb_d1 <= 24'h99_99_99;
            4'd10:     vid_rgb_d1 <= 24'hAA_AA_AA;
            4'd11:     vid_rgb_d1 <= 24'hBB_BB_BB;
            default:   vid_rgb_d1 <= RGB_WHITE;
        endcase
    end
    
    dvh_sync_d1 <= dvh_sync_i;
end

// OUTPUT
assign dvh_sync_o  = dvh_sync_d1;
assign vid_rgb_o   = vid_rgb_d1;

endmodule

