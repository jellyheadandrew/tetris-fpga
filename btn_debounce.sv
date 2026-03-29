// Button Debouncer with edge detection and level output
// Outputs a single-cycle pulse on rising edge of debounced button
// Also outputs btn_level for DAS (delayed auto-shift) use
module btn_debounce #(
    parameter CLK_FREQ    = 100_000_000,
    parameter DEBOUNCE_MS = 20
)(
    input  logic clk,
    input  logic rst_n,
    input  logic btn_in,
    output logic btn_level,  // debounced level (high while button held)
    output logic btn_pulse   // single-cycle pulse on rising edge
);

    localparam COUNT_MAX = CLK_FREQ / 1000 * DEBOUNCE_MS;
    localparam W = $clog2(COUNT_MAX + 1);

    logic [W-1:0] counter;
    logic btn_stable, btn_prev;

    assign btn_level = btn_stable;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter    <= 0;
            btn_stable <= 0;
            btn_prev   <= 0;
            btn_pulse  <= 0;
        end else begin
            btn_prev  <= btn_stable;
            btn_pulse <= 0;

            if (btn_in != btn_stable) begin
                if (counter == COUNT_MAX[W-1:0]) begin
                    btn_stable <= btn_in;
                    counter    <= 0;
                end else begin
                    counter <= counter + 1;
                end
            end else begin
                counter <= 0;
            end

            // Rising edge detection
            if (btn_stable && !btn_prev)
                btn_pulse <= 1;
        end
    end

endmodule
