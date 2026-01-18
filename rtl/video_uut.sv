/****************************************************************************
FILENAME     :  video_uut.sv
PROJECT      :  Hack-a-Thon 2026
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

    // Fixed-point format: Q16.16 (16 integer bits, 16 fractional bits)
    localparam FRAC_BITS = 16;
    localparam ONE = 1 << FRAC_BITS;
    
    // Screen dimensions
    localparam SCREEN_W = 1920;
    localparam SCREEN_H = 1080;
    
    // Grid cell dimensions (each cell can contain a square)
    localparam CELL_SIZE = 24;  // 24x24 pixel cells
    localparam GRID_W = 80;     // 80 cells wide (1920/24)
    localparam GRID_H = 45;     // 45 cells tall (1080/24)
    localparam GRID_SIZE = GRID_W * GRID_H;  // 3600 cells
    
    // Torus rendering parameters
    localparam [7:0] THETA_DIVISIONS = 64;   // theta loop iterations
    localparam [7:0] PHI_DIVISIONS = 64;     // phi loop iterations
    localparam [15:0] THETA_STEP = 256 / THETA_DIVISIONS;  // 4 units per step
    localparam [15:0] PHI_STEP = 256 / PHI_DIVISIONS;      // 4 units per step
    
    // Video timing tracking
    reg [11:0] Hcount;
    reg [11:0] Vcount;
    reg h_d, v_d;
    wire h_r = vh_blank_i[0] & ~h_d;
    wire h_f = ~vh_blank_i[0] & h_d;
    wire v_r = vh_blank_i[1] & ~v_d;
    
    // Rotation angles (increment each frame)
    reg [15:0] angle_A;
    reg [15:0] angle_B;
    
    // Double-buffered frame buffers
    reg [3:0] brightness_buffer0 [0:GRID_SIZE-1];   // Buffer 0
    reg [3:0] brightness_buffer1 [0:GRID_SIZE-1];   // Buffer 1
    reg signed [15:0] zbuffer0 [0:GRID_SIZE-1];     // Z-buffer 0
    reg signed [15:0] zbuffer1 [0:GRID_SIZE-1];     // Z-buffer 1
    reg render_to_buffer0;  // Which buffer we're rendering TO
    
    // Rendering state machine
    typedef enum logic [2:0] {
        IDLE,
        CLEAR_BUFFER,
        RENDER_STAGE1,   // Compute trig values
        RENDER_STAGE2,   // Compute intermediate values
        RENDER_STAGE3,   // Compute projection
        RENDER_STAGE4,   // Plot pixel
        SWAP_BUFFERS
    } state_t;
    
    state_t state, next_state;
    
    // Render loop counters
    reg [7:0] theta_iter;   // 0 to THETA_DIVISIONS-1
    reg [7:0] phi_iter;     // 0 to PHI_DIVISIONS-1
    reg [11:0] clear_idx;   // For clearing buffers
    
    // Pipeline registers for multi-stage rendering
    reg signed [31:0] sin_i, cos_i, sin_j, cos_j;
    reg signed [31:0] sin_A, cos_A, sin_B, cos_B;
    reg signed [31:0] c, d, e, f, g, h, l, m, n, t;
    reg signed [31:0] D_inv, D;
    reg signed [31:0] x_calc, y_calc;
    reg signed [31:0] N_calc;
    reg signed [15:0] N;
    reg [10:0] x_screen, y_screen;
    reg [11:0] buffer_idx;
    
    // Simple sine/cosine approximation
    function signed [31:0] sin_approx;
        input [7:0] angle;
        reg [7:0] a;
        reg signed [31:0] result;
        begin
            a = angle;
            // Piecewise linear approximation
            if (a < 64) begin
                result = (a * 1608) << 6;  // ~sin for 0 to π/2
            end else if (a < 128) begin
                result = ((128 - a) * 1608) << 6;  // π/2 to π
            end else if (a < 192) begin
                result = -(((a - 128) * 1608) << 6);  // π to 3π/2
            end else begin
                result = -(((256 - a) * 1608) << 6);  // 3π/2 to 2π
            end
            sin_approx = result;
        end
    endfunction
    
    function signed [31:0] cos_approx;
        input [7:0] angle;
        begin
            cos_approx = sin_approx(angle + 64);  // cos = sin(θ + π/2)
        end
    endfunction
    
    // Fixed-point multiply (Q16.16 * Q16.16 = Q16.16)
    function signed [31:0] fp_mult;
        input signed [31:0] a, b;
        reg signed [63:0] temp;
        begin
            temp = a * b;
            fp_mult = temp[47:16];
        end
    endfunction
    
    // Fixed-point divide with overflow protection
    function signed [31:0] fp_div;
        input signed [31:0] dividend, divisor;
        reg signed [63:0] temp;
        begin
            if (divisor == 0) begin
                fp_div = 32'h7FFFFFFF;
            end else if (divisor < 256 && divisor > -256) begin
                // Very small divisor, return max to avoid overflow
                fp_div = 32'h7FFFFFFF;
            end else begin
                temp = {dividend, 16'b0};
                fp_div = temp / divisor;
            end
        end
    endfunction
    
    // Square size lookup based on brightness
    function [4:0] get_square_size;
        input [3:0] brightness;
        begin
            case (brightness)
                4'd0:  get_square_size = 5'd2;
                4'd1:  get_square_size = 5'd4;
                4'd2:  get_square_size = 5'd6;
                4'd3:  get_square_size = 5'd8;
                4'd4:  get_square_size = 5'd10;
                4'd5:  get_square_size = 5'd12;
                4'd6:  get_square_size = 5'd14;
                4'd7:  get_square_size = 5'd16;
                4'd8:  get_square_size = 5'd18;
                4'd9:  get_square_size = 5'd20;
                4'd10: get_square_size = 5'd22;
                4'd11: get_square_size = 5'd24;
                default: get_square_size = 5'd2;
            endcase
        end
    endfunction
    
    // Render theta/phi values (8-bit angles)
    wire [7:0] render_theta_val = theta_iter * THETA_STEP[7:0];
    wire [7:0] render_phi_val = phi_iter * PHI_STEP[7:0];
    
    // Main FSM
    always @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            state <= IDLE;
            angle_A <= 0;
            angle_B <= 0;
            render_to_buffer0 <= 1'b1;
            theta_iter <= 0;
            phi_iter <= 0;
            clear_idx <= 0;
            h_d <= 0;
            v_d <= 0;
            Hcount <= 0;
            Vcount <= 0;
        end else if (cen_i) begin
            // Track video timing (always running)
            h_d <= vh_blank_i[0];
            v_d <= vh_blank_i[1];
            
            if (h_f) begin
                Hcount <= 12'b0;
            end else begin
                Hcount <= Hcount + 1;
            end
            
            if (v_r && h_r) begin
                Vcount <= 12'b0;
            end else if (h_r) begin
                Vcount <= Vcount + 1;
            end
            
            state <= next_state;
            
            case (state)
                IDLE: begin
                    theta_iter <= 0;
                    phi_iter <= 0;
                    clear_idx <= 0;
                end
                
                CLEAR_BUFFER: begin
                    // Clear one location per clock
                    if (clear_idx < GRID_SIZE) begin
                        if (render_to_buffer0) begin
                            brightness_buffer0[clear_idx] <= 4'd0;
                            zbuffer0[clear_idx] <= 16'sh8000;  // Most negative value
                        end else begin
                            brightness_buffer1[clear_idx] <= 4'd0;
                            zbuffer1[clear_idx] <= 16'sh8000;
                        end
                        clear_idx <= clear_idx + 1;
                    end
                end
                
                RENDER_STAGE1: begin
                    // Stage 1: Compute trig values
                    sin_i <= sin_approx(render_phi_val);
                    cos_i <= cos_approx(render_phi_val);
                    sin_j <= sin_approx(render_theta_val);
                    cos_j <= cos_approx(render_theta_val);
                    sin_A <= sin_approx(angle_A[7:0]);
                    cos_A <= cos_approx(angle_A[7:0]);
                    sin_B <= sin_approx(angle_B[7:0]);
                    cos_B <= cos_approx(angle_B[7:0]);
                end
                
                RENDER_STAGE2: begin
                    // Stage 2: Compute intermediate values
                    c <= sin_i;
                    d <= cos_j;
                    e <= sin_A;
                    f <= sin_j;
                    g <= cos_A;
                    h <= cos_j + (2 << FRAC_BITS);
                    l <= cos_i;
                    m <= cos_B;
                    n <= sin_B;
                end
                
                RENDER_STAGE3: begin
                    // Stage 3: Compute projection and lighting
                    t <= fp_mult(fp_mult(c, h), g) - fp_mult(f, e);
                    D_inv <= fp_mult(fp_mult(c, h), e) + fp_mult(f, g) + (5 << FRAC_BITS);
                    
                    // Calculate lighting value
                    N_calc <= fp_mult(fp_mult(f, e) - fp_mult(fp_mult(c, d), g), m) 
                            - fp_mult(fp_mult(c, d), e) 
                            - fp_mult(f, g) 
                            - fp_mult(fp_mult(l, d), n);
                end
                
                RENDER_STAGE4: begin
                    // Stage 4: Complete projection and plot
                    D <= fp_div(ONE, D_inv);
                    
                    // x = 40 + 30 * D * (l * h * m - t * n)
                    x_calc <= (40 << FRAC_BITS) + fp_mult(fp_mult(30 << FRAC_BITS, D),
                                (fp_mult(fp_mult(l, h), m) - fp_mult(t, n)));
                    
                    // y = 12 + 15 * D * (l * h * n + t * m)
                    y_calc <= (12 << FRAC_BITS) + fp_mult(fp_mult(15 << FRAC_BITS, D),
                                (fp_mult(fp_mult(l, h), n) + fp_mult(t, m)));
                    
                    // Scale and clamp lighting
                    N <= N_calc >>> 13;
                    
                    // Calculate screen position
                    x_screen <= x_calc >>> FRAC_BITS;
                    y_screen <= y_calc >>> FRAC_BITS;
                    
                    // Plot if in bounds and passes Z-test
                    if ((x_calc >>> FRAC_BITS) < GRID_W && (y_calc >>> FRAC_BITS) < GRID_H) begin
                        buffer_idx <= (y_calc >>> FRAC_BITS) * GRID_W + (x_calc >>> FRAC_BITS);
                        
                        // Z-buffer test and write
                        if (render_to_buffer0) begin
                            if (D[15:0] > zbuffer0[buffer_idx]) begin
                                zbuffer0[buffer_idx] <= D[15:0];
                                brightness_buffer0[buffer_idx] <= (N > 11) ? 4'd11 : (N < 0) ? 4'd0 : N[3:0];
                            end
                        end else begin
                            if (D[15:0] > zbuffer1[buffer_idx]) begin
                                zbuffer1[buffer_idx] <= D[15:0];
                                brightness_buffer1[buffer_idx] <= (N > 11) ? 4'd11 : (N < 0) ? 4'd0 : N[3:0];
                            end
                        end
                    end
                    
                    // Increment loop counters
                    if (phi_iter < PHI_DIVISIONS - 1) begin
                        phi_iter <= phi_iter + 1;
                    end else begin
                        phi_iter <= 0;
                        if (theta_iter < THETA_DIVISIONS - 1) begin
                            theta_iter <= theta_iter + 1;
                        end
                    end
                end
                
                SWAP_BUFFERS: begin
                    // Swap buffers and update rotation angles
                    render_to_buffer0 <= ~render_to_buffer0;
                    angle_A <= angle_A + 2;  // Rotation speed
                    angle_B <= angle_B + 1;
                    theta_iter <= 0;
                    phi_iter <= 0;
                    clear_idx <= 0;
                end
            endcase
        end
    end
    
    // Next state logic
    always @(*) begin
        case (state)
            IDLE: 
                next_state = CLEAR_BUFFER;
            
            CLEAR_BUFFER: 
                next_state = (clear_idx >= GRID_SIZE - 1) ? RENDER_STAGE1 : CLEAR_BUFFER;
            
            RENDER_STAGE1: 
                next_state = RENDER_STAGE2;
            
            RENDER_STAGE2: 
                next_state = RENDER_STAGE3;
            
            RENDER_STAGE3: 
                next_state = RENDER_STAGE4;
            
            RENDER_STAGE4: begin
                // Check if rendering is complete
                if (theta_iter == THETA_DIVISIONS - 1 && phi_iter == PHI_DIVISIONS - 1)
                    next_state = SWAP_BUFFERS;
                else
                    next_state = RENDER_STAGE1;
            end
            
            SWAP_BUFFERS: 
                next_state = CLEAR_BUFFER;
            
            default: 
                next_state = IDLE;
        endcase
    end
    
    // Video output generation (combinational)
    wire [6:0] cell_x = Hcount / CELL_SIZE;
    wire [5:0] cell_y = Vcount / CELL_SIZE;
    wire [11:0] cell_addr = cell_y * GRID_W + cell_x;
    
    wire [4:0] pixel_in_cell_x = Hcount % CELL_SIZE;
    wire [4:0] pixel_in_cell_y = Vcount % CELL_SIZE;
    
    // Read from display buffer (opposite of render buffer)
    wire [3:0] cell_brightness = render_to_buffer0 ? 
                                 brightness_buffer1[cell_addr] : 
                                 brightness_buffer0[cell_addr];
    
    wire [4:0] current_square_size = get_square_size(cell_brightness);
    
    wire [4:0] square_margin = (CELL_SIZE - current_square_size) >> 1;
    wire [4:0] square_start = square_margin;
    wire [4:0] square_end = square_margin + current_square_size;
    
    wire pixel_inside_square = (pixel_in_cell_x >= square_start) &&
                               (pixel_in_cell_x < square_end) &&
                               (pixel_in_cell_y >= square_start) &&
                               (pixel_in_cell_y < square_end);
    
    // Color gradient based on brightness (cyan/blue theme)
    wire [7:0] red_value   = (cell_brightness << 4) + 8'd16;
    wire [7:0] green_value = (cell_brightness << 4) + 8'd64;
    wire [7:0] blue_value  = (cell_brightness << 4) + 8'd128;
    
    wire [23:0] donut_rgb = pixel_inside_square ?
                            {red_value, green_value, blue_value} :
                            24'h001020;  // Dark blue background
    
    // Output multiplexer
    assign vid_rgb_o = vid_sel_i ? donut_rgb : vid_rgb_i;
    
    // Delay sync signals by 1 clock to match pipeline
    reg [2:0] dvh_sync_delayed;
    always @(posedge clk_i) begin
        dvh_sync_delayed <= dvh_sync_i;
    end
    
    assign dvh_sync_o = dvh_sync_delayed;

endmodule