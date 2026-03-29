// =============================================================================
// Tetris Top-Level Module — Nexys A7-100T
//
// Instantiates all sub-modules and wires up FPGA I/O.
// Single 100 MHz clock domain; no PLL/MMCM needed.
// =============================================================================
module tetris_top (
    input  logic        CLK100MHZ,

    // Buttons (active-high)
    input  logic        BTNL,
    input  logic        BTNR,
    input  logic        BTNU,
    input  logic        BTND,
    input  logic        BTNC,

    // Switches (only SW[0] and SW[15] are used)
    input  logic [15:0] SW,

    // UART TX output
    output logic        UART_RXD_OUT,

    // Seven-segment display (active-low)
    output logic [6:0]  SEG,
    output logic        DP,
    output logic [7:0]  AN,

    // LEDs
    output logic [15:0] LED,

    // Audio
    output logic        AUD_PWM,
    output logic        AUD_SD
);

    // =========================================================================
    // Reset: derive active-low reset from SW[15] or power-on synchronizer
    // =========================================================================
    // Simple synchronous reset: rst_n goes high after 4 cycles
    logic [2:0] rst_sr;
    logic       rst_n;

    always_ff @(posedge CLK100MHZ) begin
        rst_sr <= {rst_sr[1:0], 1'b1};
        rst_n  <= rst_sr[2];
    end

    // =========================================================================
    // Button debouncing
    // =========================================================================
    logic btnl_level, btnl_pulse;
    logic btnr_level, btnr_pulse;
    logic btnu_level, btnu_pulse;
    logic btnd_level, btnd_pulse;
    logic btnc_level, btnc_pulse;

    btn_debounce #(.CLK_FREQ(100_000_000), .DEBOUNCE_MS(20)) u_deb_l (
        .clk(CLK100MHZ), .rst_n(rst_n),
        .btn_in(BTNL), .btn_level(btnl_level), .btn_pulse(btnl_pulse)
    );
    btn_debounce #(.CLK_FREQ(100_000_000), .DEBOUNCE_MS(20)) u_deb_r (
        .clk(CLK100MHZ), .rst_n(rst_n),
        .btn_in(BTNR), .btn_level(btnr_level), .btn_pulse(btnr_pulse)
    );
    btn_debounce #(.CLK_FREQ(100_000_000), .DEBOUNCE_MS(20)) u_deb_u (
        .clk(CLK100MHZ), .rst_n(rst_n),
        .btn_in(BTNU), .btn_level(btnu_level), .btn_pulse(btnu_pulse)
    );
    btn_debounce #(.CLK_FREQ(100_000_000), .DEBOUNCE_MS(20)) u_deb_d (
        .clk(CLK100MHZ), .rst_n(rst_n),
        .btn_in(BTND), .btn_level(btnd_level), .btn_pulse(btnd_pulse)
    );
    btn_debounce #(.CLK_FREQ(100_000_000), .DEBOUNCE_MS(20)) u_deb_c (
        .clk(CLK100MHZ), .rst_n(rst_n),
        .btn_in(BTNC), .btn_level(btnc_level), .btn_pulse(btnc_pulse)
    );

    // =========================================================================
    // Game Engine
    // =========================================================================
    logic [1:0]  game_state;
    logic [19:0][9:0][2:0] board;
    logic [2:0]  active_type;
    logic [1:0]  active_rot;
    logic [5:0]  active_col;
    logic [5:0]  active_row;
    logic [2:0]  next_type;
    logic [5:0]  ghost_row;
    logic [31:0] score;
    logic [6:0]  level;
    logic [15:0] lines;
    logic        flash_active;
    logic        flash_toggle;
    logic        uart_trigger;

    logic        snd_move, snd_rotate, snd_lock, snd_line;
    logic        snd_tetris, snd_hard_drop, snd_game_over;

    tetris_engine u_eng (
        .clk             (CLK100MHZ),
        .rst_n           (rst_n),
        .btn_left_pulse  (btnl_pulse),
        .btn_right_pulse (btnr_pulse),
        .btn_rotate_pulse(btnu_pulse),
        .btn_down_pulse  (btnd_pulse),
        .btn_center_pulse(btnc_pulse),
        .btn_left_level  (btnl_level),
        .btn_right_level (btnr_level),
        .btn_down_level  (btnd_level),
        .sw_hard_drop    (SW[0]),
        .sw_reset        (SW[15]),
        .game_state      (game_state),
        .board_out       (board),
        .active_type     (active_type),
        .active_rot      (active_rot),
        .active_col      (active_col),
        .active_row      (active_row),
        .next_type       (next_type),
        .ghost_row       (ghost_row),
        .score           (score),
        .level           (level),
        .lines           (lines),
        .flash_active    (flash_active),
        .flash_toggle    (flash_toggle),
        .uart_trigger    (uart_trigger),
        .snd_move        (snd_move),
        .snd_rotate      (snd_rotate),
        .snd_lock        (snd_lock),
        .snd_line        (snd_line),
        .snd_tetris      (snd_tetris),
        .snd_hard_drop   (snd_hard_drop),
        .snd_game_over   (snd_game_over)
    );

    // =========================================================================
    // UART TX
    // =========================================================================
    logic [7:0] uart_tx_data;
    logic       uart_tx_start;
    logic       uart_tx_busy;

    uart_tx #(.CLK_FREQ(100_000_000), .BAUD(115200)) u_uart (
        .clk     (CLK100MHZ),
        .rst_n   (rst_n),
        .tx_data (uart_tx_data),
        .tx_start(uart_tx_start),
        .tx_out  (UART_RXD_OUT),
        .tx_busy (uart_tx_busy)
    );

    // =========================================================================
    // UART Packet Builder
    // =========================================================================
    uart_packet_builder #(.CLK_FREQ(100_000_000), .BAUD(115200)) u_pkt (
        .clk         (CLK100MHZ),
        .rst_n       (rst_n),
        .trigger     (uart_trigger),
        .game_state  (game_state),
        .board       (board),
        .active_type (active_type),
        .active_rot  (active_rot),
        .active_col  (active_col),
        .active_row  (active_row),
        .next_type   (next_type),
        .ghost_row   (ghost_row),
        .score       (score),
        .level       (level),
        .lines       (lines),
        .tx_data     (uart_tx_data),
        .tx_start    (uart_tx_start),
        .tx_busy     (uart_tx_busy),
        .sending     ()
    );

    // =========================================================================
    // Seven-Segment Display
    // =========================================================================
    seven_seg_driver #(.CLK_FREQ(100_000_000)) u_seg (
        .clk        (CLK100MHZ),
        .rst_n      (rst_n),
        .game_state (game_state),
        .score      (score),
        .level      (level),
        .SEG        (SEG),
        .DP         (DP),
        .AN         (AN)
    );

    // =========================================================================
    // LED Controller
    // =========================================================================
    led_controller #(.CLK_FREQ(100_000_000)) u_led (
        .clk        (CLK100MHZ),
        .rst_n      (rst_n),
        .game_state (game_state),
        .board      (board),
        .LED        (LED)
    );

    // =========================================================================
    // Audio Engine
    // =========================================================================
    audio_engine #(.CLK_FREQ(100_000_000)) u_aud (
        .clk           (CLK100MHZ),
        .rst_n         (rst_n),
        .snd_move      (snd_move),
        .snd_rotate    (snd_rotate),
        .snd_lock      (snd_lock),
        .snd_line      (snd_line),
        .snd_tetris    (snd_tetris),
        .snd_hard_drop (snd_hard_drop),
        .snd_game_over (snd_game_over),
        .AUD_PWM       (AUD_PWM),
        .AUD_SD        (AUD_SD)
    );

endmodule
