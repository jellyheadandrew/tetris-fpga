//=============================================================================
// tb_top.sv — Comprehensive Testbench for Tetris FPGA
// Module: tb_top (required by xelab tb_top -s sim_snapshot)
// No timescale directive — xelab --timescale 1ns/1ps applies globally
// No `include directives
//=============================================================================
module tb_top;

    //=========================================================================
    // 100 MHz clock
    //=========================================================================
    logic clk = 0;
    always #5 clk = ~clk;

    //=========================================================================
    // Global pass/fail counters
    //=========================================================================
    int pass_cnt = 0;
    int fail_cnt = 0;

    //=========================================================================
    // Timeout watchdog: 10 ms
    //=========================================================================
    initial begin
        #10_000_000;
        $display("TIMEOUT");
        $finish;
    end

    //=========================================================================
    // Test 1: piece_rom — all 28 bitmasks
    //=========================================================================
    logic [2:0]  rom_type;
    logic [1:0]  rom_rot;
    logic [15:0] rom_mask;

    piece_rom u_piece_rom (
        .piece_type (rom_type),
        .rotation   (rom_rot),
        .bitmask    (rom_mask)
    );

    task automatic test_piece_rom();
        int lf = 0;
        logic [7:0] idx;

        // I-piece
        rom_type=3'd1; rom_rot=2'd0; #1;
        if (rom_mask!==16'h0F00) begin $display("FAIL: piece_rom - I0 exp=0F00 got=%04h",rom_mask); fail_cnt++; lf++; end
        rom_rot=2'd1; #1;
        if (rom_mask!==16'h2222) begin $display("FAIL: piece_rom - I1 exp=2222 got=%04h",rom_mask); fail_cnt++; lf++; end
        rom_rot=2'd2; #1;
        if (rom_mask!==16'h00F0) begin $display("FAIL: piece_rom - I2 exp=00F0 got=%04h",rom_mask); fail_cnt++; lf++; end
        rom_rot=2'd3; #1;
        if (rom_mask!==16'h4444) begin $display("FAIL: piece_rom - I3 exp=4444 got=%04h",rom_mask); fail_cnt++; lf++; end

        // O-piece (all rotations identical)
        rom_type=3'd2;
        for (int r=0; r<4; r++) begin
            rom_rot=2'(r); #1;
            if (rom_mask!==16'h6600) begin $display("FAIL: piece_rom - O rot%0d exp=6600 got=%04h",r,rom_mask); fail_cnt++; lf++; end
        end

        // T-piece
        rom_type=3'd3;
        rom_rot=2'd0; #1; if (rom_mask!==16'h4E00) begin $display("FAIL: piece_rom - T0"); fail_cnt++; lf++; end
        rom_rot=2'd1; #1; if (rom_mask!==16'h4640) begin $display("FAIL: piece_rom - T1"); fail_cnt++; lf++; end
        rom_rot=2'd2; #1; if (rom_mask!==16'h0E40) begin $display("FAIL: piece_rom - T2"); fail_cnt++; lf++; end
        rom_rot=2'd3; #1; if (rom_mask!==16'h4C40) begin $display("FAIL: piece_rom - T3"); fail_cnt++; lf++; end

        // S-piece
        rom_type=3'd4;
        rom_rot=2'd0; #1; if (rom_mask!==16'h6C00) begin $display("FAIL: piece_rom - S0"); fail_cnt++; lf++; end
        rom_rot=2'd1; #1; if (rom_mask!==16'h4620) begin $display("FAIL: piece_rom - S1"); fail_cnt++; lf++; end
        rom_rot=2'd2; #1; if (rom_mask!==16'h06C0) begin $display("FAIL: piece_rom - S2"); fail_cnt++; lf++; end
        rom_rot=2'd3; #1; if (rom_mask!==16'h8C40) begin $display("FAIL: piece_rom - S3"); fail_cnt++; lf++; end

        // Z-piece
        rom_type=3'd5;
        rom_rot=2'd0; #1; if (rom_mask!==16'hC600) begin $display("FAIL: piece_rom - Z0"); fail_cnt++; lf++; end
        rom_rot=2'd1; #1; if (rom_mask!==16'h2640) begin $display("FAIL: piece_rom - Z1"); fail_cnt++; lf++; end
        rom_rot=2'd2; #1; if (rom_mask!==16'h0C60) begin $display("FAIL: piece_rom - Z2"); fail_cnt++; lf++; end
        rom_rot=2'd3; #1; if (rom_mask!==16'h4C80) begin $display("FAIL: piece_rom - Z3"); fail_cnt++; lf++; end

        // J-piece
        rom_type=3'd6;
        rom_rot=2'd0; #1; if (rom_mask!==16'h8E00) begin $display("FAIL: piece_rom - J0"); fail_cnt++; lf++; end
        rom_rot=2'd1; #1; if (rom_mask!==16'h6440) begin $display("FAIL: piece_rom - J1"); fail_cnt++; lf++; end
        rom_rot=2'd2; #1; if (rom_mask!==16'h0E20) begin $display("FAIL: piece_rom - J2"); fail_cnt++; lf++; end
        rom_rot=2'd3; #1; if (rom_mask!==16'h44C0) begin $display("FAIL: piece_rom - J3"); fail_cnt++; lf++; end

        // L-piece
        rom_type=3'd7;
        rom_rot=2'd0; #1; if (rom_mask!==16'h2E00) begin $display("FAIL: piece_rom - L0"); fail_cnt++; lf++; end
        rom_rot=2'd1; #1; if (rom_mask!==16'h4460) begin $display("FAIL: piece_rom - L1"); fail_cnt++; lf++; end
        rom_rot=2'd2; #1; if (rom_mask!==16'h08E0) begin $display("FAIL: piece_rom - L2"); fail_cnt++; lf++; end
        rom_rot=2'd3; #1; if (rom_mask!==16'h6220) begin $display("FAIL: piece_rom - L3"); fail_cnt++; lf++; end

        // Default (invalid type 0)
        rom_type=3'd0; rom_rot=2'd0; #1;
        if (rom_mask!==16'h0000) begin $display("FAIL: piece_rom - default nonzero"); fail_cnt++; lf++; end

        if (lf==0) begin $display("PASS: piece_rom"); pass_cnt++; end
    endtask

    //=========================================================================
    // Test 2: collision_checker
    //=========================================================================
    logic [15:0]           cc_mask;
    logic [5:0]            cc_col, cc_row;
    logic [19:0][9:0][2:0] cc_board;
    logic                  cc_collides;

    collision_checker u_cc (
        .bitmask   (cc_mask),
        .piece_col (cc_col),
        .piece_row (cc_row),
        .board     (cc_board),
        .collides  (cc_collides)
    );

    task automatic test_collision_checker();
        int lf = 0;
        cc_board = '0;

        // Valid center, empty board → no collision
        cc_mask=16'h0F00; cc_col=6'd3; cc_row=6'd5; #1;
        if (cc_collides!==1'b0) begin $display("FAIL: collision_checker - valid pos collides"); fail_cnt++; lf++; end

        // Left wall: piece at col=-1 (6'b111111)
        cc_col=6'b111111; cc_row=6'd5; #1;
        if (cc_collides!==1'b1) begin $display("FAIL: collision_checker - left wall miss"); fail_cnt++; lf++; end

        // Right wall: I-piece at col=7, row1 reaches col10
        cc_col=6'd7; cc_row=6'd5; #1;
        if (cc_collides!==1'b1) begin $display("FAIL: collision_checker - right wall miss"); fail_cnt++; lf++; end

        // Right edge OK: col=6 → row1 at cols 6,7,8,9 (all valid)
        cc_col=6'd6; cc_row=6'd5; #1;
        if (cc_collides!==1'b0) begin $display("FAIL: collision_checker - col6 false collision"); fail_cnt++; lf++; end

        // Floor OK: I-piece row=18, row1 at 19 (valid)
        cc_col=6'd3; cc_row=6'd18; #1;
        if (cc_collides!==1'b0) begin $display("FAIL: collision_checker - row18 should not collide"); fail_cnt++; lf++; end

        // Floor: I-piece row=19, row1 at 20 → out
        cc_row=6'd19; #1;
        if (cc_collides!==1'b1) begin $display("FAIL: collision_checker - floor miss at row19"); fail_cnt++; lf++; end

        // Cell collision: place piece at board[10][5]
        cc_board[10][5] = 3'd1;
        cc_mask=16'h0F00; cc_col=6'd3; cc_row=6'd9; #1; // row1=10, cols 3-6 include col5
        if (cc_collides!==1'b1) begin $display("FAIL: collision_checker - cell collision miss"); fail_cnt++; lf++; end

        // One row above: no overlap
        cc_row=6'd8; #1;
        if (cc_collides!==1'b0) begin $display("FAIL: collision_checker - false pos above cell"); fail_cnt++; lf++; end

        // Clear board, negative piece_row (-1): row0 is valid (no collision)
        cc_board = '0;
        cc_mask=16'h0F00; cc_col=6'd3; cc_row=6'b111111; #1;
        if (cc_collides!==1'b0) begin $display("FAIL: collision_checker - neg row false collision"); fail_cnt++; lf++; end

        if (lf==0) begin $display("PASS: collision_checker"); pass_cnt++; end
    endtask

    //=========================================================================
    // Test 3: btn_debounce — COUNT_MAX=10 (CLK_FREQ=10000, DEBOUNCE_MS=1)
    //=========================================================================
    logic db_rst_n, db_in, db_level, db_pulse;

    btn_debounce #(.CLK_FREQ(10_000), .DEBOUNCE_MS(1)) u_db (
        .clk      (clk),
        .rst_n    (db_rst_n),
        .btn_in   (db_in),
        .btn_level(db_level),
        .btn_pulse(db_pulse)
    );

    task automatic test_btn_debounce();
        int lf = 0;
        db_rst_n=0; db_in=0;
        repeat(2) @(posedge clk);
        db_rst_n=1;
        @(posedge clk); #1;

        // Initial: level should be 0
        if (db_level!==1'b0) begin $display("FAIL: btn_debounce - init level not 0"); fail_cnt++; lf++; end

        // Press but release before full debounce (5 < COUNT_MAX=10)
        db_in=1;
        repeat(5) @(posedge clk); #1;
        if (db_level!==1'b0) begin $display("FAIL: btn_debounce - premature debounce"); fail_cnt++; lf++; end
        db_in=0; // glitch — release resets counter
        repeat(2) @(posedge clk);

        // Hold for 12 cycles > COUNT_MAX=10 → should debounce to 1
        db_in=1;
        repeat(12) @(posedge clk); #1;
        if (db_level!==1'b1) begin $display("FAIL: btn_debounce - no debounce after hold"); fail_cnt++; lf++; end

        // Release and debounce to 0
        db_in=0;
        repeat(12) @(posedge clk); #1;
        if (db_level!==1'b0) begin $display("FAIL: btn_debounce - level not 0 after release"); fail_cnt++; lf++; end

        // Re-press: level should come back to 1
        db_in=1;
        repeat(12) @(posedge clk); #1;
        if (db_level!==1'b1) begin $display("FAIL: btn_debounce - level not 1 on re-press"); fail_cnt++; lf++; end

        db_rst_n=0;
        if (lf==0) begin $display("PASS: btn_debounce"); pass_cnt++; end
    endtask

    //=========================================================================
    // Test 4: lfsr_rng
    //=========================================================================
    logic        lfsr_rst_n;
    logic        lfsr_en_sig;
    logic [15:0] lfsr_raw;
    logic [2:0]  lfsr_piece_out;
    logic        lfsr_valid_out;

    lfsr_rng u_lfsr (
        .clk        (clk),
        .rst_n      (lfsr_rst_n),
        .en         (lfsr_en_sig),
        .lfsr_out   (lfsr_raw),
        .piece_out  (lfsr_piece_out),
        .piece_valid(lfsr_valid_out)
    );

    task automatic test_lfsr_rng();
        int lf = 0;
        logic [15:0] start_val;
        int valid_cnt;

        lfsr_rst_n=0; lfsr_en_sig=0;
        repeat(2) @(posedge clk);
        lfsr_rst_n=1;
        @(posedge clk); #1;

        // Initial value after reset must be ACE1
        if (lfsr_raw!==16'hACE1) begin
            $display("FAIL: lfsr_rng - init val=%04h exp=ACE1", lfsr_raw);
            fail_cnt++; lf++;
        end

        // Enable and run 200 cycles
        lfsr_en_sig=1;
        start_val = lfsr_raw;
        valid_cnt = 0;
        for (int i=0; i<200; i++) begin
            @(posedge clk); #1;
            if (lfsr_raw===16'h0000) begin
                $display("FAIL: lfsr_rng - stuck at zero at cycle %0d", i);
                fail_cnt++; lf++;
            end
            if (lfsr_valid_out) begin
                if (lfsr_piece_out<1 || lfsr_piece_out>7) begin
                    $display("FAIL: lfsr_rng - invalid piece %0d", lfsr_piece_out);
                    fail_cnt++; lf++;
                end
                valid_cnt++;
            end
        end

        if (valid_cnt==0) begin $display("FAIL: lfsr_rng - no valid pieces in 200 cycles"); fail_cnt++; lf++; end
        if (lfsr_raw===start_val) begin $display("FAIL: lfsr_rng - returned to start in 200 cycles"); fail_cnt++; lf++; end

        lfsr_en_sig=0;
        if (lf==0) begin $display("PASS: lfsr_rng"); pass_cnt++; end
    endtask

    //=========================================================================
    // Test 5: uart_tx — CLKS_PER_BIT=10 (CLK_FREQ=1152000, BAUD=115200)
    //=========================================================================
    logic       utx_rst_n;
    logic [7:0] utx_data;
    logic       utx_start_sig;
    logic       utx_out;
    logic       utx_busy;

    uart_tx #(.CLK_FREQ(1_152_000), .BAUD(115_200)) u_utx (
        .clk     (clk),
        .rst_n   (utx_rst_n),
        .tx_data (utx_data),
        .tx_start(utx_start_sig),
        .tx_out  (utx_out),
        .tx_busy (utx_busy)
    );

    task automatic test_uart_tx();
        int lf = 0;
        logic [7:0] tbyte;
        tbyte = 8'hA5; // 1010_0101

        utx_rst_n=0; utx_data=8'h00; utx_start_sig=0;
        repeat(2) @(posedge clk);
        utx_rst_n=1;
        @(posedge clk); #1;

        // Idle checks
        if (utx_out!==1'b1) begin $display("FAIL: uart_tx - idle tx_out not 1"); fail_cnt++; lf++; end
        if (utx_busy!==1'b0) begin $display("FAIL: uart_tx - idle busy"); fail_cnt++; lf++; end

        // Send 0xA5 — drive start signal AFTER a sync posedge+#1 so it is
        // stable for the full period before the posedge that samples it,
        // eliminating any Active-region race between initial and always_ff.
        utx_data = tbyte;
        @(posedge clk); #1;   // sync: arrive at posedge+1 ns
        utx_start_sig=1;      // set between edges → stable for next posedge
        @(posedge clk); #1;   // P1: IDLE samples tx_start=1 → state←START
        utx_start_sig=0;      // clear after DUT captured it
        @(posedge clk); #1;   // P2: START runs → tx_out←0, clk_cnt←1

        if (utx_busy!==1'b1) begin $display("FAIL: uart_tx - not busy after start"); fail_cnt++; lf++; end
        if (utx_out!==1'b0)  begin $display("FAIL: uart_tx - start bit not 0"); fail_cnt++; lf++; end

        // Consume rest of start bit (CLKS_PER_BIT=10, already at clk_cnt=1)
        // clk_cnt counts: 1→2→...→9 (8 more cycles), then at clk_cnt=9→DATA
        repeat(9) @(posedge clk);
        // State just transitioned to DATA; next posedge drives bit 0
        @(posedge clk); #1;   // DATA: bit_idx=0, tx_out=tbyte[0]
        if (utx_out!==tbyte[0]) begin $display("FAIL: uart_tx - bit0 exp=%0b got=%0b",tbyte[0],utx_out); fail_cnt++; lf++; end

        // Sample bits 1-7 (each 10 cycles apart)
        for (int b=1; b<8; b++) begin
            repeat(10) @(posedge clk); #1;
            if (utx_out!==tbyte[b]) begin
                $display("FAIL: uart_tx - bit%0d exp=%0b got=%0b", b, tbyte[b], utx_out);
                fail_cnt++; lf++;
            end
        end

        // Stop bit: 10 cycles after bit7
        repeat(10) @(posedge clk); #1;
        if (utx_out!==1'b1) begin $display("FAIL: uart_tx - stop bit not 1"); fail_cnt++; lf++; end

        // Return to idle: 10 more cycles
        repeat(10) @(posedge clk); #1;
        if (utx_busy!==1'b0) begin $display("FAIL: uart_tx - still busy after stop"); fail_cnt++; lf++; end

        utx_rst_n=0;
        if (lf==0) begin $display("PASS: uart_tx"); pass_cnt++; end
    endtask

    //=========================================================================
    // Test 6: seven_seg_driver — MUX_DIV=10 (CLK_FREQ=80000)
    //=========================================================================
    logic        ssd_rst_n;
    logic [1:0]  ssd_gs;
    logic [31:0] ssd_score;
    logic [6:0]  ssd_level;
    logic [6:0]  ssd_seg;
    logic        ssd_dp;
    logic [7:0]  ssd_an;

    seven_seg_driver #(.CLK_FREQ(80_000)) u_ssd (
        .clk       (clk),
        .rst_n     (ssd_rst_n),
        .game_state(ssd_gs),
        .score     (ssd_score),
        .level     (ssd_level),
        .SEG       (ssd_seg),
        .DP        (ssd_dp),
        .AN        (ssd_an)
    );

    task automatic test_seven_seg_driver();
        int lf = 0;
        int zero_cnt;

        ssd_rst_n=0; ssd_gs=2'd0; ssd_score=32'd0; ssd_level=7'd1;
        repeat(2) @(posedge clk);
        ssd_rst_n=1;
        @(posedge clk); #1;

        // TITLE: all anodes off (8'hFF, active-low)
        if (ssd_an!==8'hFF) begin
            $display("FAIL: seven_seg - TITLE AN not FF (got %02h)", ssd_an);
            fail_cnt++; lf++;
        end

        // Switch to PLAYING, set score=1234, level=5
        ssd_gs=2'd1; ssd_score=32'd1234; ssd_level=7'd5;

        // Wait >1 full mux cycle (8 digits × 10 cycles = 80 cycles)
        repeat(100) @(posedge clk); #1;

        // At least one anode active
        if (ssd_an===8'hFF) begin
            $display("FAIL: seven_seg - PLAYING all anodes off");
            fail_cnt++; lf++;
        end

        // Exactly one anode low (active-low multiplexed display)
        zero_cnt=0;
        for (int b=0; b<8; b++) if (ssd_an[b]==1'b0) zero_cnt++;
        if (zero_cnt!==1) begin
            $display("FAIL: seven_seg - not exactly 1 anode active (cnt=%0d)", zero_cnt);
            fail_cnt++; lf++;
        end

        // Verify SEG not all-off while digit active
        if (zero_cnt==1 && ssd_seg===7'b1111111) begin
            $display("FAIL: seven_seg - anode active but all segments off");
            fail_cnt++; lf++;
        end

        // GAME_OVER still shows display
        ssd_gs=2'd3;
        repeat(20) @(posedge clk); #1;
        if (ssd_an===8'hFF) begin
            $display("FAIL: seven_seg - GAMEOVER all anodes off");
            fail_cnt++; lf++;
        end

        ssd_rst_n=0;
        if (lf==0) begin $display("PASS: seven_seg_driver"); pass_cnt++; end
    endtask

    //=========================================================================
    // Test 7: audio_engine — CLK_FREQ=1_000_000 for fast PWM toggling
    //   freq_to_half(800) = 1_000_000/2/800 = 625 cycles
    //=========================================================================
    logic ae_rst_n;
    logic ae_move, ae_rotate, ae_lock, ae_line, ae_tetris, ae_hd, ae_go;
    logic ae_pwm, ae_sd;

    audio_engine #(.CLK_FREQ(1_000_000)) u_ae (
        .clk          (clk),
        .rst_n        (ae_rst_n),
        .snd_move     (ae_move),
        .snd_rotate   (ae_rotate),
        .snd_lock     (ae_lock),
        .snd_line     (ae_line),
        .snd_tetris   (ae_tetris),
        .snd_hard_drop(ae_hd),
        .snd_game_over(ae_go),
        .AUD_PWM      (ae_pwm),
        .AUD_SD       (ae_sd)
    );

    task automatic test_audio_engine();
        int lf = 0;
        logic first_pwm;
        int toggled;

        ae_rst_n=0;
        ae_move=0; ae_rotate=0; ae_lock=0;
        ae_line=0; ae_tetris=0; ae_hd=0; ae_go=0;
        repeat(2) @(posedge clk);
        ae_rst_n=1;
        @(posedge clk); #1;

        // AUD_SD must always be high (amplifier always enabled)
        if (ae_sd!==1'b1) begin $display("FAIL: audio_engine - AUD_SD not 1 at reset"); fail_cnt++; lf++; end

        // Trigger move sound (800 Hz, CLK_FREQ=1 MHz → freq_to_half=625 cycles)
        // Drive AFTER sync posedge to guarantee DUT captures the pulse.
        @(posedge clk); #1;   // sync
        ae_move=1;
        @(posedge clk); #1;   // DUT captures snd_move=1: loads dur_cnt=30000, tone_cnt=625
        ae_move=0;
        @(posedge clk); #1;   // first playing cycle: tone_cnt 625→624
        if (ae_sd!==1'b1) begin $display("FAIL: audio_engine - AUD_SD dropped after trigger"); fail_cnt++; lf++; end

        // tone_cnt counts 625→0 over 626 cycles then wave toggles; 700-cycle
        // window is sufficient to observe at least one toggle.
        first_pwm = ae_pwm;
        toggled = 0;
        for (int i=0; i<700; i++) begin
            @(posedge clk); #1;
            if (ae_pwm !== first_pwm) toggled = 1;
        end
        if (!toggled) begin $display("FAIL: audio_engine - PWM not toggling in 700 cycles"); fail_cnt++; lf++; end

        // Trigger rotate sound (1200 Hz → half=416 cycles): drive after sync posedge
        @(posedge clk); #1;   // sync
        ae_rotate=1;
        @(posedge clk); #1;   // DUT captures snd_rotate=1
        ae_rotate=0;
        @(posedge clk); #1;   // first playing cycle
        first_pwm = ae_pwm;
        toggled = 0;
        for (int i=0; i<500; i++) begin
            @(posedge clk); #1;
            if (ae_pwm !== first_pwm) toggled = 1;
        end
        if (!toggled) begin $display("FAIL: audio_engine - rotate PWM not toggling"); fail_cnt++; lf++; end

        ae_rst_n=0;
        if (lf==0) begin $display("PASS: audio_engine"); pass_cnt++; end
    endtask

    //=========================================================================
    // Test 8: tetris_engine — state transitions, spawn, hard drop, SW reset
    //=========================================================================
    logic        eng_rst_n;
    logic        eng_bl, eng_br, eng_brot, eng_bd, eng_bc;
    logic        eng_bll, eng_brl, eng_bdl;
    logic        eng_sw_hd, eng_sw_rst;
    logic [1:0]  eng_gs;
    logic [19:0][9:0][2:0] eng_board;
    logic [2:0]  eng_atype;
    logic [1:0]  eng_arot;
    logic [5:0]  eng_acol, eng_arow, eng_ghost;
    logic [2:0]  eng_next;
    logic [31:0] eng_score;
    logic [6:0]  eng_level;
    logic [15:0] eng_lines;
    logic        eng_fa, eng_ft, eng_utrig;
    logic        eng_sm, eng_sr, eng_sl, eng_sln, eng_st, eng_shd, eng_sgo;

    tetris_engine u_eng (
        .clk             (clk),
        .rst_n           (eng_rst_n),
        .btn_left_pulse  (eng_bl),
        .btn_right_pulse (eng_br),
        .btn_rotate_pulse(eng_brot),
        .btn_down_pulse  (eng_bd),
        .btn_center_pulse(eng_bc),
        .btn_left_level  (eng_bll),
        .btn_right_level (eng_brl),
        .btn_down_level  (eng_bdl),
        .sw_hard_drop    (eng_sw_hd),
        .sw_reset        (eng_sw_rst),
        .game_state      (eng_gs),
        .board_out       (eng_board),
        .active_type     (eng_atype),
        .active_rot      (eng_arot),
        .active_col      (eng_acol),
        .active_row      (eng_arow),
        .next_type       (eng_next),
        .ghost_row       (eng_ghost),
        .score           (eng_score),
        .level           (eng_level),
        .lines           (eng_lines),
        .flash_active    (eng_fa),
        .flash_toggle    (eng_ft),
        .uart_trigger    (eng_utrig),
        .snd_move        (eng_sm),
        .snd_rotate      (eng_sr),
        .snd_lock        (eng_sl),
        .snd_line        (eng_sln),
        .snd_tetris      (eng_st),
        .snd_hard_drop   (eng_shd),
        .snd_game_over   (eng_sgo)
    );

    task automatic test_tetris_engine();
        int lf = 0;
        int has_locked;

        eng_rst_n=0;
        eng_bl=0; eng_br=0; eng_brot=0; eng_bd=0; eng_bc=0;
        eng_bll=0; eng_brl=0; eng_bdl=0;
        eng_sw_hd=0; eng_sw_rst=0;
        repeat(3) @(posedge clk);
        eng_rst_n=1;
        @(posedge clk); #1;

        // Initial state: TITLE (game_state=0)
        if (eng_gs!==2'd0) begin $display("FAIL: tetris_engine - init state=%0d exp=TITLE(0)", eng_gs); fail_cnt++; lf++; end
        if (eng_score!==32'd0) begin $display("FAIL: tetris_engine - init score not 0"); fail_cnt++; lf++; end
        if (eng_level!==7'd1) begin $display("FAIL: tetris_engine - init level not 1"); fail_cnt++; lf++; end

        // Start game: drive btn_center_pulse AFTER sync posedge to guarantee capture
        @(posedge clk); #1;    // sync
        eng_bc=1;
        @(posedge clk); #1;    // DUT captures: ST_TITLE sees bc=1 → state←ST_SPAWN
        eng_bc=0;
        // ST_SPAWN runs next cycle → state←ST_PLAYING, a_type/col/row latched
        @(posedge clk); #1;
        if (eng_gs!==2'd1) begin $display("FAIL: tetris_engine - after start gs=%0d exp=1", eng_gs); fail_cnt++; lf++; end
        // One more cycle in ST_PLAYING
        @(posedge clk); #1;
        if (eng_gs!==2'd1) begin $display("FAIL: tetris_engine - PLAYING gs=%0d exp=1", eng_gs); fail_cnt++; lf++; end

        // Active type must be 1-7 in PLAYING
        if (eng_atype<3'd1 || eng_atype>3'd7) begin
            $display("FAIL: tetris_engine - active_type=%0d invalid", eng_atype);
            fail_cnt++; lf++;
        end

        // Piece spawns at col=3, row=0
        if (eng_acol!==6'd3) begin $display("FAIL: tetris_engine - spawn col=%0d exp=3", eng_acol); fail_cnt++; lf++; end
        if (eng_arow!==6'd0) begin $display("FAIL: tetris_engine - spawn row=%0d exp=0", eng_arow); fail_cnt++; lf++; end

        // Pause via btn_center (sync-drive pattern)
        @(posedge clk); #1;
        eng_bc=1;
        @(posedge clk); #1;    // ST_PLAYING sees bc=1 → state←ST_PAUSED
        eng_bc=0;
        @(posedge clk); #1;
        if (eng_gs!==2'd2) begin $display("FAIL: tetris_engine - PAUSED gs=%0d exp=2", eng_gs); fail_cnt++; lf++; end

        // Unpause
        @(posedge clk); #1;
        eng_bc=1;
        @(posedge clk); #1;    // ST_PAUSED sees bc=1 → state←ST_PLAYING
        eng_bc=0;
        @(posedge clk); #1;
        if (eng_gs!==2'd1) begin $display("FAIL: tetris_engine - UNPAUSE gs=%0d exp=1", eng_gs); fail_cnt++; lf++; end

        // Hard drop: enable sw_hard_drop, drive btn_down_pulse after sync
        eng_sw_hd=1;
        @(posedge clk); #1;
        eng_bd=1;
        @(posedge clk); #1;    // ST_PLAYING sees bd=1 AND sw_hard_drop=1 → lock at ghost, state←ST_SPAWN
        eng_bd=0;
        // ST_SPAWN→ST_PLAYING in next cycle; wait a few more to be safe
        repeat(3) @(posedge clk); #1;
        if (eng_gs!==2'd1) begin $display("FAIL: tetris_engine - after hd gs=%0d exp=1", eng_gs); fail_cnt++; lf++; end

        // Score should have increased (2 pts/row dropped)
        if (eng_score===32'd0) begin $display("FAIL: tetris_engine - score=0 after hard drop"); fail_cnt++; lf++; end

        // Board must have locked piece (some non-zero cell)
        has_locked = 0;
        for (int r=0; r<20; r++)
            for (int c=0; c<10; c++)
                if (eng_board[r][c]!=3'd0) has_locked = 1;
        if (!has_locked) begin $display("FAIL: tetris_engine - board empty after hard drop"); fail_cnt++; lf++; end

        // SW[15] master reset → back to TITLE (sync-drive pattern)
        @(posedge clk); #1;
        eng_sw_rst=1;
        @(posedge clk); #1;    // sw_reset=1 → state←ST_TITLE, score←0
        eng_sw_rst=0;
        @(posedge clk); #1;
        if (eng_gs!==2'd0) begin $display("FAIL: tetris_engine - SW reset gs=%0d exp=0", eng_gs); fail_cnt++; lf++; end
        if (eng_score!==32'd0) begin $display("FAIL: tetris_engine - SW reset score=%0d exp=0", eng_score); fail_cnt++; lf++; end

        // Start again and test move left
        @(posedge clk); #1;
        eng_bc=1;
        @(posedge clk); #1;    // ST_TITLE→ST_SPAWN
        eng_bc=0;
        @(posedge clk); #1;    // ST_SPAWN→ST_PLAYING
        @(posedge clk); #1;    // in ST_PLAYING
        begin
            logic [5:0] orig_col;
            orig_col = eng_acol;
            @(posedge clk); #1;
            eng_bl=1;
            @(posedge clk); #1;    // ST_PLAYING captures btn_left_pulse → a_col←a_col-1 (if room)
            eng_bl=0;
            @(posedge clk); #1;
            // Piece col should have moved left by 1, or stayed if at wall — informational only
            $display("INFO: tetris_engine - left move orig_col=%0d new_col=%0d", orig_col, eng_acol);
        end

        eng_rst_n=0;
        if (lf==0) begin $display("PASS: tetris_engine"); pass_cnt++; end
    endtask

    //=========================================================================
    // Test 9: uart_packet_builder — capture 216 bytes, verify header+checksum
    //=========================================================================
    logic        pb_rst_n;
    logic        pb_trigger;
    logic [1:0]  pb_gs;
    logic [19:0][9:0][2:0] pb_board;
    logic [2:0]  pb_atype;
    logic [1:0]  pb_arot;
    logic [5:0]  pb_acol, pb_arow, pb_ghost;
    logic [2:0]  pb_next;
    logic [31:0] pb_score;
    logic [6:0]  pb_level;
    logic [15:0] pb_lines;
    logic [7:0]  pb_txdata;
    logic        pb_txstart;
    logic        pb_txbusy;
    logic        pb_sending;

    // Busy signal: held low so the packet builder runs freely.
    // The DUT fires tx_start for each byte in a 2-cycle PB_SEND/PB_WAIT cadence;
    // the capture loop below catches every pulse within the 50 k-cycle budget.
    assign pb_txbusy = 1'b0;

    uart_packet_builder #(.CLK_FREQ(100_000_000), .BAUD(115_200)) u_pb (
        .clk        (clk),
        .rst_n      (pb_rst_n),
        .trigger    (pb_trigger),
        .game_state (pb_gs),
        .board      (pb_board),
        .active_type(pb_atype),
        .active_rot (pb_arot),
        .active_col (pb_acol),
        .active_row (pb_arow),
        .next_type  (pb_next),
        .ghost_row  (pb_ghost),
        .score      (pb_score),
        .level      (pb_level),
        .lines      (pb_lines),
        .tx_data    (pb_txdata),
        .tx_start   (pb_txstart),
        .tx_busy    (pb_txbusy),
        .sending    (pb_sending)
    );

    task automatic test_uart_packet_builder();
        int lf = 0;
        logic [7:0] captured [0:255];
        int pc;
        logic [7:0] xchk;
        int to_cnt;

        pb_rst_n=0; pb_trigger=0;
        pb_gs=2'd1;             // PLAYING
        pb_board='0;
        pb_atype=3'd3; pb_arot=2'd0;
        pb_acol=6'd3;  pb_arow=6'd0;
        pb_next=3'd2;  pb_ghost=6'd18;
        pb_score=32'd1234; pb_level=7'd1; pb_lines=16'd0;

        repeat(3) @(posedge clk);
        pb_rst_n=1;
        @(posedge clk); #1;

        // Fire trigger — sync-drive to guarantee DUT captures it
        @(posedge clk); #1;
        pb_trigger=1;
        @(posedge clk); #1;    // DUT captures trigger=1 → pb_state←PB_SEND
        pb_trigger=0;

        // Capture 216 bytes by monitoring pb_txstart pulses
        pc=0; to_cnt=0;
        while (pc < 216 && to_cnt < 50_000) begin
            @(posedge clk); #1;
            to_cnt++;
            if (pb_txstart) begin
                captured[pc] = pb_txdata;
                pc++;
            end
        end

        if (pc < 216) begin
            $display("FAIL: uart_packet_builder - only %0d/216 bytes received", pc);
            fail_cnt++; lf++;
        end else begin
            // Header = 0xAA
            if (captured[0]!==8'hAA) begin
                $display("FAIL: uart_packet_builder - hdr exp=AA got=%02h", captured[0]);
                fail_cnt++; lf++;
            end
            // State = 1 (PLAYING)
            if (captured[1]!==8'h01) begin
                $display("FAIL: uart_packet_builder - state exp=01 got=%02h", captured[1]);
                fail_cnt++; lf++;
            end
            // Score big-endian: 1234 = 0x000004D2
            if (captured[208]!==8'h00 || captured[209]!==8'h00 ||
                captured[210]!==8'h04 || captured[211]!==8'hD2) begin
                $display("FAIL: uart_packet_builder - score bytes: %02h %02h %02h %02h",
                         captured[208],captured[209],captured[210],captured[211]);
                fail_cnt++; lf++;
            end
            // Level byte
            if (captured[212]!==8'h01) begin
                $display("FAIL: uart_packet_builder - level exp=01 got=%02h", captured[212]);
                fail_cnt++; lf++;
            end
            // Checksum = XOR of bytes 1..214
            xchk = 8'h00;
            for (int i=1; i<=214; i++) xchk ^= captured[i];
            if (xchk !== captured[215]) begin
                $display("FAIL: uart_packet_builder - checksum exp=%02h got=%02h", xchk, captured[215]);
                fail_cnt++; lf++;
            end
        end

        pb_rst_n=0;
        if (lf==0) begin $display("PASS: uart_packet_builder"); pass_cnt++; end
    endtask

    //=========================================================================
    // PPM Frame Rendering — writes frame.ppm (160×320, P3 ASCII)
    // Each cell = 16×16 pixels (15×15 content + 1px grid border on right/bottom)
    //=========================================================================
    function automatic [23:0] piece_rgb(input [2:0] t);
        case (t)
            3'd0: piece_rgb = 24'h000000; // empty — black
            3'd1: piece_rgb = 24'h00FFFF; // I — cyan
            3'd2: piece_rgb = 24'hFFFF00; // O — yellow
            3'd3: piece_rgb = 24'hAA00FF; // T — purple
            3'd4: piece_rgb = 24'h00FF00; // S — green
            3'd5: piece_rgb = 24'hFF0000; // Z — red
            3'd6: piece_rgb = 24'h0000FF; // J — blue
            3'd7: piece_rgb = 24'hFF8000; // L — orange
            default: piece_rgb = 24'h000000;
        endcase
    endfunction

    task automatic render_ppm();
        integer fd;
        logic [19:0][9:0][2:0] demo_board;
        logic [2:0]  act_type;
        logic [1:0]  act_rot;
        int          act_col_i, act_row_i, ghost_row_i;
        logic [15:0] act_mask;
        logic [23:0] color;
        logic        is_active, is_ghost;
        int          abs_r, abs_c;

        // --- Build demo board ---
        demo_board = '0;
        // Row 19: rainbow bottom row
        for (int c=0; c<10; c++) demo_board[19][c] = 3'(1 + c % 7);
        // Row 18: partial
        for (int c=0; c<6; c++) demo_board[18][c] = 3'(7 - c % 7);
        // Scattered mid-board pieces
        demo_board[15][1]=3'd4; demo_board[15][2]=3'd4;
        demo_board[14][3]=3'd5; demo_board[14][4]=3'd5;
        demo_board[16][6]=3'd6; demo_board[16][7]=3'd6; demo_board[16][8]=3'd6;
        demo_board[13][0]=3'd3; demo_board[13][1]=3'd3; demo_board[12][1]=3'd3;

        // --- Active piece: T rot0 at (col=3, row=2) ---
        // mask 16'h4E00 => row0: col1; row1: col0,col1,col2
        act_type  = 3'd3;
        act_rot   = 2'd0;
        act_col_i = 3;
        act_row_i = 2;
        ghost_row_i = 12; // T-piece ghost near mid-board
        act_mask  = 16'h4E00;

        fd = $fopen("frame.ppm", "w");
        if (fd == 0) begin
            $display("FAIL: render_ppm - cannot open frame.ppm");
            fail_cnt++;
            return;
        end

        $fwrite(fd, "P3\n160 320\n255\n");

        for (int brow=0; brow<20; brow++) begin
            for (int py=0; py<16; py++) begin
                for (int bcol=0; bcol<10; bcol++) begin
                    for (int px=0; px<16; px++) begin
                        if (px==15 || py==15) begin
                            // Grid line — dark gray
                            $fwrite(fd, "40 40 40\n");
                        end else begin
                            // Check active piece
                            is_active = 1'b0;
                            for (int pr=0; pr<4; pr++) begin
                                for (int pc2=0; pc2<4; pc2++) begin
                                    if (act_mask[15-pr*4-pc2]) begin
                                        abs_r = act_row_i + pr;
                                        abs_c = act_col_i + pc2;
                                        if (abs_r==brow && abs_c==bcol)
                                            is_active = 1'b1;
                                    end
                                end
                            end
                            // Check ghost piece (same mask, ghost row)
                            is_ghost = 1'b0;
                            if (!is_active) begin
                                for (int pr=0; pr<4; pr++) begin
                                    for (int pc2=0; pc2<4; pc2++) begin
                                        if (act_mask[15-pr*4-pc2]) begin
                                            abs_r = ghost_row_i + pr;
                                            abs_c = act_col_i + pc2;
                                            if (abs_r==brow && abs_c==bcol)
                                                is_ghost = 1'b1;
                                        end
                                    end
                                end
                            end

                            if (is_active)
                                color = piece_rgb(act_type);
                            else if (is_ghost)
                                color = 24'h505050; // ghost gray
                            else
                                color = piece_rgb(demo_board[brow][bcol]);

                            $fwrite(fd, "%0d %0d %0d\n",
                                    color[23:16], color[15:8], color[7:0]);
                        end
                    end // px
                end // bcol
            end // py
        end // brow

        $fclose(fd);
        $display("PASS: render_ppm - frame.ppm written (160x320 P3 PPM)");
        pass_cnt++;
    endtask

    //=========================================================================
    // Main — run all tests in order
    //=========================================================================
    initial begin
        test_piece_rom();
        test_collision_checker();
        test_btn_debounce();
        test_lfsr_rng();
        test_uart_tx();
        test_seven_seg_driver();
        test_audio_engine();
        test_tetris_engine();
        test_uart_packet_builder();
        render_ppm();

        $display("Results: %0d passed, %0d failed", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
