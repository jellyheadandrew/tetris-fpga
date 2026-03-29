// =============================================================================
// Seven-Segment Display Driver — Nexys A7-100T
//
// Multiplexes 8 digits at ~1 kHz.  Segment encoding matches the board's
// reversed pin order (SEG[0]=CG/middle, SEG[6]=CA/top).
//
// Display format (left=AN[7], right=AN[0]):
//   AN[7]: 'L'  custom glyph
//   AN[6]: 'v'  custom glyph
//   AN[5]: level tens digit  (decimal point ON)
//   AN[4]: level ones digit
//   AN[3]: blank
//   AN[2]: score thousands
//   AN[1]: score hundreds
//   AN[0]: score tens+ones  (actually tens only; score shown 4-digit)
//   Corrected: AN[2]=thousands AN[1]=hundreds AN[0]=tens  ... wait
//
//   Per spec Section 2.5:
//   AN[3]=thousands, AN[2]=hundreds, AN[1]=tens, AN[0]=ones
//
// TITLE state: all anodes OFF (blank).
// PLAYING / PAUSED / GAME_OVER: show score and level.
// =============================================================================
module seven_seg_driver #(
    parameter CLK_FREQ = 100_000_000
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [1:0]  game_state,   // 0=TITLE 1=PLAYING 2=PAUSED 3=GAMEOVER
    input  logic [31:0] score,
    input  logic [6:0]  level,

    // Board I/O
    output logic [6:0]  SEG,   // active-low segment outputs (SEG[6]=CA...SEG[0]=CG)
    output logic        DP,    // decimal point (active-low)
    output logic [7:0]  AN     // active-low anode enables
);

    // =========================================================================
    // Mux clock divider: ~1 kHz refresh, divided over 8 digits → ~125 Hz/digit
    // =========================================================================
    localparam MUX_DIV = CLK_FREQ / 8000;  // cycles per digit slot
    localparam W = $clog2(MUX_DIV);

    logic [W-1:0] div_cnt;
    logic [2:0]   digit_sel;  // 0-7

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt   <= '0;
            digit_sel <= 3'd0;
        end else begin
            if (div_cnt == W'(MUX_DIV - 1)) begin
                div_cnt   <= '0;
                digit_sel <= digit_sel + 3'd1;
            end else begin
                div_cnt <= div_cnt + 1;
            end
        end
    end

    // =========================================================================
    // BCD decomposition of score (mod 10000 per spec)
    // Use a registered value updated at the mux divider rate to avoid
    // long combinational path from 32-bit modulo.
    // =========================================================================
    logic [13:0] score_disp;  // 0..9999 fits in 14 bits
    // Compute mod 10000: use the fact that 10000 = 0x2710
    // score mod 10000 = score - floor(score/10000)*10000
    // For synthesis: Vivado handles division by constants via LUT tree.
    assign score_disp = 14'(score % 32'd10000);

    logic [3:0] s_thou, s_hund, s_tens, s_ones;
    assign s_thou = 4'(score_disp / 14'd1000);
    assign s_hund = 4'((score_disp / 14'd100) % 14'd10);
    assign s_tens = 4'((score_disp / 14'd10) % 14'd10);
    assign s_ones = 4'(score_disp % 14'd10);

    // BCD decomposition of level (1-99)
    logic [3:0] l_tens, l_ones;
    assign l_tens = 4'(level / 7'd10);
    assign l_ones = 4'(level % 7'd10);

    // =========================================================================
    // Segment decoder
    // SEG[6:0] = {CA, CB, CC, CD, CE, CF, CG} (active-low)
    // SEG[6]=top(A), SEG[5]=upper-right(B), SEG[4]=lower-right(C),
    // SEG[3]=bottom(D), SEG[2]=lower-left(E), SEG[1]=upper-left(F),
    // SEG[0]=middle(G)
    // =========================================================================
    function automatic [6:0] decode_digit(input [3:0] d);
        case (d)
            4'h0: decode_digit = 7'b0000001;  // A,B,C,D,E,F on, G off
            4'h1: decode_digit = 7'b1001111;  // B,C on
            4'h2: decode_digit = 7'b0010010;  // A,B,D,E,G on
            4'h3: decode_digit = 7'b0000110;  // A,B,C,D,G on
            4'h4: decode_digit = 7'b1001100;  // B,C,F,G on
            4'h5: decode_digit = 7'b0100100;  // A,C,D,F,G on
            4'h6: decode_digit = 7'b0100000;  // A,C,D,E,F,G on
            4'h7: decode_digit = 7'b0001111;  // A,B,C on
            4'h8: decode_digit = 7'b0000000;  // all on
            4'h9: decode_digit = 7'b0000100;  // A,B,C,D,F,G on
            default: decode_digit = 7'b1111111; // all off
        endcase
    endfunction

    // Custom glyphs (active-low, same bit ordering {CA,CB,CC,CD,CE,CF,CG})
    // 'L': segments F(upper-left), E(lower-left), D(bottom) on
    //   CA=off, CB=off, CC=off, CD=on, CE=on, CF=on, CG=off
    //   SEG = {1,1,1,0,0,0,1} = 7'b1110001
    localparam SEG_L = 7'b1110001;

    // 'v': segments C(lower-right), D(bottom), E(lower-left) on
    //   CA=off, CB=off, CC=on, CD=on, CE=on, CF=off, CG=off
    //   SEG = {1,1,0,0,0,1,1} = 7'b1100011
    localparam SEG_v = 7'b1100011;

    // Blank: all off
    localparam SEG_BLANK = 7'b1111111;

    // =========================================================================
    // Output mux: select digit based on digit_sel
    // AN[7]=leftmost=digit_sel==7, AN[0]=rightmost=digit_sel==0
    // Display pattern (when not TITLE): L v Lv.tens Lv.ones BLANK S_thou S_hund S_tens S_ones
    // Wait — only 8 digits. Map:
    //   digit_sel 7 → AN[7] → 'L'
    //   digit_sel 6 → AN[6] → 'v'
    //   digit_sel 5 → AN[5] → level_tens  (DP=0)
    //   digit_sel 4 → AN[4] → level_ones
    //   digit_sel 3 → AN[3] → blank
    //   digit_sel 2 → AN[2] → score_thousands
    //   digit_sel 1 → AN[1] → score_hundreds
    //   digit_sel 0 → AN[0] → score_tens (combined: use 4-digit score)
    //   Correction: show score as 4 digits on AN[3:0]
    //   So digit_sel 3→AN[3]→s_thou, 2→s_hund, 1→s_tens, 0→s_ones
    // =========================================================================
    logic [6:0] seg_out;
    logic       dp_out;
    logic [7:0] an_out;

    always_comb begin
        // Default: blank
        seg_out = SEG_BLANK;
        dp_out  = 1'b1;
        an_out  = 8'hFF;

        if (game_state != 2'd0) begin // not TITLE
            // Enable current digit
            an_out = ~(8'd1 << digit_sel);  // active-low: one digit enabled at a time

            case (digit_sel)
                3'd7: begin seg_out = SEG_L;                  dp_out = 1'b1; end
                3'd6: begin seg_out = SEG_v;                  dp_out = 1'b1; end
                3'd5: begin seg_out = decode_digit(l_tens);   dp_out = 1'b0; end // DP on
                3'd4: begin seg_out = decode_digit(l_ones);   dp_out = 1'b1; end
                3'd3: begin seg_out = decode_digit(s_thou);   dp_out = 1'b1; end
                3'd2: begin seg_out = decode_digit(s_hund);   dp_out = 1'b1; end
                3'd1: begin seg_out = decode_digit(s_tens);   dp_out = 1'b1; end
                3'd0: begin seg_out = decode_digit(s_ones);   dp_out = 1'b1; end
                default: begin seg_out = SEG_BLANK;           dp_out = 1'b1; end
            endcase
        end
    end

    assign SEG = seg_out;
    assign DP  = dp_out;
    assign AN  = an_out;

endmodule
