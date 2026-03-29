// UART Transmitter - 115200 baud, 8N1
module uart_tx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] tx_data,
    input  logic       tx_start,
    output logic       tx_out,
    output logic       tx_busy
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;

    typedef enum logic [1:0] {
        IDLE, START, DATA, STOP
    } state_t;

    state_t state;
    logic [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;
    logic [2:0] bit_idx;
    logic [7:0] shift_reg;

    assign tx_busy = (state != IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            tx_out    <= 1'b1;
            clk_cnt   <= 0;
            bit_idx   <= 0;
            shift_reg <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx_out <= 1'b1;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        state     <= START;
                        clk_cnt   <= 0;
                    end
                end

                START: begin
                    tx_out <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        bit_idx <= 0;
                        state   <= DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                DATA: begin
                    tx_out <= shift_reg[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        if (bit_idx == 7)
                            state <= STOP;
                        else
                            bit_idx <= bit_idx + 1;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                STOP: begin
                    tx_out <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        state   <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
            endcase
        end
    end

endmodule
