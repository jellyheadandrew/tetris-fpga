// 16-bit LFSR Pseudo-Random Number Generator
// Polynomial: x^16 + x^14 + x^13 + x^11 + 1 (taps at bits 15, 13, 12, 10)
// Seed: 16'hACE1
// Free-running when en=1
// piece_out: valid Tetris piece type 1-7 (when piece_valid=1)
module lfsr_rng (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        en,          // enable (free-run when playing)
    output logic [15:0] lfsr_out,    // raw LFSR state
    output logic [2:0]  piece_out,   // piece type 1-7
    output logic        piece_valid  // 1 when piece_out is valid (lfsr[2:0] < 7)
);

    logic [15:0] lfsr;
    logic        feedback;

    // Fibonacci LFSR: feedback = XOR of taps
    // Polynomial x^16+x^14+x^13+x^11+1 -> taps at positions 15,13,12,10 (0-indexed LSB)
    assign feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfsr <= 16'hACE1;
        else if (en)
            lfsr <= {lfsr[14:0], feedback};
    end

    assign lfsr_out    = lfsr;
    assign piece_valid = (lfsr[2:0] < 3'd7);
    assign piece_out   = lfsr[2:0] + 3'd1;  // map 0->1 ... 6->7

endmodule
