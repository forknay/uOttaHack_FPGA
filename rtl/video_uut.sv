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


// Donut dimensions and screen size
localparam [11:0] DONUT_WIDTH = 800;
localparam [11:0] DONUT_HEIGHT = 352;

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
localparam [21:0] FRAME_SIZE = 281600;  // 800 x 352 pixels per frame
localparam [7:0] NUM_FRAMES = 60;      // Total number of frames
reg [7:0] frame_counter;                // Current frame (0-9)
reg [7:0] frame_delay_counter;          // Frame rate control
localparam [7:0] DELAY_COUNT = 4;       // ~60Hz / 15fps = 4 vsyncs per frame

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



// Donut ROM instantiation
donut_rom donut_rom_inst (
    .clk_i(clk_i),
    .cen_i(cen_i),
    .addr_rd(donut_addr),
    //.addr_wr(),
    .data_o(donut_lum)
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
            
            // Frame animation counter
            if (frame_delay_counter >= DELAY_COUNT - 1) begin
                frame_delay_counter <= 0;
                // Advance to next frame (loop back to 0)
                frame_counter <= (frame_counter >= NUM_FRAMES - 1) ? 8'd0 : frame_counter + 1;
            end else begin
                frame_delay_counter <= frame_delay_counter + 1;
            end
        end else if(h_r) begin
            Vcount <= Vcount + 1;
        end
        h_d <= vh_blank_i[0];
        v_d <= vh_blank_i[1];
        
        // Display donut from ROM, centered on screen
        // Check if current pixel is within donut bounds
        if ((Hcount >= DONUT_X_START && Hcount < DONUT_X_START + DONUT_WIDTH) && 
            (Vcount >= DONUT_Y_START && Vcount < DONUT_Y_START + DONUT_HEIGHT)) begin
            
            // Calculate address in donut ROM based on relative position
            donut_x_rel <= Hcount - DONUT_X_START;
            donut_y_rel <= Vcount - DONUT_Y_START;
            // Calculate final ROM address: frame_offset + pixel_offset
            donut_addr <= (frame_counter * FRAME_SIZE) + (donut_y_rel * DONUT_WIDTH) + donut_x_rel;
            
            // Get actual background color (changes based on vid_sel_i)
            bg_color <= (vid_sel_i) ? RGB_COLOUR : vid_rgb_i;
            
            // Check if luminance is 0 (transparent - show background)
            if (donut_lum == 4'h0) begin
                vid_rgb_d1 <= (vid_sel_i) ? RGB_COLOUR : vid_rgb_i;
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
        end else begin
            donut_addr <= 15'b0;
            vid_rgb_d1 <= (vid_sel_i)? RGB_COLOUR : vid_rgb_i;
        end
        
        dvh_sync_d1 <= dvh_sync_i;
    end
    
end

// OUTPUT
assign dvh_sync_o  = dvh_sync_d1;
assign vid_rgb_o   = vid_rgb_d1;

endmodule

