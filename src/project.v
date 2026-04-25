`default_nettype none

module tt_um_sobel #(
    parameter IMG_SIZE    = 6,
    parameter OUTPUT_BITS = 8
)(
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for (i = value - 1; i > 0; i = i >> 1)
                clog2 = clog2 + 1;
        end
    endfunction

    localparam ADDR_WIDTH   = clog2(IMG_SIZE);
    localparam OUTPUT_SHIFT = 8 - OUTPUT_BITS;

    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    wire _unused = &{ena, ui_in[7:1], p11, 1'b0};

    wire       pixel_valid = ui_in[0];
    wire [7:0] pixel_in    = uio_in;

    reg [7:0] out;
    assign uo_out = out;

    reg [ADDR_WIDTH-1:0] row;
    reg [ADDR_WIDTH-1:0] col;

    reg [7:0] linebuf1 [0:IMG_SIZE-1];
    reg [7:0] linebuf2 [0:IMG_SIZE-1];

    reg [7:0] r0_0, r0_1;
    reg [7:0] r1_0, r1_1;
    reg [7:0] r2_0, r2_1;

    wire [7:0] row1_col2 = linebuf1[col];
    wire [7:0] row2_col2 = linebuf2[col];

    wire [7:0] p00 = r2_0;
    wire [7:0] p01 = r2_1;
    wire [7:0] p02 = row2_col2;

    wire [7:0] p10 = r1_0;
    wire [7:0] p11 = r1_1;
    wire [7:0] p12 = row1_col2;

    wire [7:0] p20 = r0_0;
    wire [7:0] p21 = r0_1;
    wire [7:0] p22 = pixel_in;

    wire signed [11:0] gx =
        -$signed({4'b0, p00}) + $signed({4'b0, p02})
        -($signed({4'b0, p10}) <<< 1) + ($signed({4'b0, p12}) <<< 1)
        -$signed({4'b0, p20}) + $signed({4'b0, p22});

    wire signed [11:0] gy =
         $signed({4'b0, p00}) + ($signed({4'b0, p01}) <<< 1) + $signed({4'b0, p02})
        -$signed({4'b0, p20}) - ($signed({4'b0, p21}) <<< 1) - $signed({4'b0, p22});

    wire [11:0] abs_gx = gx[11] ? (~gx + 1'b1) : gx;
    wire [11:0] abs_gy = gy[11] ? (~gy + 1'b1) : gy;
    wire [12:0] mag    = abs_gx + abs_gy;

    wire [7:0] mag_sat8 = (mag > 13'd255) ? 8'hFF : mag[7:0];

    // OUTPUT_BITS controls effective output precision.
    // Example:
    // OUTPUT_BITS = 8 -> uo_out = 0~255
    // OUTPUT_BITS = 4 -> uo_out = 0~15
    // OUTPUT_BITS = 1 -> uo_out = 0 or 1
    wire [7:0] edge_quantized = mag_sat8 >> OUTPUT_SHIFT;

    wire valid_window = (row >= 2) && (col >= 2);

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row <= 0;
            col <= 0;
            out <= 0;

            r0_0 <= 0;
            r0_1 <= 0;
            r1_0 <= 0;
            r1_1 <= 0;
            r2_0 <= 0;
            r2_1 <= 0;

            for (i = 0; i < IMG_SIZE; i = i + 1) begin
                linebuf1[i] <= 0;
                linebuf2[i] <= 0;
            end

        end else if (pixel_valid) begin

            if (valid_window)
                out <= edge_quantized;
            else
                out <= 8'd0;

            linebuf2[col] <= row1_col2;
            linebuf1[col] <= pixel_in;

            if (col == IMG_SIZE-1) begin
                col <= 0;

                r0_0 <= 0;
                r0_1 <= 0;
                r1_0 <= 0;
                r1_1 <= 0;
                r2_0 <= 0;
                r2_1 <= 0;

                if (row == IMG_SIZE-1)
                    row <= 0;
                else
                    row <= row + 1'b1;

            end else begin
                col <= col + 1'b1;

                r0_0 <= r0_1;
                r0_1 <= pixel_in;

                r1_0 <= r1_1;
                r1_1 <= row1_col2;

                r2_0 <= r2_1;
                r2_1 <= row2_col2;
            end
        end
    end

endmodule

`default_nettype wire
