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
localparam [23:0] RGB_BLACK = 24'h00_00_00; // Black

// Background colors for cycling
localparam [23:0] BG_COLOR_0 = 24'h1A_1A_2E; // Dark blue
localparam [23:0] BG_COLOR_1 = 24'h2E_1A_1A; // Dark red
localparam [23:0] BG_COLOR_2 = 24'h1A_2E_1A; // Dark green
localparam [23:0] BG_COLOR_3 = 24'h2E_2E_1A; // Dark yellow
localparam [23:0] BG_COLOR_4 = 24'h2E_1A_2E; // Dark purple
localparam [23:0] BG_COLOR_5 = 24'h1A_2E_2E; // Dark cyan


// Donut dimensions and screen size
// ROM dimensions (actual data size)
localparam [11:0] DONUT_ROM_WIDTH = 200;
localparam [11:0] DONUT_ROM_HEIGHT = 88;
// Display dimensions (2x scaled)
localparam [11:0] DONUT_WIDTH = 400;
localparam [11:0] DONUT_HEIGHT = 176;

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

// Animation parameters
localparam [21:0] FRAME_SIZE = 17600;  // 200 x 88 pixels per frame
localparam [7:0] NUM_FRAMES = 30;      // Total number of frames
reg [7:0] frame_counter;                // Current frame (0-29)
reg [7:0] frame_delay_counter;          // Frame rate control
localparam [7:0] DELAY_COUNT = 4;       // ~60Hz / 15fps = 4 vsyncs per frame
// Background color cycling (every 3 seconds / 180 frames)
reg [7:0] bg_frame_counter;             // Count frames for background color change
reg [2:0] bg_color_index;               // Index for which background color to use (0-5)
localparam [7:0] BG_CHANGE_FRAMES = 120; // 120 frames = 2 seconds at 60fps
reg [23:0] current_bg_color;            // The current background color

// Donut ROM signals
wire [3:0] donut_lum;
reg [31:0] donut_addr;
reg [11:0] donut_x_rel;
reg [11:0] donut_y_rel;
reg [7:0] brightness;
reg [8:0] r_temp, g_temp, b_temp;
reg [23:0] bg_color;
localparam [11:0] DONUT_X_START = (SCREEN_WIDTH - DONUT_WIDTH) / 2;  // Center X
localparam [11:0] DONUT_Y_START = (SCREEN_HEIGHT - DONUT_HEIGHT) / 2; // Center Y

// Letter dimensions (commented out)
// localparam [11:0] R_WIDTH = 368;
// localparam [11:0] R_HEIGHT = 352;
// localparam [11:0] S_WIDTH = 625;
// localparam [11:0] S_HEIGHT = 352;

// Letter positions (commented out)
// localparam [11:0] LETTER_Y_START = (SCREEN_HEIGHT - R_HEIGHT) / 2;
// localparam [11:0] R_X_START = DONUT_X_START - R_WIDTH;
// localparam [11:0] S_X_START = DONUT_X_START + DONUT_WIDTH;

// Letter ROM signals (commented out)
// wire r_lum;
// wire s_lum;
// reg [31:0] r_addr;
// reg [31:0] s_addr;
// reg [11:0] r_x_rel;
// reg [11:0] r_y_rel;
// reg [11:0] s_x_rel;
// reg [11:0] s_y_rel;

// Donut ROM instantiation
donut_rom donut_rom_inst (
    .clk_i(clk_i),
    .cen_i(cen_i),
    .addr_rd(donut_addr),
    .data_o(donut_lum)
);

// R_rom instantiation (commented out)
// R_rom r_rom_inst (
//     .clk_i(clk_i),
//     .cen_i(cen_i),
//     .addr_rd(r_addr),
//     .data_o(r_lum)
// );

// S_rom instantiation (commented out)
// S_rom s_rom_inst (
//     .clk_i(clk_i),
//     .cen_i(cen_i),
//     .addr_rd(s_addr),
//     .data_o(s_lum)
// );


