// =============================================================================
// UART Packet Builder
// Serializes game state into 216-byte Tetris UART packets (Section 3.1)
//
// Packet format:
//   [0]      0xAA  header
//   [1]      state  (0=TITLE 1=PLAYING 2=PAUSED 3=GAMEOVER)
//   [2..201] board  (20 rows × 10 cols, 1 byte each, row-major)
//   [202]    active piece type
//   [203]    active piece rotation
//   [204]    active piece col  (signed int8)
//   [205]    active piece row  (signed int8)
//   [206]    next piece type
//   [207]    ghost row         (signed int8)
//   [208..211] score          (big-endian uint32)
//   [212]    level
//   [213..214] lines          (big-endian uint16)
//   [215]    checksum          (XOR of bytes 1..214)
//
// Total: 216 bytes
// =============================================================================
module uart_packet_builder #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115_200
)(
    input  logic        clk,
    input  logic        rst_n,

    // Trigger: high one cycle to start sending a packet
    input  logic        trigger,

    // Game state snapshot inputs
    input  logic [1:0]  game_state,
    input  logic [19:0][9:0][2:0] board,
    input  logic [2:0]  active_type,
    input  logic [1:0]  active_rot,
    input  logic [5:0]  active_col,    // signed 6-bit
    input  logic [5:0]  active_row,    // signed 6-bit
    input  logic [2:0]  next_type,
    input  logic [5:0]  ghost_row,     // signed 6-bit
    input  logic [31:0] score,
    input  logic [6:0]  level,
    input  logic [15:0] lines,

    // UART TX interface
    output logic [7:0]  tx_data,
    output logic        tx_start,
    input  logic        tx_busy,

    // Status
    output logic        sending
);

    // =========================================================================
    // Snapshot registers (captured when trigger fires)
    // =========================================================================
    logic [1:0]  snap_state;
    logic [19:0][9:0][2:0] snap_board;
    logic [2:0]  snap_atype;
    logic [1:0]  snap_arot;
    logic [5:0]  snap_acol;
    logic [5:0]  snap_arow;
    logic [2:0]  snap_ntype;
    logic [5:0]  snap_ghost;
    logic [31:0] snap_score;
    logic [6:0]  snap_level;
    logic [15:0] snap_lines;

    // Pending trigger — set when trigger fires while busy
    logic        pending;

    // =========================================================================
    // Byte index and checksum accumulator
    // =========================================================================
    logic [7:0]  byte_idx;    // 0..215
    logic [7:0]  checksum;    // running XOR of bytes 1..214
    logic        active;      // packet transmission in progress
    logic        byte_sent;   // uart finished one byte

    assign sending   = active || pending;
    assign byte_sent = !tx_busy;  // next byte can be sent

    // =========================================================================
    // Compute current byte to send based on byte_idx and snapshot
    // =========================================================================
    function automatic [7:0] get_byte(
        input logic [7:0]   idx,
        input logic [1:0]   gs,
        input logic [19:0][9:0][2:0] brd,
        input logic [2:0]   at,
        input logic [1:0]   ar,
        input logic [5:0]   ac,
        input logic [5:0]   row,
        input logic [2:0]   nt,
        input logic [5:0]   gr,
        input logic [31:0]  sc,
        input logic [6:0]   lv,
        input logic [15:0]  ln,
        input logic [7:0]   csum
    );
        // Board row/col calculation (used in default branch for bytes 2..201)
        logic [7:0] bidx;
        logic [4:0] brow;  // 5-bit: 0..19
        logic [3:0] bcol;  // 4-bit: 0..9

        bidx = idx - 8'd2;
        brow = 5'(bidx / 8'd10);
        bcol = 4'(bidx % 8'd10);

        case (idx)
            8'd0:   get_byte = 8'hAA;             // header
            8'd1:   get_byte = {6'b0, gs};         // game state
            8'd202: get_byte = {5'b0, at};         // active type
            8'd203: get_byte = {6'b0, ar};         // active rotation
            8'd204: get_byte = {{2{ac[5]}}, ac};   // piece col (sign-ext 6→8)
            8'd205: get_byte = {{2{row[5]}}, row}; // piece row (sign-ext 6→8)
            8'd206: get_byte = {5'b0, nt};         // next type
            8'd207: get_byte = {{2{gr[5]}}, gr};   // ghost row (sign-ext 6→8)
            8'd208: get_byte = sc[31:24];          // score MSB
            8'd209: get_byte = sc[23:16];
            8'd210: get_byte = sc[15:8];
            8'd211: get_byte = sc[7:0];            // score LSB
            8'd212: get_byte = {1'b0, lv};         // level
            8'd213: get_byte = ln[15:8];           // lines MSB
            8'd214: get_byte = ln[7:0];            // lines LSB
            8'd215: get_byte = csum;               // checksum (XOR bytes 1..214)
            default: begin
                // Board bytes: indices 2..201 → board[row][col]
                if (idx >= 8'd2 && idx <= 8'd201)
                    get_byte = {5'b0, brd[brow][bcol]};
                else
                    get_byte = 8'h00;
            end
        endcase
    endfunction

    // =========================================================================
    // State machine
    // =========================================================================
    // States: IDLE, WAIT (waiting for tx_busy=0), SEND (assert tx_start)
    localparam logic [1:0] PB_IDLE = 2'd0, PB_WAIT = 2'd1, PB_SEND = 2'd2;
    logic [1:0] pb_state;

    logic [7:0] cur_byte;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pb_state  <= PB_IDLE;
            active    <= 1'b0;
            pending   <= 1'b0;
            byte_idx  <= 8'd0;
            checksum  <= 8'd0;
            tx_data   <= 8'd0;
            tx_start  <= 1'b0;
            // snapshot regs
            snap_state <= '0;
            snap_board <= '0;
            snap_atype <= '0;
            snap_arot  <= '0;
            snap_acol  <= '0;
            snap_arow  <= '0;
            snap_ntype <= '0;
            snap_ghost <= '0;
            snap_score <= '0;
            snap_level <= '0;
            snap_lines <= '0;
        end else begin
            tx_start <= 1'b0;

            // Capture trigger → snapshot or set pending
            if (trigger) begin
                if (!active) begin
                    // Capture snapshot and start transmission
                    snap_state <= game_state;
                    snap_board <= board;
                    snap_atype <= active_type;
                    snap_arot  <= active_rot;
                    snap_acol  <= active_col;
                    snap_arow  <= active_row;
                    snap_ntype <= next_type;
                    snap_ghost <= ghost_row;
                    snap_score <= score;
                    snap_level <= level;
                    snap_lines <= lines;
                    byte_idx   <= 8'd0;
                    checksum   <= 8'd0;
                    active     <= 1'b1;
                    pb_state   <= PB_SEND;
                end else begin
                    // Already sending — overwrite pending snapshot
                    pending    <= 1'b1;
                    snap_state <= game_state;
                    snap_board <= board;
                    snap_atype <= active_type;
                    snap_arot  <= active_rot;
                    snap_acol  <= active_col;
                    snap_arow  <= active_row;
                    snap_ntype <= next_type;
                    snap_ghost <= ghost_row;
                    snap_score <= score;
                    snap_level <= level;
                    snap_lines <= lines;
                end
            end

            case (pb_state)
                PB_IDLE: begin
                    // Nothing to do
                end

                PB_SEND: begin
                    // Assert tx_start for one cycle to send current byte
                    if (!tx_busy) begin
                        cur_byte = get_byte(byte_idx,
                                            snap_state, snap_board,
                                            snap_atype, snap_arot,
                                            snap_acol, snap_arow,
                                            snap_ntype, snap_ghost,
                                            snap_score, snap_level,
                                            snap_lines, checksum);
                        tx_data  <= cur_byte;
                        tx_start <= 1'b1;

                        // Accumulate checksum for bytes 1-214
                        if (byte_idx >= 8'd1 && byte_idx <= 8'd214)
                            checksum <= checksum ^ cur_byte;

                        if (byte_idx == 8'd215) begin
                            // Last byte sent — packet done
                            byte_idx <= 8'd0;
                            checksum <= 8'd0;
                            if (pending) begin
                                // Start next packet immediately
                                pending  <= 1'b0;
                                active   <= 1'b1;
                                pb_state <= PB_SEND;
                            end else begin
                                active   <= 1'b0;
                                pb_state <= PB_IDLE;
                            end
                        end else begin
                            byte_idx <= byte_idx + 8'd1;
                            pb_state <= PB_WAIT;
                        end
                    end
                end

                PB_WAIT: begin
                    // Wait for UART TX to finish current byte
                    if (!tx_busy) begin
                        pb_state <= PB_SEND;
                    end
                end

                default: pb_state <= PB_IDLE;
            endcase
        end
    end

endmodule
