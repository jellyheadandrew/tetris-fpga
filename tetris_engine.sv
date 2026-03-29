// =============================================================================
// Tetris Game Engine
// Implements complete Tetris game logic: movement, gravity, SRS rotation,
// lock delay, line clearing, scoring, DAS, ghost piece.
// All logic in single 100 MHz clock domain.
// =============================================================================
module tetris_engine (
    input  logic        clk,
    input  logic        rst_n,

    // Button inputs: pulse = one-cycle HIGH on press
    input  logic        btn_left_pulse,
    input  logic        btn_right_pulse,
    input  logic        btn_rotate_pulse,
    input  logic        btn_down_pulse,
    input  logic        btn_center_pulse,

    // Button levels: HIGH while held (for DAS + soft drop)
    input  logic        btn_left_level,
    input  logic        btn_right_level,
    input  logic        btn_down_level,

    // Switch inputs
    input  logic        sw_hard_drop,  // SW[0]: BTND = hard drop
    input  logic        sw_reset,      // SW[15]: master reset

    // Outputs: game state
    output logic [1:0]  game_state,    // 0=TITLE 1=PLAYING 2=PAUSED 3=GAMEOVER
    output logic [19:0][9:0][2:0] board_out,
    output logic [2:0]  active_type,
    output logic [1:0]  active_rot,
    output logic [5:0]  active_col,    // signed 6-bit (2's complement)
    output logic [5:0]  active_row,    // signed 6-bit (2's complement)
    output logic [2:0]  next_type,
    output logic [5:0]  ghost_row,     // signed 6-bit
    output logic [31:0] score,
    output logic [6:0]  level,
    output logic [15:0] lines,
    output logic        flash_active,
    output logic        flash_toggle,

    // UART trigger: one-cycle pulse to request packet transmission
    output logic        uart_trigger,

    // Audio event pulses
    output logic        snd_move,
    output logic        snd_rotate,
    output logic        snd_lock,
    output logic        snd_line,
    output logic        snd_tetris,
    output logic        snd_hard_drop,
    output logic        snd_game_over
);

    // =========================================================================
    // State encoding
    // =========================================================================
    localparam logic [2:0]
        ST_TITLE     = 3'd0,
        ST_SPAWN     = 3'd1,
        ST_PLAYING   = 3'd2,
        ST_LINE_ANIM = 3'd3,
        ST_PAUSED    = 3'd4,
        ST_GAMEOVER  = 3'd5;

    logic [2:0] state;

    // =========================================================================
    // Timing constants (100 MHz)
    // =========================================================================
    localparam LOCK_DELAY    = 27'd50_000_000;   // 500 ms
    localparam SOFT_DROP_INT = 27'd1_667_000;    // ~16.7 ms
    localparam DAS_INITIAL   = 27'd20_000_000;   // 200 ms
    localparam DAS_REPEAT    = 27'd5_000_000;    // 50 ms
    localparam ANIM_FLASH    = 25'd5_000_000;    // 50 ms per flash phase
    localparam ANIM_STEPS    = 3'd6;             // 3 flashes × 2 phases
    localparam GAMEOVER_LOCK = 28'd200_000_000;  // 2 s

    // =========================================================================
    // Registers
    // =========================================================================
    logic [19:0][9:0][2:0] board;
    logic [2:0]  a_type;
    logic [1:0]  a_rot;
    logic [5:0]  a_col;
    logic [5:0]  a_row;
    logic [2:0]  nxt_type;

    logic [31:0] score_r;
    logic [6:0]  level_r;
    logic [15:0] lines_r;

    logic [26:0] grav_cnt;
    logic [26:0] lock_cnt;
    logic [3:0]  lock_rst_cnt;
    logic        in_lock;

    logic [26:0] das_l_cnt;
    logic [26:0] das_r_cnt;

    logic [24:0] anim_cnt;
    logic [2:0]  anim_phase;

    logic [27:0] go_cnt;
    logic        go_unlocked;

    logic [19:0] comp_rows;   // which rows are complete (for line clear)
    logic [2:0]  n_comp;      // count of complete rows

    // =========================================================================
    // LFSR for piece randomization
    // =========================================================================
    logic lfsr_en;
    logic [15:0] lfsr_raw;
    logic [2:0]  lfsr_piece;
    logic        lfsr_valid;

    assign lfsr_en = (state == ST_PLAYING) || (state == ST_SPAWN)   ||
                     (state == ST_LINE_ANIM) || (state == ST_PAUSED) ||
                     (state == ST_GAMEOVER);

    lfsr_rng u_rng (
        .clk        (clk),
        .rst_n      (rst_n),
        .en         (lfsr_en),
        .lfsr_out   (lfsr_raw),
        .piece_out  (lfsr_piece),
        .piece_valid(lfsr_valid)
    );

    // Update nxt_type whenever LFSR produces a valid value (and not spawning)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            nxt_type <= 3'd1;
        else if (lfsr_valid && state != ST_SPAWN)
            nxt_type <= lfsr_piece;
    end

    // =========================================================================
    // Piece ROM — inline function avoids module port overhead
    // =========================================================================
    function automatic [15:0] get_mask(input [2:0] pt, input [1:0] rt);
        case ({pt, rt})
            {3'd1,2'd0}: get_mask = 16'h0F00;
            {3'd1,2'd1}: get_mask = 16'h2222;
            {3'd1,2'd2}: get_mask = 16'h00F0;
            {3'd1,2'd3}: get_mask = 16'h4444;
            {3'd2,2'd0}: get_mask = 16'h6600;
            {3'd2,2'd1}: get_mask = 16'h6600;
            {3'd2,2'd2}: get_mask = 16'h6600;
            {3'd2,2'd3}: get_mask = 16'h6600;
            {3'd3,2'd0}: get_mask = 16'h4E00;
            {3'd3,2'd1}: get_mask = 16'h4640;
            {3'd3,2'd2}: get_mask = 16'h0E40;
            {3'd3,2'd3}: get_mask = 16'h4C40;
            {3'd4,2'd0}: get_mask = 16'h6C00;
            {3'd4,2'd1}: get_mask = 16'h4620;
            {3'd4,2'd2}: get_mask = 16'h06C0;
            {3'd4,2'd3}: get_mask = 16'h8C40;
            {3'd5,2'd0}: get_mask = 16'hC600;
            {3'd5,2'd1}: get_mask = 16'h2640;
            {3'd5,2'd2}: get_mask = 16'h0C60;
            {3'd5,2'd3}: get_mask = 16'h4C80;
            {3'd6,2'd0}: get_mask = 16'h8E00;
            {3'd6,2'd1}: get_mask = 16'h6440;
            {3'd6,2'd2}: get_mask = 16'h0E20;
            {3'd6,2'd3}: get_mask = 16'h44C0;
            {3'd7,2'd0}: get_mask = 16'h2E00;
            {3'd7,2'd1}: get_mask = 16'h4460;
            {3'd7,2'd2}: get_mask = 16'h08E0;
            {3'd7,2'd3}: get_mask = 16'h6220;
            default:     get_mask = 16'h0000;
        endcase
    endfunction

    // =========================================================================
    // Collision check function (automatic — safe in synthesis)
    // Checks piece (type, rot) at position (pc, pr) against board brd.
    // pc, pr: 6-bit 2's complement signed values
    // =========================================================================
    function automatic logic coll_check(
        input logic [2:0]              pt,
        input logic [1:0]              rt,
        input logic [5:0]              pc,
        input logic [5:0]              pr,
        input logic [19:0][9:0][2:0]   brd
    );
        logic [15:0]     msk;
        logic signed [6:0] br, bc;
        integer r, c;

        msk = get_mask(pt, rt);
        coll_check = 1'b0;

        for (r = 0; r < 4; r++) begin
            for (c = 0; c < 4; c++) begin
                if (msk[15 - r*4 - c]) begin
                    br = $signed({pr[5], pr}) + 7'(r);
                    bc = $signed({pc[5], pc}) + 7'(c);
                    if (bc < 0 || bc >= 7'sd10)
                        coll_check = 1'b1;
                    else if (br >= 7'sd20)
                        coll_check = 1'b1;
                    else if (br >= 0 &&
                             brd[br[4:0]][bc[3:0]] != 3'b0)
                        coll_check = 1'b1;
                end
            end
        end
    endfunction

    // =========================================================================
    // Gravity interval (cycles) per level
    // =========================================================================
    function automatic [26:0] grav_int(input [6:0] lvl);
        case (lvl)
            7'd1:    grav_int = 27'd100_000_000;
            7'd2:    grav_int = 27'd79_300_000;
            7'd3:    grav_int = 27'd61_800_000;
            7'd4:    grav_int = 27'd47_300_000;
            7'd5:    grav_int = 27'd35_500_000;
            7'd6:    grav_int = 27'd26_200_000;
            7'd7:    grav_int = 27'd19_000_000;
            7'd8:    grav_int = 27'd13_500_000;
            7'd9:    grav_int = 27'd10_000_000;
            default: grav_int = 27'd6_700_000;
        endcase
    endfunction

    // =========================================================================
    // Score points for line clears
    // =========================================================================
    function automatic [31:0] calc_score(input [2:0] nl, input [6:0] lvl);
        logic [10:0] base;
        case (nl)
            3'd1:    base = 11'd100;
            3'd2:    base = 11'd300;
            3'd3:    base = 11'd500;
            3'd4:    base = 11'd800;
            default: base = 11'd0;
        endcase
        // Small multiplication: base is 11-bit max, lvl is 7-bit max
        // Use explicit narrow widths to avoid DSP block inference
        calc_score = {14'b0, base[10:0] * lvl[6:0]};
    endfunction

    // =========================================================================
    // SRS kick offsets
    // from_rot = transition being attempted (0=0->1, 1=1->2, 2=2->3, 3=3->0)
    // test_num = 0-3 (4 kick tests)
    // Output: col_off, row_off (positive row_off = up = subtract from row)
    // =========================================================================
    function automatic void kick_off(
        input  logic [2:0] pt,
        input  logic [1:0] from_rot,
        input  logic [1:0] tnum,
        output logic signed [3:0] co,
        output logic signed [3:0] ro
    );
        if (pt == 3'd1) begin // I-piece
            case ({from_rot, tnum})
                4'b0000: begin co=-4'sd2; ro= 4'sd0; end
                4'b0001: begin co= 4'sd1; ro= 4'sd0; end
                4'b0010: begin co=-4'sd2; ro=-4'sd1; end
                4'b0011: begin co= 4'sd1; ro= 4'sd2; end
                4'b0100: begin co= 4'sd2; ro= 4'sd0; end
                4'b0101: begin co=-4'sd1; ro= 4'sd0; end
                4'b0110: begin co= 4'sd2; ro= 4'sd1; end
                4'b0111: begin co=-4'sd1; ro=-4'sd2; end
                4'b1000: begin co=-4'sd1; ro= 4'sd0; end
                4'b1001: begin co= 4'sd2; ro= 4'sd0; end
                4'b1010: begin co=-4'sd1; ro= 4'sd2; end
                4'b1011: begin co= 4'sd2; ro=-4'sd1; end
                4'b1100: begin co= 4'sd1; ro= 4'sd0; end
                4'b1101: begin co=-4'sd2; ro= 4'sd0; end
                4'b1110: begin co= 4'sd1; ro=-4'sd2; end
                4'b1111: begin co=-4'sd2; ro= 4'sd1; end
                default: begin co= 4'sd0; ro= 4'sd0; end
            endcase
        end else begin // JLSTZ
            case ({from_rot, tnum})
                4'b0000: begin co=-4'sd1; ro= 4'sd0; end
                4'b0001: begin co=-4'sd1; ro= 4'sd1; end
                4'b0010: begin co= 4'sd0; ro=-4'sd2; end
                4'b0011: begin co=-4'sd1; ro=-4'sd2; end
                4'b0100: begin co= 4'sd1; ro= 4'sd0; end
                4'b0101: begin co= 4'sd1; ro=-4'sd1; end
                4'b0110: begin co= 4'sd0; ro= 4'sd2; end
                4'b0111: begin co= 4'sd1; ro= 4'sd2; end
                4'b1000: begin co= 4'sd1; ro= 4'sd0; end
                4'b1001: begin co= 4'sd1; ro= 4'sd1; end
                4'b1010: begin co= 4'sd0; ro=-4'sd2; end
                4'b1011: begin co= 4'sd1; ro=-4'sd2; end
                4'b1100: begin co=-4'sd1; ro= 4'sd0; end
                4'b1101: begin co=-4'sd1; ro=-4'sd1; end
                4'b1110: begin co= 4'sd0; ro= 4'sd2; end
                4'b1111: begin co=-4'sd1; ro= 4'sd2; end
                default: begin co= 4'sd0; ro= 4'sd0; end
            endcase
        end
    endfunction

    // =========================================================================
    // Combinational: current piece mask
    // =========================================================================
    logic [15:0] a_mask;
    assign a_mask = get_mask(a_type, a_rot);

    // =========================================================================
    // Combinational: ghost row
    // Use integer arithmetic to avoid 6-bit overflow (a_row+dr can reach 39).
    // Only check rows 0..19; the loop stops as soon as rows would be out of
    // the board (floor collision is already guaranteed at row 20+).
    // =========================================================================
    logic [5:0] ghost_r;
    always_comb begin
        integer dr, test_row, ar_int;
        ar_int  = $unsigned(a_row[4:0]);  // treat a_row as unsigned 0-31
        ghost_r = a_row;
        for (dr = 1; dr <= 20; dr++) begin
            test_row = ar_int + dr;
            if (test_row < 20) begin  // row must be within board
                if (!coll_check(a_type, a_rot, a_col, 6'(test_row), board))
                    ghost_r = 6'(test_row);
            end
            // row 20+ always causes floor collision; no need to check further
        end
    end

    // =========================================================================
    // Combinational: simple collision checks
    // =========================================================================
    logic coll_below, coll_left, coll_right;
    assign coll_below = coll_check(a_type, a_rot, a_col,
                                   6'(a_row) + 6'd1, board);
    assign coll_left  = coll_check(a_type, a_rot,
                                   6'(a_col) - 6'd1, a_row, board);
    assign coll_right = coll_check(a_type, a_rot,
                                   6'(a_col) + 6'd1, a_row, board);

    // =========================================================================
    // Combinational: rotation test positions and results (SRS)
    // new_rot = a_rot + 1 (wraps 3->0)
    // test 0 = no kick, tests 1-4 = SRS kicks
    // =========================================================================
    logic [1:0]  new_rot;
    logic [5:0]  rot_tcol[5];
    logic [5:0]  rot_trow[5];
    logic        rot_tok [5];
    logic signed [3:0] kco, kro;

    assign new_rot = a_rot + 2'd1;

    // Test 0: direct rotation, no kick
    assign rot_tcol[0] = a_col;
    assign rot_trow[0] = a_row;
    assign rot_tok[0]  = !coll_check(a_type, new_rot, rot_tcol[0],
                                      rot_trow[0], board);

    // Tests 1-4: kick offsets
    genvar ki;
    generate
        for (ki = 0; ki < 4; ki++) begin : KICK_TEST
            logic signed [3:0] kco_w, kro_w;
            always_comb begin
                kick_off(a_type, a_rot, 2'(ki), kco_w, kro_w);
                rot_tcol[ki+1] = 6'(a_col) + {{2{kco_w[3]}}, kco_w};
                rot_trow[ki+1] = 6'(a_row) - {{2{kro_w[3]}}, kro_w};
                rot_tok[ki+1]  = !coll_check(a_type, new_rot,
                                              rot_tcol[ki+1],
                                              rot_trow[ki+1], board);
            end
        end
    endgenerate

    // Pick first valid rotation test
    logic [2:0] rot_winner;
    logic       rot_possible;
    always_comb begin
        if      (rot_tok[0]) rot_winner = 3'd0;
        else if (rot_tok[1]) rot_winner = 3'd1;
        else if (rot_tok[2]) rot_winner = 3'd2;
        else if (rot_tok[3]) rot_winner = 3'd3;
        else if (rot_tok[4]) rot_winner = 3'd4;
        else                 rot_winner = 3'd5;
        rot_possible = (rot_winner < 3'd5);
    end

    logic [5:0] rot_final_col, rot_final_row;
    always_comb begin
        case (rot_winner)
            3'd0: begin rot_final_col=rot_tcol[0]; rot_final_row=rot_trow[0]; end
            3'd1: begin rot_final_col=rot_tcol[1]; rot_final_row=rot_trow[1]; end
            3'd2: begin rot_final_col=rot_tcol[2]; rot_final_row=rot_trow[2]; end
            3'd3: begin rot_final_col=rot_tcol[3]; rot_final_row=rot_trow[3]; end
            3'd4: begin rot_final_col=rot_tcol[4]; rot_final_row=rot_trow[4]; end
            default: begin rot_final_col=a_col; rot_final_row=a_row; end
        endcase
    end

    // =========================================================================
    // Combinational: lock piece into board
    // board_locked = board with active piece written in
    // =========================================================================
    logic [19:0][9:0][2:0] board_locked;
    always_comb begin
        logic [15:0] msk;
        logic signed [6:0] br, bc;
        integer r, c;

        board_locked = board;
        msk = a_mask;

        for (r = 0; r < 4; r++) begin
            for (c = 0; c < 4; c++) begin
                if (msk[15 - r*4 - c]) begin
                    br = $signed({a_row[5], a_row}) + 7'(r);
                    bc = $signed({a_col[5], a_col}) + 7'(c);
                    if (br >= 0 && br < 20 && bc >= 0 && bc < 10)
                        board_locked[br[4:0]][bc[3:0]] = a_type;
                end
            end
        end
    end

    // Combinational: lock from ghost position (for hard drop)
    logic [19:0][9:0][2:0] board_locked_hd;
    always_comb begin
        logic [15:0] msk;
        logic signed [6:0] br, bc;
        integer r, c;

        board_locked_hd = board;
        msk = a_mask;

        for (r = 0; r < 4; r++) begin
            for (c = 0; c < 4; c++) begin
                if (msk[15 - r*4 - c]) begin
                    br = $signed({ghost_r[5], ghost_r}) + 7'(r);
                    bc = $signed({a_col[5], a_col}) + 7'(c);
                    if (br >= 0 && br < 20 && bc >= 0 && bc < 10)
                        board_locked_hd[br[4:0]][bc[3:0]] = a_type;
                end
            end
        end
    end

    // =========================================================================
    // Combinational: detect complete rows
    // =========================================================================
    logic [19:0] compl_rows_from_locked;
    logic [2:0]  n_compl_from_locked;
    logic [19:0] compl_rows_from_locked_hd;
    logic [2:0]  n_compl_from_locked_hd;

    always_comb begin
        integer rr, cc;
        logic row_full;
        compl_rows_from_locked = '0;
        n_compl_from_locked    = 3'd0;
        for (rr = 0; rr < 20; rr++) begin
            row_full = 1'b1;
            for (cc = 0; cc < 10; cc++)
                if (board_locked[rr][cc] == 3'b0) row_full = 1'b0;
            if (row_full) begin
                compl_rows_from_locked[rr] = 1'b1;
                n_compl_from_locked++;
            end
        end
    end

    always_comb begin
        integer rr, cc;
        logic row_full;
        compl_rows_from_locked_hd = '0;
        n_compl_from_locked_hd    = 3'd0;
        for (rr = 0; rr < 20; rr++) begin
            row_full = 1'b1;
            for (cc = 0; cc < 10; cc++)
                if (board_locked_hd[rr][cc] == 3'b0) row_full = 1'b0;
            if (row_full) begin
                compl_rows_from_locked_hd[rr] = 1'b1;
                n_compl_from_locked_hd++;
            end
        end
    end

    // =========================================================================
    // Combinational: clear complete rows and shift down
    // =========================================================================
    function automatic [19:0][9:0][2:0] clear_rows(
        input logic [19:0][9:0][2:0] brd,
        input logic [19:0]           comp
    );
        // Two-pass algorithm with constant loop bounds for synthesis.
        // Pass 1: copy non-complete rows from bottom to top of result (bottom=row19).
        // Pass 2: zero the remaining top rows.
        integer rd, wr;
        // Initialize all rows to empty first (constant bound = 20)
        for (rd = 0; rd < 20; rd++)
            clear_rows[rd] = '0;
        wr = 19;
        // Shift non-complete rows downward (constant bound)
        for (rd = 19; rd >= 0; rd--) begin
            if (!comp[rd]) begin
                clear_rows[wr] = brd[rd];
                wr = wr - 1;
            end
        end
        // Rows 0..wr already zeroed in initialization pass above
    endfunction

    logic [19:0][9:0][2:0] board_cleared;
    assign board_cleared = clear_rows(board, comp_rows);

    // =========================================================================
    // DAS: want_left / want_right pulses
    // =========================================================================
    // These are combinational based on button state and DAS counter
    logic want_left, want_right;
    assign want_left  = btn_left_pulse ||
                        (btn_left_level && !btn_left_pulse && das_l_cnt == 27'd0);
    assign want_right = btn_right_pulse ||
                        (btn_right_level && !btn_right_pulse && das_r_cnt == 27'd0);

    // Soft drop active: btn_down_level held and not hard drop mode
    logic soft_drop_active;
    assign soft_drop_active = btn_down_level && !sw_hard_drop;

    // Effective gravity interval
    logic [26:0] eff_grav;
    assign eff_grav = soft_drop_active ? 27'(SOFT_DROP_INT) : grav_int(level_r);

    // =========================================================================
    // Hard-drop row difference
    // =========================================================================
    logic [5:0] hd_drop_rows;
    assign hd_drop_rows = 6'(ghost_r) - 6'(a_row);

    // =========================================================================
    // Main sequential logic
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_TITLE;
            board         <= '0;
            a_type        <= 3'd0;
            a_rot         <= 2'd0;
            a_col         <= 6'd3;
            a_row         <= 6'd0;
            score_r       <= 32'd0;
            level_r       <= 7'd1;
            lines_r       <= 16'd0;
            grav_cnt      <= 27'd0;
            lock_cnt      <= 27'd0;
            lock_rst_cnt  <= 4'd0;
            in_lock       <= 1'b0;
            das_l_cnt     <= 27'(DAS_INITIAL);
            das_r_cnt     <= 27'(DAS_INITIAL);
            anim_cnt      <= 25'd0;
            anim_phase    <= 3'd0;
            go_cnt        <= 28'd0;
            go_unlocked   <= 1'b0;
            comp_rows     <= 20'd0;
            n_comp        <= 3'd0;
            flash_active  <= 1'b0;
            flash_toggle  <= 1'b0;
            uart_trigger  <= 1'b0;
            snd_move      <= 1'b0;
            snd_rotate    <= 1'b0;
            snd_lock      <= 1'b0;
            snd_line      <= 1'b0;
            snd_tetris    <= 1'b0;
            snd_hard_drop <= 1'b0;
            snd_game_over <= 1'b0;
        end else begin
            // Default: clear all one-cycle pulses
            uart_trigger  <= 1'b0;
            snd_move      <= 1'b0;
            snd_rotate    <= 1'b0;
            snd_lock      <= 1'b0;
            snd_line      <= 1'b0;
            snd_tetris    <= 1'b0;
            snd_hard_drop <= 1'b0;
            snd_game_over <= 1'b0;

            // SW[15] master reset (any state)
            if (sw_reset) begin
                state        <= ST_TITLE;
                board        <= '0;
                a_type       <= 3'd0;
                score_r      <= 32'd0;
                level_r      <= 7'd1;
                lines_r      <= 16'd0;
                in_lock      <= 1'b0;
                flash_active <= 1'b0;
                uart_trigger <= 1'b1;
            end else begin

            case (state)

            // =================================================================
            ST_TITLE: begin
                flash_active <= 1'b0;
                a_type       <= 3'd0;
                if (btn_center_pulse) begin
                    board        <= '0;
                    score_r      <= 32'd0;
                    level_r      <= 7'd1;
                    lines_r      <= 16'd0;
                    in_lock      <= 1'b0;
                    state        <= ST_SPAWN;
                end
            end

            // =================================================================
            // ST_SPAWN: place next piece on board, check for immediate collision
            // =================================================================
            ST_SPAWN: begin
                a_type       <= nxt_type;
                a_rot        <= 2'd0;
                a_col        <= 6'd3;
                a_row        <= 6'd0;
                in_lock      <= 1'b0;
                lock_rst_cnt <= 4'd0;

                if (coll_check(nxt_type, 2'd0, 6'd3, 6'd0, board)) begin
                    // Spawn collision → game over
                    state         <= ST_GAMEOVER;
                    go_cnt        <= 28'd0;
                    go_unlocked   <= 1'b0;
                    snd_game_over <= 1'b1;
                    uart_trigger  <= 1'b1;
                end else begin
                    grav_cnt     <= grav_int(level_r);
                    state        <= ST_PLAYING;
                    uart_trigger <= 1'b1;
                end
            end

            // =================================================================
            ST_PLAYING: begin
                flash_active <= 1'b0;

                // Pause
                if (btn_center_pulse) begin
                    state        <= ST_PAUSED;
                    uart_trigger <= 1'b1;
                end else begin

                // ---------- Hard drop ----------
                if (btn_down_pulse && sw_hard_drop) begin
                    // Add 2 pts per row
                    score_r <= score_r + {26'b0, hd_drop_rows} * 32'd2;
                    // Lock at ghost position
                    board        <= board_locked_hd;
                    snd_hard_drop<= 1'b1;
                    snd_lock     <= 1'b1;
                    comp_rows    <= compl_rows_from_locked_hd;
                    n_comp       <= n_compl_from_locked_hd;
                    a_type       <= 3'd0;
                    in_lock      <= 1'b0;
                    if (|compl_rows_from_locked_hd) begin
                        anim_cnt     <= 25'(ANIM_FLASH);
                        anim_phase   <= 3'd0;
                        flash_active <= 1'b1;
                        flash_toggle <= 1'b0;
                        state        <= ST_LINE_ANIM;
                    end else begin
                        state        <= ST_SPAWN;
                        uart_trigger <= 1'b1;
                    end
                end else begin

                // ---------- Gravity ----------
                if (grav_cnt == 27'd0) begin
                    if (!coll_below) begin
                        // Fall one row
                        if (soft_drop_active) score_r <= score_r + 32'd1;
                        a_row        <= 6'(a_row) + 6'd1;
                        grav_cnt     <= eff_grav;
                        in_lock      <= 1'b0;
                        uart_trigger <= 1'b1;
                    end else begin
                        // Can't fall → start lock delay if not already
                        grav_cnt <= eff_grav;
                        if (!in_lock) begin
                            in_lock      <= 1'b1;
                            lock_cnt     <= 27'(LOCK_DELAY);
                            lock_rst_cnt <= 4'd0;
                        end
                    end
                end else begin
                    grav_cnt <= grav_cnt - 27'd1;
                end

                // ---------- Lock delay ----------
                if (in_lock) begin
                    if (lock_cnt == 27'd0) begin
                        // Lock piece
                        board        <= board_locked;
                        snd_lock     <= 1'b1;
                        comp_rows    <= compl_rows_from_locked;
                        n_comp       <= n_compl_from_locked;
                        a_type       <= 3'd0;
                        in_lock      <= 1'b0;
                        if (|compl_rows_from_locked) begin
                            anim_cnt     <= 25'(ANIM_FLASH);
                            anim_phase   <= 3'd0;
                            flash_active <= 1'b1;
                            flash_toggle <= 1'b0;
                            state        <= ST_LINE_ANIM;
                        end else begin
                            state        <= ST_SPAWN;
                            uart_trigger <= 1'b1;
                        end
                    end else begin
                        lock_cnt <= lock_cnt - 27'd1;
                    end
                end

                // ---------- Left / Right movement ----------
                // DAS counters
                if (btn_left_level) begin
                    if (btn_left_pulse)
                        das_l_cnt <= 27'(DAS_INITIAL);
                    else if (das_l_cnt == 27'd0)
                        das_l_cnt <= 27'(DAS_REPEAT);
                    else
                        das_l_cnt <= das_l_cnt - 27'd1;
                end else begin
                    das_l_cnt <= 27'(DAS_INITIAL);
                end

                if (btn_right_level) begin
                    if (btn_right_pulse)
                        das_r_cnt <= 27'(DAS_INITIAL);
                    else if (das_r_cnt == 27'd0)
                        das_r_cnt <= 27'(DAS_REPEAT);
                    else
                        das_r_cnt <= das_r_cnt - 27'd1;
                end else begin
                    das_r_cnt <= 27'(DAS_INITIAL);
                end

                // Execute left move
                if (want_left && !coll_left) begin
                    a_col        <= 6'(a_col) - 6'd1;
                    snd_move     <= 1'b1;
                    uart_trigger <= 1'b1;
                    if (in_lock && lock_rst_cnt < 4'd15) begin
                        lock_cnt     <= 27'(LOCK_DELAY);
                        lock_rst_cnt <= lock_rst_cnt + 4'd1;
                    end
                end

                // Execute right move (only if not moving left this cycle)
                if (want_right && !want_left && !coll_right) begin
                    a_col        <= 6'(a_col) + 6'd1;
                    snd_move     <= 1'b1;
                    uart_trigger <= 1'b1;
                    if (in_lock && lock_rst_cnt < 4'd15) begin
                        lock_cnt     <= 27'(LOCK_DELAY);
                        lock_rst_cnt <= lock_rst_cnt + 4'd1;
                    end
                end

                // ---------- Rotation ----------
                if (btn_rotate_pulse && a_type != 3'd2 && rot_possible) begin
                    a_rot        <= new_rot;
                    a_col        <= rot_final_col;
                    a_row        <= rot_final_row;
                    snd_rotate   <= 1'b1;
                    uart_trigger <= 1'b1;
                    if (in_lock && lock_rst_cnt < 4'd15) begin
                        lock_cnt     <= 27'(LOCK_DELAY);
                        lock_rst_cnt <= lock_rst_cnt + 4'd1;
                    end
                end

                end // not hard drop
                end // not pausing
            end // ST_PLAYING

            // =================================================================
            ST_LINE_ANIM: begin
                if (anim_cnt == 25'd0) begin
                    anim_phase   <= anim_phase + 3'd1;
                    flash_toggle <= ~flash_toggle;
                    anim_cnt     <= 25'(ANIM_FLASH);
                    uart_trigger <= 1'b1;

                    if (anim_phase == (ANIM_STEPS - 3'd1)) begin
                        // Animation done: clear rows, update stats
                        board        <= board_cleared;
                        flash_active <= 1'b0;
                        lines_r      <= lines_r + {13'b0, n_comp};
                        score_r      <= score_r + calc_score(n_comp, level_r);

                        // Level up every 10 lines
                        if (((lines_r + {13'b0, n_comp}) / 16'd10) >
                             (lines_r / 16'd10) && level_r < 7'd99)
                            level_r <= level_r + 7'd1;

                        if (n_comp == 3'd4) snd_tetris <= 1'b1;
                        else                snd_line   <= 1'b1;

                        state        <= ST_SPAWN;
                        uart_trigger <= 1'b1;
                    end
                end else begin
                    anim_cnt <= anim_cnt - 25'd1;
                end
            end

            // =================================================================
            ST_PAUSED: begin
                if (btn_center_pulse) begin
                    grav_cnt     <= grav_int(level_r);
                    state        <= ST_PLAYING;
                    uart_trigger <= 1'b1;
                end
            end

            // =================================================================
            ST_GAMEOVER: begin
                if (!go_unlocked) begin
                    if (go_cnt == 28'(GAMEOVER_LOCK))
                        go_unlocked <= 1'b1;
                    else
                        go_cnt <= go_cnt + 28'd1;
                end else if (btn_center_pulse) begin
                    state        <= ST_TITLE;
                    board        <= '0;
                    a_type       <= 3'd0;
                    go_cnt       <= 28'd0;
                    go_unlocked  <= 1'b0;
                    uart_trigger <= 1'b1;
                end
            end

            default: state <= ST_TITLE;

            endcase
            end // not sw_reset
        end
    end

    // =========================================================================
    // Output assignments
    // =========================================================================
    always_comb begin
        case (state)
            ST_TITLE:                        game_state = 2'd0;
            ST_SPAWN, ST_PLAYING,
            ST_LINE_ANIM:                    game_state = 2'd1;
            ST_PAUSED:                       game_state = 2'd2;
            ST_GAMEOVER:                     game_state = 2'd3;
            default:                         game_state = 2'd0;
        endcase
    end

    assign board_out   = board;
    assign active_type = (state == ST_PLAYING || state == ST_PAUSED) ?
                          a_type : 3'd0;
    assign active_rot  = a_rot;
    assign active_col  = a_col;
    assign active_row  = a_row;
    assign next_type   = nxt_type;
    assign ghost_row   = ghost_r;
    assign score       = score_r;
    assign level       = level_r;
    assign lines       = lines_r;

endmodule
