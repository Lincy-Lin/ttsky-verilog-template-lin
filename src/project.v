`default_nettype none

module tt_um_edge_detect (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    assign uio_out = 0;
    assign uio_oe  = 0;

    wire pixel_valid = ui_in[0];
    wire [7:0] pixel_in = uio_in;

    reg [7:0] out;
    assign uo_out = out;

    // -----------------------------
    // 3×3 SHIFT WINDOW (NO ARRAY!)
    // -----------------------------

    reg [7:0] r0_0, r0_1, r0_2;
    reg [7:0] r1_0, r1_1, r1_2;
    reg [7:0] r2_0, r2_1, r2_2;

    reg [7:0] prev1, prev2;

    // simple counters (small!)
    reg [3:0] col;

    // Sobel
    wire signed [10:0] gx =
        -$signed(r0_0) + $signed(r0_2)
        -($signed(r1_0) <<< 1) + ($signed(r1_2) <<< 1)
        -$signed(r2_0) + $signed(r2_2);

    wire signed [10:0] gy =
         $signed(r0_0) + ($signed(r0_1) <<< 1) + $signed(r0_2)
        -$signed(r2_0) - ($signed(r2_1) <<< 1) - $signed(r2_2);

    wire [10:0] ax = gx[10] ? -gx : gx;
    wire [10:0] ay = gy[10] ? -gy : gy;
    wire [11:0] mag = ax + ay;

    wire valid_window = (col >= 2);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col <= 0;
            out <= 0;

            r0_0 <= 0; r0_1 <= 0; r0_2 <= 0;
            r1_0 <= 0; r1_1 <= 0; r1_2 <= 0;
            r2_0 <= 0; r2_1 <= 0; r2_2 <= 0;

            prev1 <= 0;
            prev2 <= 0;
        end else if (pixel_valid) begin

            // -----------------------------
            // SHIFT WINDOW UPDATE
            // -----------------------------

            r0_0 <= r0_1;
            r0_1 <= r0_2;
            r0_2 <= pixel_in;

            r1_0 <= r1_1;
            r1_1 <= r1_2;
            r1_2 <= prev1;

            r2_0 <= r2_1;
            r2_1 <= r2_2;
            r2_2 <= prev2;

            prev2 <= prev1;
            prev1 <= pixel_in;

            // -----------------------------
            // COLUMN COUNTER
            // -----------------------------
            if (col < 7)
                col <= col + 1;

            // -----------------------------
            // OUTPUT
            // -----------------------------
            if (valid_window) begin
                if (mag > 255)
                    out <= 8'hFF;
                else
                    out <= mag[7:0];
            end else begin
                out <= 0;
            end
        end
    end

endmodule
