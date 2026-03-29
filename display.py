#!/usr/bin/env python3
"""TODO: Rewrite for Tetris UART protocol (216-byte packets, see PLAN.md Section 3)
Current structure from 2048 project — needs full update for:
- 216-byte packet: 0xAA + state + 200B board + piece info + score/level/lines + checksum
- 10x20 Tetris grid rendering with ANSI colors
- Active piece + ghost piece overlay
- Next piece preview
- Score/level/lines display
"""

import serial
import sys
import os

# TODO: Tetris piece colors (PLAN.md Section 9.2)
PIECE_COLORS = {
    0: (0, 0, 0),        # empty (black)
    1: (0, 255, 255),    # I (cyan)
    2: (255, 255, 0),    # O (yellow)
    3: (170, 0, 255),    # T (purple)
    4: (0, 255, 0),      # S (green)
    5: (255, 0, 0),      # Z (red)
    6: (0, 0, 255),      # J (blue)
    7: (255, 128, 0),    # L (orange)
}

PACKET_SIZE = 216
HEADER = 0xAA

STATE_NAMES = {0: "TITLE", 1: "PLAYING", 2: "PAUSED", 3: "GAME_OVER"}


def main():
    port = sys.argv[1] if len(sys.argv) > 1 else '/dev/ttyUSB1'
    baud = 115200

    print(f"Connecting to {port} at {baud} baud...")
    print("Press buttons on FPGA to play. Ctrl+C to exit.\n")

    try:
        ser = serial.Serial(port, baud, timeout=1)
    except serial.SerialException as e:
        print(f"Error: {e}")
        print("Usage: python3 display.py [serial_port]")
        sys.exit(1)

    while True:
        try:
            # TODO: Implement Tetris packet parsing (PLAN.md Section 3.1)
            # Wait for header 0xAA
            b = ser.read(1)
            if len(b) == 0 or b[0] != HEADER:
                continue

            # Read remaining 215 bytes
            data = ser.read(PACKET_SIZE - 1)
            if len(data) < PACKET_SIZE - 1:
                continue

            # TODO: Validate checksum (XOR of bytes 1-214)
            # TODO: Parse state, board, piece info, score/level/lines
            # TODO: Render with ANSI terminal colors

            pass

        except KeyboardInterrupt:
            print("\nExiting.")
            break

    ser.close()


if __name__ == '__main__':
    main()
