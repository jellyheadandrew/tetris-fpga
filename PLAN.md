# TETRIS FPGA — Product Specification

**Target Board:** Digilent Nexys A7-100T (XC7A100T-1CSG324C, Artix-7)
**Language:** SystemVerilog (IEEE 1800-2017), synthesizable subset only
**Toolchain:** AMD Vivado 2025.2
**Version:** 1.0

---

## 1. Overview

A fully hardware-implemented Tetris game. No soft-core processor, no MicroBlaze, no firmware. All game logic, input handling, audio synthesis, and score tracking are implemented as synthesizable RTL driving the Nexys A7-100T's on-board peripherals directly.

The player controls falling tetrominoes via the board's five push buttons. The game state is transmitted to a host PC over UART at 115200 baud, where a Python terminal renderer displays the game in real time. The current score and level are displayed on the board's 8-digit seven-segment display. Sound effects play through the board's mono audio output (PWM). Game state is indicated on the 16 user LEDs.

**Display strategy:** No VGA. The FPGA sends the full board state over UART after every game event (piece move, lock, line clear, state change). A companion `display.py` script on the PC renders the game using ANSI terminal colors.

---

## 2. Hardware Interface — Pin Assignments

All I/O uses LVCMOS33.

### 2.1 System Clock

| Signal | Pin | Notes |
|--------|-----|-------|
| `CLK100MHZ` | E3 | 100 MHz on-board oscillator. `create_clock -period 10.000` |

### 2.2 Push Buttons (active-high, active when pressed)

| Signal | Pin | Game Function |
|--------|-----|---------------|
| `BTNL` | P17 | Move piece left |
| `BTNR` | M17 | Move piece right |
| `BTNU` | M18 | Rotate piece clockwise |
| `BTND` | P18 | Soft drop (accelerate fall) |
| `BTNC` | N17 | Start game / Pause / Unpause |

### 2.3 Switches

| Signal | Pin | Game Function |
|--------|-----|---------------|
| `SW[0]` | J15 | Hard drop toggle: when ON, BTND becomes instant hard drop instead of soft drop |
| `SW[15]` | V10 | Master reset: when toggled ON, resets entire game to title screen |

Remaining switches (`SW[1]`-`SW[14]`) are unused and unconnected.

### 2.4 UART Output

| Signal | Pin | Notes |
|--------|-----|-------|
| `UART_RXD_OUT` | D4 | FPGA TX -> PC RX, 115200 baud, 8N1 |

### 2.5 Seven-Segment Display (active-low cathodes, active-low anodes)

| Signal | Pins |
|--------|------|
| `SEG[6:0]` (CG-CA) | T10, R10, K16, K13, P15, T11, L18 |
| `DP` (decimal point) | H15 |
| `AN[7:0]` (anodes) | J17, J18, T9, J14, P14, T14, K2, U13 |

**IMPORTANT — Segment mapping (confirmed on physical board):**

```
SEG[0] = CG (middle horizontal, pin T10)
SEG[1] = CF (upper-left vertical, pin R10)
SEG[2] = CE (lower-left vertical, pin K16)
SEG[3] = CD (bottom horizontal, pin K13)
SEG[4] = CC (lower-right vertical, pin P15)
SEG[5] = CB (upper-right vertical, pin T11)
SEG[6] = CA (top horizontal, pin L18)
```

Note: SEG[0] is the middle segment (G) and SEG[6] is the top segment (A). This is the reverse of the typical CA=SEG[0] convention. The decoder must account for this ordering.

Display convention: digits `AN[7]`..`AN[0]` are left-to-right on board.

The display shows: `Lv.LL SSSS` mapped as follows (left-to-right = AN[7]..AN[0]):
- AN[7]: 'L' (custom segment pattern: CE,CD,CF on = `7'b1000110`)
- AN[6]: 'v' (custom segment pattern: CC,CD,CE on = `7'b1010001`)
- AN[5]: level tens digit, with decimal point ON (DP=0)
- AN[4]: level ones digit
- AN[3]: blank (anode OFF)
- AN[2]: score thousands digit
- AN[1]: score hundreds digit
- AN[0]: score tens and ones...

