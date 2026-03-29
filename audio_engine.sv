// =============================================================================
// Audio Engine — Nexys A7-100T PWM audio
//
// Generates square-wave tones via AUD_PWM.
// AUD_SD held HIGH to enable the on-board audio amplifier.
//
// Sound effects:
//   Move:       800 Hz, 30 ms
//   Rotate:    1200 Hz, 50 ms
//   Lock:       200 Hz, 80 ms
//   Line clear: 500→1000 Hz ascending sweep, 150 ms (10 steps × 15 ms)
//   Tetris:     800→1000→1200 Hz fanfare, 400 ms (3 steps × 133 ms)
//   Hard drop:  100 Hz, 60 ms
//   Game over:  800→100 Hz descending sweep, 1000 ms (10 steps × 100 ms)
//
// All freq half-period values are computed from CLK_FREQ parameter so the
// module works correctly at any clock frequency (including CLK_FREQ=1_000_000
// used in the testbench).
// =============================================================================
module audio_engine #(
    parameter CLK_FREQ = 100_000_000
)(
    input  logic clk,
    input  logic rst_n,

    // Trigger inputs (one-cycle pulses; new trigger overrides current sound)
    input  logic snd_move,
    input  logic snd_rotate,
    input  logic snd_lock,
    input  logic snd_line,
    input  logic snd_tetris,
    input  logic snd_hard_drop,
    input  logic snd_game_over,

    // Audio outputs
    output logic AUD_PWM,
    output logic AUD_SD
);

    // Enable amplifier always
    assign AUD_SD = 1'b1;

    // =========================================================================
    // Parameterized half-period localparams (half_period = CLK_FREQ / (2*freq))
    // All division is on compile-time constants so NO hardware dividers generated.
    // =========================================================================
    localparam HP_100  = CLK_FREQ / 200;    // 100 Hz
    localparam HP_170  = CLK_FREQ / 340;    // 170 Hz
    localparam HP_200  = CLK_FREQ / 400;    // 200 Hz
    localparam HP_240  = CLK_FREQ / 480;    // 240 Hz
    localparam HP_310  = CLK_FREQ / 620;    // 310 Hz
    localparam HP_380  = CLK_FREQ / 760;    // 380 Hz
    localparam HP_450  = CLK_FREQ / 900;    // 450 Hz
    localparam HP_500  = CLK_FREQ / 1000;   // 500 Hz
    localparam HP_520  = CLK_FREQ / 1040;   // 520 Hz
    localparam HP_550  = CLK_FREQ / 1100;   // 550 Hz
    localparam HP_590  = CLK_FREQ / 1180;   // 590 Hz
    localparam HP_600  = CLK_FREQ / 1200;   // 600 Hz
    localparam HP_650  = CLK_FREQ / 1300;   // 650 Hz
    localparam HP_660  = CLK_FREQ / 1320;   // 660 Hz
    localparam HP_700  = CLK_FREQ / 1400;   // 700 Hz
    localparam HP_730  = CLK_FREQ / 1460;   // 730 Hz
    localparam HP_750  = CLK_FREQ / 1500;   // 750 Hz
    localparam HP_800  = CLK_FREQ / 1600;   // 800 Hz
    localparam HP_850  = CLK_FREQ / 1700;   // 850 Hz
    localparam HP_900  = CLK_FREQ / 1800;   // 900 Hz
    localparam HP_950  = CLK_FREQ / 1900;   // 950 Hz
    localparam HP_1000 = CLK_FREQ / 2000;   // 1000 Hz
    localparam HP_1200 = CLK_FREQ / 2400;   // 1200 Hz

    // =========================================================================
    // Sound type register
    // 0=none, 1=move, 2=rotate, 3=lock, 4=line, 5=tetris, 6=hard_drop, 7=game_over
    // =========================================================================
    logic [2:0] sound_type;

    // =========================================================================
    // Playback registers
    // freq_half/tone_cnt: 20 bits supports up to 1M cycles half-period (100 Hz @ 100 MHz)
    // =========================================================================
    logic [27:0] dur_cnt;   // remaining cycles
    logic [19:0] freq_half; // half-period in cycles for current pitch
    logic [19:0] tone_cnt;  // cycles until next wave toggle
    logic        wave;      // current square wave output (0/1)

    logic        is_sweep;  // 1 = frequency changes over time
    logic [26:0] step_dur;  // sweep step duration in cycles
    logic [26:0] step_cnt;  // countdown within current sweep step
    logic [3:0]  sweep_step;// how many steps have fired so far

    logic playing;
    assign playing = (dur_cnt > 0);
    assign AUD_PWM = playing ? wave : 1'b0;

    // =========================================================================
    // Precomputed sweep half-period lookup functions
    // Uses module localparams — pure compile-time constants, no hardware dividers.
    //
    // gameover_half(step): half-period AFTER step fires (800→730→...→100 Hz)
    // lineclear_half(step): half-period AFTER step fires (500→550→...→1000 Hz)
    // =========================================================================
    function automatic [19:0] gameover_half(input [3:0] step);
        case (step)
            4'd0:    gameover_half = 20'(HP_730);
            4'd1:    gameover_half = 20'(HP_660);
            4'd2:    gameover_half = 20'(HP_590);
            4'd3:    gameover_half = 20'(HP_520);
            4'd4:    gameover_half = 20'(HP_450);
            4'd5:    gameover_half = 20'(HP_380);
            4'd6:    gameover_half = 20'(HP_310);
            4'd7:    gameover_half = 20'(HP_240);
            4'd8:    gameover_half = 20'(HP_170);
            default: gameover_half = 20'(HP_100);
        endcase
    endfunction

    function automatic [19:0] lineclear_half(input [3:0] step);
        case (step)
            4'd0:    lineclear_half = 20'(HP_550);
            4'd1:    lineclear_half = 20'(HP_600);
            4'd2:    lineclear_half = 20'(HP_650);
            4'd3:    lineclear_half = 20'(HP_700);
            4'd4:    lineclear_half = 20'(HP_750);
            4'd5:    lineclear_half = 20'(HP_800);
            4'd6:    lineclear_half = 20'(HP_850);
            4'd7:    lineclear_half = 20'(HP_900);
            4'd8:    lineclear_half = 20'(HP_950);
            default: lineclear_half = 20'(HP_1000);
        endcase
    endfunction

    // =========================================================================
    // Main sequencer
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sound_type <= 3'd0;
            dur_cnt    <= 28'd0;
            freq_half  <= 20'd0;
            tone_cnt   <= 20'd0;
            wave       <= 1'b0;
            is_sweep   <= 1'b0;
            step_dur   <= 27'd0;
            step_cnt   <= 27'd0;
            sweep_step <= 4'd0;
        end else begin

            // ------------------------------------------------------------------
            // Trigger detection (priority: game_over > tetris > line > lock >
            //                    hard_drop > rotate > move)
            // New trigger always overrides current sound.
            // ------------------------------------------------------------------
            if (snd_game_over) begin
                sound_type <= 3'd7;
                dur_cnt    <= 28'(CLK_FREQ / 1000 * 1000);
                freq_half  <= 20'(HP_800);
                tone_cnt   <= 20'(HP_800);
                step_dur   <= 27'(CLK_FREQ / 1000 * 100);
                step_cnt   <= 27'(CLK_FREQ / 1000 * 100);
                sweep_step <= 4'd0;
                is_sweep   <= 1'b1;
                wave       <= 1'b0;

            end else if (snd_tetris) begin
                sound_type <= 3'd5;
                dur_cnt    <= 28'(CLK_FREQ / 1000 * 400);
                freq_half  <= 20'(HP_800);
                tone_cnt   <= 20'(HP_800);
                step_dur   <= 27'(CLK_FREQ / 1000 * 133);
                step_cnt   <= 27'(CLK_FREQ / 1000 * 133);
                sweep_step <= 4'd0;
                is_sweep   <= 1'b1;
                wave       <= 1'b0;

            end else if (snd_line) begin
                sound_type <= 3'd4;
                dur_cnt    <= 28'(CLK_FREQ / 1000 * 150);
                freq_half  <= 20'(HP_500);
                tone_cnt   <= 20'(HP_500);
                step_dur   <= 27'(CLK_FREQ / 1000 * 15);
                step_cnt   <= 27'(CLK_FREQ / 1000 * 15);
                sweep_step <= 4'd0;
                is_sweep   <= 1'b1;
                wave       <= 1'b0;

            end else if (snd_lock) begin
                sound_type <= 3'd3;
                dur_cnt    <= 28'(CLK_FREQ / 1000 * 80);
                freq_half  <= 20'(HP_200);
                tone_cnt   <= 20'(HP_200);
                is_sweep   <= 1'b0;
                wave       <= 1'b0;

            end else if (snd_hard_drop) begin
                sound_type <= 3'd6;
                dur_cnt    <= 28'(CLK_FREQ / 1000 * 60);
                freq_half  <= 20'(HP_100);
                tone_cnt   <= 20'(HP_100);
                is_sweep   <= 1'b0;
                wave       <= 1'b0;

            end else if (snd_rotate) begin
                sound_type <= 3'd2;
                dur_cnt    <= 28'(CLK_FREQ / 1000 * 50);
                freq_half  <= 20'(HP_1200);
                tone_cnt   <= 20'(HP_1200);
                is_sweep   <= 1'b0;
                wave       <= 1'b0;

            end else if (snd_move) begin
                sound_type <= 3'd1;
                dur_cnt    <= 28'(CLK_FREQ / 1000 * 30);
                freq_half  <= 20'(HP_800);
                tone_cnt   <= 20'(HP_800);
                is_sweep   <= 1'b0;
                wave       <= 1'b0;

            end else if (playing) begin
                // ----------------------------------------------------------------
                // Playback (no new trigger this cycle)
                // ----------------------------------------------------------------

                // Sweep: update frequency at each step boundary
                if (is_sweep) begin
                    if (step_cnt == 27'd0) begin
                        sweep_step <= sweep_step + 4'd1;
                        step_cnt   <= step_dur;

                        case (sound_type)
                            3'd7: begin // game over: 800→100 Hz descending
                                freq_half <= gameover_half(sweep_step);
                            end
                            3'd4: begin // line clear: 500→1000 Hz ascending
                                freq_half <= lineclear_half(sweep_step);
                            end
                            3'd5: begin // tetris fanfare: 800→1000→1200 Hz
                                case (sweep_step)
                                    4'd0:    freq_half <= 20'(HP_1000);
                                    4'd1:    freq_half <= 20'(HP_1200);
                                    default: freq_half <= 20'(HP_1200);
                                endcase
                            end
                            default: begin end
                        endcase
                    end else begin
                        step_cnt <= step_cnt - 27'd1;
                    end
                end

                // Tone oscillator: toggle wave at half-period
                if (tone_cnt == 20'd0) begin
                    wave     <= ~wave;
                    tone_cnt <= freq_half;
                end else begin
                    tone_cnt <= tone_cnt - 20'd1;
                end

                // Duration countdown
                dur_cnt <= dur_cnt - 28'd1;
                if (dur_cnt == 28'd1) begin
                    wave       <= 1'b0;
                    sound_type <= 3'd0;
                end
            end

        end
    end

endmodule
