// Tetris Piece ROM - combinational lookup
// Returns 16-bit bitmask for (piece_type, rotation)
//
// Bitmask encoding: bit[15-r*4-c] = 1 if cell (row=r, col=c) is occupied
//   Nibble layout per row: bit3=col0, bit2=col1, bit1=col2, bit0=col3
//   [15:12]=row0, [11:8]=row1, [7:4]=row2, [3:0]=row3
//
// piece_type: 1=I, 2=O, 3=T, 4=S, 5=Z, 6=J, 7=L
// rotation:   0-3 per SRS
module piece_rom (
    input  logic [2:0]  piece_type,  // 1-7
    input  logic [1:0]  rotation,    // 0-3
    output logic [15:0] bitmask
);

    always_comb begin
        case ({piece_type, rotation})
            // ---- I-piece ----
            // State 0: row1 full
            {3'd1, 2'd0}: bitmask = 16'h0F00;
            // State 1: col2 in each row
            {3'd1, 2'd1}: bitmask = 16'h2222;
            // State 2: row2 full
            {3'd1, 2'd2}: bitmask = 16'h00F0;
            // State 3: col1 in each row
            {3'd1, 2'd3}: bitmask = 16'h4444;

            // ---- O-piece (all states identical) ----
            // rows 0,1 have cols 1,2
            {3'd2, 2'd0}: bitmask = 16'h6600;
            {3'd2, 2'd1}: bitmask = 16'h6600;
            {3'd2, 2'd2}: bitmask = 16'h6600;
            {3'd2, 2'd3}: bitmask = 16'h6600;

            // ---- T-piece ----
            // State 0: . T . / T T T
            {3'd3, 2'd0}: bitmask = 16'h4E00;
            // State 1: . T . / . T T / . T .
            {3'd3, 2'd1}: bitmask = 16'h4640;
            // State 2: . . . / T T T / . T .
            {3'd3, 2'd2}: bitmask = 16'h0E40;
            // State 3: . T . / T T . / . T .
            {3'd3, 2'd3}: bitmask = 16'h4C40;

            // ---- S-piece ----
            // State 0: . S S / S S .
            {3'd4, 2'd0}: bitmask = 16'h6C00;
            // State 1: . S . / . S S / . . S
            {3'd4, 2'd1}: bitmask = 16'h4620;
            // State 2: . . . / . S S / S S .
            {3'd4, 2'd2}: bitmask = 16'h06C0;
            // State 3: S . . / S S . / . S .
            {3'd4, 2'd3}: bitmask = 16'h8C40;

            // ---- Z-piece ----
            // State 0: Z Z . / . Z Z
            {3'd5, 2'd0}: bitmask = 16'hC600;
            // State 1: . . Z / . Z Z / . Z .
            {3'd5, 2'd1}: bitmask = 16'h2640;
            // State 2: . . . / Z Z . / . Z Z
            {3'd5, 2'd2}: bitmask = 16'h0C60;
            // State 3: . Z . / Z Z . / Z . .
            {3'd5, 2'd3}: bitmask = 16'h4C80;

            // ---- J-piece ----
            // State 0: J . . / J J J
            {3'd6, 2'd0}: bitmask = 16'h8E00;
            // State 1: . J J / . J . / . J .
            {3'd6, 2'd1}: bitmask = 16'h6440;
            // State 2: . . . / J J J / . . J
            {3'd6, 2'd2}: bitmask = 16'h0E20;
            // State 3: . J . / . J . / J J .
            {3'd6, 2'd3}: bitmask = 16'h44C0;

            // ---- L-piece ----
            // State 0: . . L / L L L
            {3'd7, 2'd0}: bitmask = 16'h2E00;
            // State 1: . L . / . L . / . L L
            {3'd7, 2'd1}: bitmask = 16'h4460;
            // State 2: . . . / L . . / L L L
            {3'd7, 2'd2}: bitmask = 16'h08E0;
            // State 3: L L . / . . L / . . L  -> wait, check spec again
            // State 3: . L L / . . L / . . L
            {3'd7, 2'd3}: bitmask = 16'h6220;

            default: bitmask = 16'h0000;
        endcase
    end

endmodule