Score is displayed on AN[3:0] as 4-digit decimal (0000-9999). AN[3]=thousands, AN[2]=hundreds, AN[1]=tens, AN[0]=ones. If the score exceeds 9999, it wraps modulo 10000.

### 2.6 User LEDs

| Signal | Pins |
|--------|------|
| `LED[15:0]` | H17, K15, J13, N14, R18, V17, U17, U16, V16, T15, U14, T16, V15, V14, V12, V11 |

LED behavior:
- **Title screen:** Knight-rider / Larson scanner animation across all 16 LEDs.
- **Playing:** `LED[9:0]` represents the fill level of the board -- each LED lights when the corresponding pair of rows (rows 0-1, 2-3, ... 18-19) contains at least one occupied cell.
- **Game over:** All 16 LEDs on solid.
- **Paused:** All 16 LEDs blink at 2 Hz.

### 2.7 Audio Output (PWM)

| Signal | Pin | Notes |
|--------|-----|-------|
| `AUD_PWM` | A11 | PWM audio out. Configure as open-drain. |
| `AUD_SD` | D12 | Audio amplifier shutdown. Drive HIGH to enable audio. |

---

## 3. UART Display Protocol

### 3.1 Packet Format

The FPGA sends a binary packet over UART (115200 baud, 8N1) after every game event. The PC-side `display.py` receives and renders the game state.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | Header | `0xAA` (sync byte) |
| 1 | 1 | State | Game state: `0x00`=TITLE, `0x01`=PLAYING, `0x02`=PAUSED, `0x03`=GAME_OVER |
| 2-201 | 200 | Board | 20 rows x 10 cols, row-major order (row 0 first), each cell 1 byte (0=empty, 1-7=piece type) |
| 202 | 1 | Piece type | Active piece type (1-7), or 0 if none |
| 203 | 1 | Piece rotation | Active piece rotation state (0-3) |
| 204 | 1 | Piece col | Active piece column (signed, int8) |
| 205 | 1 | Piece row | Active piece row (signed, int8) |
| 206 | 1 | Next piece | Next piece type (1-7) |
| 207 | 1 | Ghost row | Ghost piece row position (int8) |
| 208-211 | 4 | Score | Big-endian uint32 |
| 212 | 1 | Level | Current level (1-99) |
| 213-214 | 2 | Lines | Big-endian uint16, total lines cleared |
| 215 | 1 | Checksum | XOR of bytes 1-214 |

**Total packet size: 216 bytes.**

Packets are sent on: piece spawn, piece move, piece rotate, piece lock, line clear complete, state change (title/play/pause/gameover), gravity tick (piece falls one row).

### 3.2 Transmission Rate

At 115200 baud, 8N1: 11520 bytes/sec. A 216-byte packet takes ~18.75 ms to transmit. This supports ~53 packets/sec, more than enough for 60 Hz game logic (not every tick needs a packet — only on visible state changes).

To avoid queueing issues, the UART TX state machine must finish sending the current packet before starting a new one. If a new event occurs while transmitting, the new packet is queued (single-buffer). If the buffer is full, the event is dropped (acceptable — the next event will carry the full current state).

---

## 4. Game Mechanics

### 4.1 Tetrominoes — Shape Definitions

Each tetromino is defined as a 4x4 bitmask. There are 7 pieces x 4 rotation states = 28 bitmasks.

Rotation follows the **Super Rotation System (SRS)** standard:

**I-piece (4 rotations):**
```
State 0:        State 1:        State 2:        State 3:
. . . .         . . I .         . . . .         . I . .
I I I I         . . I .         . . . .         . I . .
. . . .         . . I .         I I I I         . I . .
. . . .         . . I .         . . . .         . I . .
```

**O-piece (all 4 states identical):**
```
. O O .
. O O .
. . . .
. . . .
```

**T-piece (4 rotations):**
```
State 0:        State 1:        State 2:        State 3:
. T .           . T .           . . .           . T .
T T T           . T T           T T T           T T .
. . .           . T .           . T .           . T .
```

