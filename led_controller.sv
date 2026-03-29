// =============================================================================
// LED Controller — Nexys A7-100T
//
// LED behavior per game state:
//   TITLE:     Larson scanner (bouncing bright dot across 16 LEDs)
//   PLAYING:   LED[9:0] = board fill level indicator
//   PAUSED:    All 16 LEDs blink at 2 Hz
//   GAME_OVER: All 16 LEDs on solid
// =============================================================================
module led_controller #(
    parameter CLK_FREQ = 100_000_000
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [1:0]  game_state,     // 0=TITLE 1=PLAYING 2=PAUSED 3=GAMEOVER
    input  logic [19:0][9:0][2:0] board,

    output logic [15:0] LED
);

    // =========================================================================
    // Larson scanner for TITLE state
    // Speed: ~30 ms per step (30 steps to go 15 positions each way)
    // =========================================================================
    localparam LARSON_STEP = CLK_FREQ / 30;  // ~33 ms
    localparam LW = $clog2(LARSON_STEP);

    logic [LW-1:0] larson_cnt;
    logic [3:0]    larson_pos;  // 0-15
    logic          larson_dir;  // 0=right, 1=left

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            larson_cnt <= '0;
            larson_pos <= 4'd0;
            larson_dir <= 1'b0;
        end else if (larson_cnt == LW'(LARSON_STEP - 1)) begin
            larson_cnt <= '0;
            if (!larson_dir) begin
                if (larson_pos == 4'd15) begin
                    larson_dir <= 1'b1;
                    larson_pos <= 4'd14;
                end else
                    larson_pos <= larson_pos + 4'd1;
            end else begin
                if (larson_pos == 4'd0) begin
                    larson_dir <= 1'b0;
                    larson_pos <= 4'd1;
                end else
                    larson_pos <= larson_pos - 4'd1;
            end
        end else begin
            larson_cnt <= larson_cnt + 1;
        end
    end

    // Larson: bright center + fade on neighbors (3-LED wide)
    logic [15:0] larson_leds;
    always_comb begin
        larson_leds = 16'd0;
        larson_leds[larson_pos] = 1'b1;
        if (larson_pos > 0)     larson_leds[larson_pos - 1] = 1'b1;
        if (larson_pos < 15)    larson_leds[larson_pos + 1] = 1'b1;
    end

    // =========================================================================
    // 2 Hz blink for PAUSED state
    // =========================================================================
    localparam BLINK_HALF = CLK_FREQ / 4;  // 250 ms half-period → 2 Hz
    localparam BW = $clog2(BLINK_HALF);

    logic [BW-1:0] blink_cnt;
    logic          blink_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            blink_cnt   <= '0;
            blink_state <= 1'b0;
        end else if (blink_cnt == BW'(BLINK_HALF - 1)) begin
            blink_cnt   <= '0;
            blink_state <= ~blink_state;
        end else begin
            blink_cnt <= blink_cnt + 1;
        end
    end

    // =========================================================================
    // Board fill level (PLAYING state)
    // LED[i] = 1 if rows 2i or 2i+1 contain any occupied cell
    // LED[0] = rows 0-1, LED[1] = rows 2-3, ..., LED[9] = rows 18-19
    // =========================================================================
    logic [9:0] fill_leds;
    always_comb begin
        integer i, r, c;
        for (i = 0; i < 10; i++) begin
            fill_leds[i] = 1'b0;
            for (r = i*2; r < i*2+2; r++) begin
                for (c = 0; c < 10; c++) begin
                    if (board[r][c] != 3'b0)
                        fill_leds[i] = 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // Output mux
    // =========================================================================
    always_comb begin
        case (game_state)
            2'd0:    LED = larson_leds;                         // TITLE
            2'd1:    LED = {6'b0, fill_leds};                   // PLAYING
            2'd2:    LED = blink_state ? 16'hFFFF : 16'h0000;   // PAUSED
            2'd3:    LED = 16'hFFFF;                            // GAME_OVER
            default: LED = 16'h0000;
        endcase
    end

endmodule