always @(posedge clk_i) begin
    // ALL OF OUR CALCULATIONS PER PIXEL
    
    if(cen_i) begin
       //vid_rgb_d1  <= (vid_sel_i)? RGB_COLOUR : vid_rgb_i;
       //dvh_sync_d1 <= dvh_sync_i;
       //my code
       
       Hcount <= (h_f)? (0) : (Hcount + 1);
       if(v_r && h_r) begin
            Vcount <= 0;
            
            // Frame animation counter
            if (frame_delay_counter >= DELAY_COUNT - 1) begin
                frame_delay_counter <= 0;
                // Advance to next frame (loop back to 0)
                frame_counter <= (frame_counter >= NUM_FRAMES - 1) ? 8'd0 : frame_counter + 1;
            end else begin
                frame_delay_counter <= frame_delay_counter + 1;
            end
            
            // Background color cycling counter
            if (bg_frame_counter >= BG_CHANGE_FRAMES - 1) begin
                bg_frame_counter <= 0;
                // Cycle through colors (0-5)
                bg_color_index <= (bg_color_index >= 5) ? 3'd0 : bg_color_index + 1;
            end else begin
                bg_frame_counter <= bg_frame_counter + 1;
            end
        end else if(h_r) begin
            Vcount <= Vcount + 1;
        end
        h_d <= vh_blank_i[0];
        v_d <= vh_blank_i[1];
        
        // Select current background color based on index
        case(bg_color_index)
            3'd0: current_bg_color <= BG_COLOR_0;
            3'd1: current_bg_color <= BG_COLOR_1;
            3'd2: current_bg_color <= BG_COLOR_2;
            3'd3: current_bg_color <= BG_COLOR_3;
            3'd4: current_bg_color <= BG_COLOR_4;
            3'd5: current_bg_color <= BG_COLOR_5;
            default: current_bg_color <= BG_COLOR_0;
        endcase
        
        // Display R letter from ROM (commented out)
        // if ((Hcount >= R_X_START && Hcount < R_X_START + R_WIDTH) &&
        //     (Vcount >= LETTER_Y_START && Vcount < LETTER_Y_START + R_HEIGHT)) begin
        //     r_x_rel <= Hcount - R_X_START;
        //     r_y_rel <= Vcount - LETTER_Y_START;
        //     r_addr <= (r_y_rel * R_WIDTH) + r_x_rel;
        //     vid_rgb_d1 <= (r_lum) ? RGB_WHITE : ((vid_sel_i) ? current_bg_color : vid_rgb_i);
        // end
        // Display S letter from ROM (commented out)
        // else if ((Hcount >= S_X_START && Hcount < S_X_START + S_WIDTH) &&
        //          (Vcount >= LETTER_Y_START && Vcount < LETTER_Y_START + S_HEIGHT)) begin
        //     s_x_rel <= Hcount - S_X_START;
        //     s_y_rel <= Vcount - LETTER_Y_START;
        //     s_addr <= (s_y_rel * S_WIDTH) + s_x_rel;
        //     vid_rgb_d1 <= (s_lum) ? RGB_WHITE : ((vid_sel_i) ? current_bg_color : vid_rgb_i);
        // end
        // Display donut with 2x scaling
        if ((Hcount >= DONUT_X_START && Hcount < DONUT_X_START + DONUT_WIDTH) && 
            (Vcount >= DONUT_Y_START && Vcount < DONUT_Y_START + DONUT_HEIGHT)) begin
            
            // Calculate relative position in display coordinates
            donut_x_rel <= Hcount - DONUT_X_START;
            donut_y_rel <= Vcount - DONUT_Y_START;
            // Scale down by 2 for ROM lookup (>> 1 is divide by 2)
            donut_addr <= (frame_counter * FRAME_SIZE) + ((donut_y_rel >> 1) * DONUT_ROM_WIDTH) + (donut_x_rel >> 1);
            
            // Get actual background color (changes based on vid_sel_i)
            bg_color <= (vid_sel_i) ? current_bg_color : vid_rgb_i;
            
            // Check if luminance is 0 (transparent - show background)
            if (donut_lum == 4'h0) begin
                vid_rgb_d1 <= (vid_sel_i) ? current_bg_color : vid_rgb_i;
            end else begin
                // Scale luminance value (1-15) to RGB color starting from actual background
                // Higher luminance = brighter (adds to base color)
                brightness <= {donut_lum, donut_lum};  // 4-bit to 8-bit scaling (e.g., 0xF -> 0xFF)
                r_temp = {1'b0, bg_color[23:16]} + {1'b0, brightness};  // R channel + brightness
                g_temp = {1'b0, bg_color[15:8]} + {1'b0, brightness};   // G channel + brightness
                b_temp = {1'b0, bg_color[7:0]} + {1'b0, brightness};    // B channel + brightness
                vid_rgb_d1 <= {(r_temp > 255) ? 8'hFF : r_temp[7:0],
                               (g_temp > 255) ? 8'hFF : g_temp[7:0],
                               (b_temp > 255) ? 8'hFF : b_temp[7:0]};
            end
        end
        // Background (else case)
        else begin
            donut_addr <= 32'b0;
            vid_rgb_d1 <= (vid_sel_i)? current_bg_color : vid_rgb_i;
        end
        
        dvh_sync_d1 <= dvh_sync_i;
    end
    
end

// OUTPUT
assign dvh_sync_o  = dvh_sync_d1;
assign vid_rgb_o   = vid_rgb_d1;

endmodule