**S-piece (4 rotations):**
```
State 0:        State 1:        State 2:        State 3:
. S S           . S .           . . .           S . .
S S .           . S S           . S S           S S .
. . .           . . S           S S .           . S .
```

**Z-piece (4 rotations):**
```
State 0:        State 1:        State 2:        State 3:
Z Z .           . . Z           . . .           . Z .
. Z Z           . Z Z           Z Z .           Z Z .
. . .           . Z .           . Z Z           Z . .
```

**J-piece (4 rotations):**
```
State 0:        State 1:        State 2:        State 3:
J . .           . J J           . . .           . J .
J J J           . J .           J J J           . J .
. . .           . J .           . . J           J J .
```

**L-piece (4 rotations):**
```
State 0:        State 1:        State 2:        State 3:
. . L           . L .           . . .           . L L
L L L           . L .           L . .           . . L
. . .           . L L           L L L           . . L
```

These 28 bitmasks are stored in a combinational ROM (`case` statement).

### 4.2 SRS Wall Kick

When a rotation would cause collision, try the following offset translations in order. If any offset produces no collision, use it. If all fail, the rotation is denied.

**Wall kick offset table (for T, S, Z, J, L pieces):**

| Rotation | Test 1 | Test 2 | Test 3 | Test 4 |
|----------|--------|--------|--------|--------|
| 0->1 | (-1, 0) | (-1,+1) | ( 0,-2) | (-1,-2) |
| 1->2 | (+1, 0) | (+1,-1) | ( 0,+2) | (+1,+2) |
| 2->3 | (+1, 0) | (+1,+1) | ( 0,-2) | (+1,-2) |
| 3->0 | (-1, 0) | (-1,-1) | ( 0,+2) | (-1,+2) |

Offsets are `(column_offset, row_offset)` where positive column = right, positive row = up (toward row 0).

**Wall kick offset table (for I-piece):**

| Rotation | Test 1 | Test 2 | Test 3 | Test 4 |
|----------|--------|--------|--------|--------|
| 0->1 | (-2, 0) | (+1, 0) | (-2,-1) | (+1,+2) |
| 1->2 | (+2, 0) | (-1, 0) | (+2,+1) | (-1,-2) |
| 2->3 | (-1, 0) | (+2, 0) | (-1,+2) | (+2,-1) |
| 3->0 | (+1, 0) | (-2, 0) | (+1,-2) | (-2,+1) |

**The O-piece does not rotate.**

### 4.3 Board State

The playing board is a 10-column x 20-row grid. Each cell stores a 3-bit value:

| Value | Meaning |
|-------|---------|
| `3'b000` | Empty |
| `3'b001` | I-piece (cyan) |
| `3'b010` | O-piece (yellow) |
| `3'b011` | T-piece (purple) |
| `3'b100` | S-piece (green) |
| `3'b101` | Z-piece (red) |
| `3'b110` | J-piece (blue) |
| `3'b111` | L-piece (orange) |

Total storage: 10 x 20 x 3 bits = 600 bits (registers, no BRAM).

Row 0 is the top row. Row 19 is the bottom row. Column 0 is the leftmost column.

### 4.4 Piece Spawning

