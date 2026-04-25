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

    assign uio_out = 8'd0;
    assign uio_oe  = 8'd0;

    wire pixel_valid = ui_in[0];
    wire [7:0] pixel_in = uio_in;

    reg [7:0] out;
    assign uo_out = out;

    // =====================================================
    // 64x64 COUNTERS
    // =====================================================
    reg [5:0] row;
    reg [5:0] col;

    // =====================================================
    // 3x3 SHIFT WINDOW (NO ARRAYS!)
    // =====================================================
    reg [7:0] r0_0, r0_1, r0_2;
    reg [7:0] r1_0, r1_1, r1_2;
    reg [7:0] r2_0, r2_1, r2_2;

    reg [7:0] prev1, prev2;

    // =====================================================
    // SOBEL COMPUTATION
    // =====================================================
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

    wire valid_window = (row >= 2 && col >= 2);

    // =====================================================
    // MAIN PIPELINE
    // =====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row <= 0;
            col <= 0;
            out <= 0;

            r0_0 <= 0; r0_1 <= 0; r0_2 <= 0;
            r1_0 <= 0; r1_1 <= 0; r1_2 <= 0;
            r2_0 <= 0; r2_1 <= 0; r2_2 <= 0;

            prev1 <= 0;
            prev2 <= 0;
        end else if (pixel_valid) begin

            // =================================================
            // SHIFT REGISTER UPDATE (NO MEMORY ARRAY)
            // =================================================
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

            // =================================================
            // 64x64 COUNTER LOGIC
            // =================================================
            if (col == 6'd63) begin
                col <= 0;
                if (row == 6'd63)
                    row <= 0;
                else
                    row <= row + 1;
            end else begin
                col <= col + 1;
            end

            // =================================================
            // OUTPUT LOGIC
            // =================================================
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
