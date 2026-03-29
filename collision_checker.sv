// Collision Checker - combinational
// Checks whether a piece (bitmask) at (piece_col, piece_row) collides with
// board walls, floor, or existing locked cells.
//
// piece_col / piece_row: 6-bit 2's-complement signed value
//   piece_col[5]=1 means negative (piece is partially off-screen left)
// board[row][col]: 3-bit cell value; 0 = empty
//
// Bitmask bit[15-r*4-c] = 1 means the piece occupies relative cell (r,c)
//   [15:12]=row0, [11:8]=row1, [7:4]=row2, [3:0]=row3
//   within each nibble: bit3=col0, bit2=col1, bit1=col2, bit0=col3
module collision_checker (
    input  logic [15:0]           bitmask,
    input  logic [5:0]            piece_col,   // signed 6-bit (2's complement)
    input  logic [5:0]            piece_row,   // signed 6-bit (2's complement)
    input  logic [19:0][9:0][2:0] board,
    output logic                   collides
);

    // Intermediate: board coordinates for each of 16 cells
    logic signed [6:0] br [0:3][0:3];
    logic signed [6:0] bc [0:3][0:3];
    logic              hit[0:3][0:3];

    always_comb begin : COLL_CALC
        integer r, c;
        for (r = 0; r < 4; r++) begin
            for (c = 0; c < 4; c++) begin
                br[r][c] = $signed({piece_row[5], piece_row}) + 7'(r);
                bc[r][c] = $signed({piece_col[5], piece_col}) + 7'(c);

                if (!bitmask[15 - r*4 - c]) begin
                    hit[r][c] = 1'b0;
                end else if (bc[r][c] < 0 || bc[r][c] >= 7'sd10) begin
                    hit[r][c] = 1'b1;           // wall
                end else if (br[r][c] >= 7'sd20) begin
                    hit[r][c] = 1'b1;           // floor
                end else if (br[r][c] >= 0 &&
                             board[br[r][c][4:0]][bc[r][c][3:0]] != 3'b0) begin
                    hit[r][c] = 1'b1;           // occupied cell
                end else begin
                    hit[r][c] = 1'b0;
                end
            end
        end
    end

    assign collides = |{hit[0][0], hit[0][1], hit[0][2], hit[0][3],
                        hit[1][0], hit[1][1], hit[1][2], hit[1][3],
                        hit[2][0], hit[2][1], hit[2][2], hit[2][3],
                        hit[3][0], hit[3][1], hit[3][2], hit[3][3]};

endmodule