When a new piece enters the field:
- The piece type is taken from the "next piece" register, and a new "next piece" is generated by the LFSR RNG.
- Initial position: column 3, row 0 (the piece's 4x4 bounding box occupies columns 3-6, rows 0-3).
- Initial rotation state: 0.
- If the spawned piece immediately collides -> **game over**.

**Piece generation:** Use a 16-bit LFSR (polynomial `x^16 + x^14 + x^13 + x^11 + 1`, taps at bits 15, 13, 12, 10, seed `16'hACE1`). Use rejection sampling: take `lfsr[2:0]`; if the value is >= 7, re-clock and retry until `lfsr[2:0]` is in range 0-6. The result selects piece type (0-6). The LFSR is free-running at the system clock whenever the game is in the PLAYING state.

### 4.5 Movement and Collision

**Left/Right movement:** When BTNL or BTNR is pressed, shift the active piece's column by -1 or +1. If collision, deny the move.

**Collision detection:**
```
For each of the 16 cells (r, c) in the 4x4 piece bitmask:
    if bitmask[r][c] == 1:
        board_row = piece_row + r
        board_col = piece_col + c
        if board_col < 0 or board_col >= 10:  -> collision (wall)
        if board_row >= 20:                    -> collision (floor)
        if board_row >= 0 and board[board_row][board_col] != 0: -> collision (cell)
```

Cells with `board_row < 0` are above the field -- not a collision.

**Auto-repeat (DAS):** When BTNL or BTNR is held:
- Initial delay: 200 ms before first repeat.
- Repeat rate: every 50 ms thereafter.

### 4.6 Gravity and Locking

The active piece falls by one row at a rate determined by the current level:

| Level | Fall interval (ms) | Approx ticks @ 100MHz |
|-------|-------------------|----------------------|
| 1 | 1000 | 100,000,000 |
| 2 | 793 | 79,300,000 |
| 3 | 618 | 61,800,000 |
| 4 | 473 | 47,300,000 |
| 5 | 355 | 35,500,000 |
| 6 | 262 | 26,200,000 |
| 7 | 190 | 19,000,000 |
| 8 | 135 | 13,500,000 |
| 9 | 100 | 10,000,000 |
| 10+ | 67 | 6,700,000 |

When the active piece cannot fall further, a **lock delay** of 500 ms begins:
- Player can still move/rotate during lock delay.
- Each successful move/rotation resets the lock delay timer.
- Maximum lock delay resets: 15.
- When timer expires, the piece locks into the board.

**Soft drop (BTND with SW[0] OFF):** Fall one row every 16.7 ms (~60 Hz). Score: +1 per row.

**Hard drop (BTND with SW[0] ON):** Instantly drop to lowest valid position and lock immediately. Score: +2 per row. No lock delay.

### 4.7 Line Clearing

After a piece locks, scan all 20 rows. Any row where all 10 cells are non-empty is a completed line.

Line clearing sequence:
1. Identify all completed rows (1-4 possible).
2. **Flash animation:** Completed rows flash (toggle between piece colors and white) 3 times over 300 ms. During flash, gameplay is paused.
3. Remove completed rows and shift all rows above down.
4. Award score (Section 4.8).
5. Send UART packet with updated state.

### 4.8 Scoring

| Action | Points |
|--------|--------|
| Single (1 line) | 100 x level |
| Double (2 lines) | 300 x level |
| Triple (3 lines) | 500 x level |
| Tetris (4 lines) | 800 x level |
| Soft drop | 1 per row |
| Hard drop | 2 per row |

### 4.9 Leveling

- Game starts at **level 1**.
- Every **10 lines cleared**, level increments by 1.
- Maximum level: 99 (gravity stays at level-10 rate for 10-99).

### 4.10 Ghost Piece

The ghost piece position (where the piece would land on hard drop) is computed and sent in the UART packet. The PC renderer draws it as a hollow outline.

---

## 5. Game States (Top-Level FSM)

```
         +----------+
    -----|  TITLE   |<----------------------+
    reset|          |                       |
         +----+-----+                       |
              | BTNC pressed                |
              v                             |
         +----------+                       |
         |  PLAYING |<------+               |
         |          |       |               |
         +--+---+---+       |               |
            |   | BTNC      |               |
            |   v           |               |
            | +----------+  |               |
            | |  PAUSED  |--+               |
            | +----------+  BTNC            |
            |                               |
            | spawn collision               |
            v                               |
         +----------+                       |
         | GAME_OVER|---------------------->+
         |          |  BTNC (after 2s delay)
         +----------+
```

**TITLE state:**
- Seven-segment display: blank (all anodes OFF).
- LEDs: Larson scanner animation.
- UART: sends packet with state=TITLE, empty board.
- Audio: silent.

**PLAYING state:**
- Normal gameplay as described in Section 4.
- Seven-segment shows score and level.
- LEDs show board fill level.
- UART: sends packet on every visible state change.

**PAUSED state:**
- Seven-segment: continues showing score/level.
- LEDs: all blink at 2 Hz.
- Gravity timer frozen. All input except BTNC ignored.
- UART: sends packet with state=PAUSED.

**GAME_OVER state:**
- Seven-segment: shows final score.
- LEDs: all on solid.
- 2-second lockout before BTNC is accepted.
- UART: sends packet with state=GAME_OVER.

---

## 6. Audio Specification

PWM synthesis via `AUD_PWM` pin. `AUD_SD` held HIGH when audio active.

**PWM carrier frequency:** 50 kHz (100 MHz / 2000).

### 6.1 Sound Effects

| Event | Sound | Duration | Implementation |
|-------|-------|----------|----------------|
| Piece move (L/R) | Short tick | 30 ms | 800 Hz square wave |
| Piece rotate | Click | 50 ms | 1200 Hz square wave |
| Piece lock | Thud | 80 ms | 200 Hz square wave, amplitude decaying |
| Single line clear | Rising tone | 150 ms | 500 Hz -> 1000 Hz sweep |
| Tetris (4 lines) | Fanfare | 400 ms | 800/1000/1200 Hz sequence |
| Hard drop | Slam | 60 ms | 100 Hz square wave |
| Game over | Descending tone | 1000 ms | 800 Hz -> 100 Hz sweep |

Only one sound plays at a time. New sound replaces current.

### 6.2 PWM Implementation

8-bit duty cycle value compared against 8-bit free-running counter. Output HIGH when counter < duty_cycle. Duty cycle computed from waveform generator.

---

## 7. Module Hierarchy

```
tetris_top                          -- Top-level, port mapping
+-- btn_debounce (x5)               -- Debounce each button (20 ms)
+-- lfsr_rng                        -- 16-bit LFSR pseudo-random generator
+-- tetris_engine                   -- Game logic FSM, board state, piece state
|   +-- piece_rom                   -- (piece_type, rotation) -> 4x4 bitmask
|   +-- collision_checker           -- piece+position+board -> collides?
|   +-- line_clear_logic            -- Scan rows, shift down, count lines
+-- uart_tx                         -- UART transmitter (115200, 8N1)
+-- uart_packet_builder             -- Serialize game state into UART packets
+-- seven_seg_driver                -- Multiplexed 8-digit display
+-- led_controller                  -- LED animations based on game state
+-- audio_engine                    -- Sound effect FSM + PWM output
```

### 7.1 Clock Domain

**Single clock domain: 100 MHz.** No clock generation needed (no VGA). All logic runs on `CLK100MHZ` directly.

---

## 8. Seven-Segment Decoder

The segment ordering on this board (confirmed on hardware) is:

```
    AAAAAA        SEG[6]
   F      B       SEG[1]=F, SEG[5]=B
   F      B
    GGGGGG        SEG[0]
   E      C       SEG[2]=E, SEG[4]=C
   E      C
    DDDDDD        SEG[3]
```

So `SEG[6:0] = {CA, CB, CC, CD, CE, CF, CG}` = `{SEG[6], SEG[5], SEG[4], SEG[3], SEG[2], SEG[1], SEG[0]}`.

Seven-segment decoder (active-low, bit order SEG[6:0] = CG,CF,CE,CD,CC,CB,CA):

```systemverilog
// SEG[6:0] = {CA, CB, CC, CD, CE, CF, CG}  (per pin assignments: SEG[6]=CA, SEG[5]=CB, SEG[4]=CC, SEG[3]=CD, SEG[2]=CE, SEG[1]=CF, SEG[0]=CG)
// Each bit: 0 = segment ON, 1 = segment OFF
case (digit)
    4'h0: SEG = 7'b0000001;  // A,B,C,D,E,F on, G off  -> segments 6,5,4,3,2,1 on, 0 off
    4'h1: SEG = 7'b1001111;  // B,C on
    4'h2: SEG = 7'b0010010;  // A,B,D,E,G on
    4'h3: SEG = 7'b0000110;  // A,B,C,D,G on
    4'h4: SEG = 7'b1001100;  // B,C,F,G on
    4'h5: SEG = 7'b0100100;  // A,C,D,F,G on
    4'h6: SEG = 7'b0100000;  // A,C,D,E,F,G on
    4'h7: SEG = 7'b0001111;  // A,B,C on
    4'h8: SEG = 7'b0000000;  // all on
    4'h9: SEG = 7'b0000100;  // A,B,C,D,F,G on
    default: SEG = 7'b1111111;
endcase
```

**NOTE:** This mapping must be verified against the actual XDC pin assignments. The builder must ensure the case statement correctly maps each digit to the physical segments given the pin order `SEG[0]=T10(CG), SEG[1]=R10(CF), ..., SEG[6]=L18(CA)`.

---

## 9. Simulation & Testbench

### 9.1 Frame Rendering for Simulation

Since there is no VGA, simulation verification uses a **PPM frame renderer** in the testbench. The testbench:

1. Runs the game engine through a scripted sequence of moves.
2. After each significant event, reads the board state, active piece, and ghost piece from internal signals.
3. Renders a 160x320 pixel PPM image (each cell = 16x16 pixels) showing:
   - The 10x20 grid with colored cells
   - The active piece in its current position
   - The ghost piece as a dimmed version
   - Grid lines between cells
4. Saves to `frame_NNN.ppm` for visual inspection.

### 9.2 Color Palette for PPM Rendering

| Piece | Color | RGB (8-bit) |
|-------|-------|-------------|
| Empty | Black | (0, 0, 0) |
| I | Cyan | (0, 255, 255) |
| O | Yellow | (255, 255, 0) |
| T | Purple | (170, 0, 255) |
| S | Green | (0, 255, 0) |
| Z | Red | (255, 0, 0) |
| J | Blue | (0, 0, 255) |
| L | Orange | (255, 128, 0) |
| Ghost | Gray | (80, 80, 80) |
| Grid line | Dark gray | (40, 40, 40) |

### 9.3 Module Testbenches

| Module | Testbench Checks |
|--------|-----------------|
| `btn_debounce` | Noisy input -> clean output after 20 ms; single pulse on rising edge |
| `lfsr_rng` | Non-zero output; period >= 65535; no stuck states |
| `piece_rom` | All 28 bitmasks match Section 4.1 definitions |
| `collision_checker` | Wall, floor, cell collision; no false positives on valid positions |
| `line_clear_logic` | Single, double, triple, tetris; rows shift correctly; score correct |
| `tetris_engine` | Spawn -> fall -> lock -> clear -> spawn cycle; game over on top collision |
| `uart_tx` | Correct baud rate timing; start/stop bits; data bits |
| `uart_packet_builder` | Correct packet format per Section 3.1; checksum validity |
| `seven_seg_driver` | Correct digit values and multiplexing; segment mapping per Section 8 |
| `audio_engine` | Trigger -> PWM output at expected frequency |

All testbenches must be self-checking (`$display` / `$error` with exit codes).

---

## 10. PC-Side Display Script (`display.py`)

The companion Python script receives UART packets and renders the game in terminal:

- Uses `pyserial` for UART reception.
- ANSI 24-bit color escape codes for colored blocks.
- Renders: board grid, active piece, ghost piece, next piece preview, score/level/lines.
- Terminal size: ~30 columns x 25 rows minimum.
- Updates on every received packet.
- Validates checksum; drops corrupted packets silently.

---

## 11. Timing Constraints (XDC)

```xdc
## Clock
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }];
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0 5} [get_ports { CLK100MHZ }];

## Buttons
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { BTNC }];
set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports { BTNU }];
set_property -dict { PACKAGE_PIN P17   IOSTANDARD LVCMOS33 } [get_ports { BTNL }];
set_property -dict { PACKAGE_PIN M17   IOSTANDARD LVCMOS33 } [get_ports { BTNR }];
set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 } [get_ports { BTND }];

## Switches
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { SW[0] }];
set_property -dict { PACKAGE_PIN V10   IOSTANDARD LVCMOS33 } [get_ports { SW[15] }];

## UART
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { UART_RXD_OUT }];

## Seven Segment Display
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { SEG[0] }];
set_property -dict { PACKAGE_PIN R10   IOSTANDARD LVCMOS33 } [get_ports { SEG[1] }];
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports { SEG[2] }];
set_property -dict { PACKAGE_PIN K13   IOSTANDARD LVCMOS33 } [get_ports { SEG[3] }];
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { SEG[4] }];
set_property -dict { PACKAGE_PIN T11   IOSTANDARD LVCMOS33 } [get_ports { SEG[5] }];
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports { SEG[6] }];
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { DP }];
set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports { AN[0] }];
set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports { AN[1] }];
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { AN[2] }];
set_property -dict { PACKAGE_PIN J14   IOSTANDARD LVCMOS33 } [get_ports { AN[3] }];
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { AN[4] }];
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { AN[5] }];
set_property -dict { PACKAGE_PIN K2    IOSTANDARD LVCMOS33 } [get_ports { AN[6] }];
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { AN[7] }];

## LEDs
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { LED[0] }];
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { LED[1] }];
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { LED[2] }];
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { LED[3] }];
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { LED[4] }];
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { LED[5] }];
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { LED[6] }];
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { LED[7] }];
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { LED[8] }];
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { LED[9] }];
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { LED[10] }];
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { LED[11] }];
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { LED[12] }];
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { LED[13] }];
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { LED[14] }];
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { LED[15] }];

## Audio PWM
set_property -dict { PACKAGE_PIN A11   IOSTANDARD LVCMOS33 } [get_ports { AUD_PWM }];
set_property -dict { PACKAGE_PIN D12   IOSTANDARD LVCMOS33 } [get_ports { AUD_SD }];

## Configuration
set_property CFGBVS VCCO [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];
```

---

## 12. Resource Budget (estimated)

| Resource | Estimated Usage | Available (XC7A100T) | % |
|----------|----------------|---------------------|---|
| LUTs | ~2,000-4,000 | 63,400 | 3-6% |
| Flip-Flops | ~1,000-2,500 | 126,800 | 1-2% |
| BRAM (36Kb) | 0 | 135 | 0% |
| MMCM | 0 | 6 | 0% |
| DSP | 0 | 240 | 0% |

No VGA means no MMCM/PLL needed. Single 100 MHz clock domain.

---

## 13. Known Simplifications

1. **No bag randomizer.** Simple LFSR instead of 7-bag system.
2. **No hold piece.**
3. **No T-spin detection.**
4. **Score wraps at 9999 on seven-segment.** UART score is full 32-bit.
5. **No background music.** Only sound effects via PWM.
6. **No VGA.** Display via UART + PC terminal renderer.
7. **Single speed table.** Levels 10+ all use the same gravity speed.

---

## 14. Acceptance Criteria

1. **Synthesis:** Synthesizes without errors in Vivado 2025.2 targeting `xc7a100tcsg324-1`.
2. **Implementation:** Place-and-route with all timing met (no negative slack).
3. **Bitstream:** `.bit` file generated.
4. **Simulation:** Testbench produces valid PPM frames showing correct Tetris gameplay.
5. **UART:** Packets conform to Section 3.1 protocol; `display.py` renders correctly.
6. **Gameplay:** All 7 tetrominoes spawn, fall, move, rotate with SRS wall kicks, lock, and clear lines.
7. **Ghost piece:** Ghost position computed correctly in UART packet.
8. **Scoring:** Score increments per Section 4.8, displayed on seven-segment and UART.
9. **Leveling:** Level increments every 10 lines, gravity speeds up per Section 4.6.
10. **Game states:** Title -> Playing -> Paused -> Playing and Game Over -> Title transitions work.
11. **Audio:** At least line clear sound is audible through audio jack.
12. **LEDs:** LED behavior matches Section 2.6.
13. **Seven-segment:** Digits display correctly with the corrected segment mapping (Section 8).
