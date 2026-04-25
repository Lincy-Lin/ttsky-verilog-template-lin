`timescale 1ns/1ps
module tt_um_edge_detect #(
    parameter IMG_WIDTH  = 8,
    parameter IMG_HEIGHT = 8
)(
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
    wire _unused = &{ena, ui_in[7:1], uio_in};

    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    // Internal signals
    wire       pixel_valid = ui_in[0];
    wire [7:0] pixel_in    = uio_in;

    reg [7:0] edge_out;
    reg       edge_valid;
    reg       frame_done;

    assign uo_out = edge_out;

    // Sobel line buffers
    integer i;
    reg [7:0] linebuf1 [0:IMG_WIDTH-1];
    reg [7:0] linebuf2 [0:IMG_WIDTH-1];
    reg [7:0] row0_col0, row0_col1;
    reg [7:0] row1_col0, row1_col1;
    reg [7:0] row2_col0, row2_col1;
    reg [2:0] row;
    reg [2:0] col;

    wire [7:0] row1_col2 = linebuf1[col];
    wire [7:0] row2_col2 = linebuf2[col];

    wire [7:0] p00 = row2_col0;
    wire [7:0] p01 = row2_col1;
    wire [7:0] p02 = row2_col2;
    wire [7:0] p10 = row1_col0;
    wire [7:0] p12 = row1_col2;
    wire [7:0] p20 = row0_col0;
    wire [7:0] p21 = row0_col1;
    wire [7:0] p22 = pixel_in;

    wire signed [11:0] gx;
    wire signed [11:0] gy;
    wire [11:0] abs_gx;
    wire [11:0] abs_gy;
    wire [12:0] mag;

    assign gx = -$signed({4'b0, p00}) + $signed({4'b0, p02})
                - ($signed({4'b0, p10}) <<< 1) + ($signed({4'b0, p12}) <<< 1)
                - $signed({4'b0, p20}) + $signed({4'b0, p22});
    assign gy =  $signed({4'b0, p00}) + ($signed({4'b0, p01}) <<< 1) + $signed({4'b0, p02})
                - $signed({4'b0, p20}) - ($signed({4'b0, p21}) <<< 1) - $signed({4'b0, p22});

    assign abs_gx = gx[11] ? (~gx + 1'b1) : gx;
    assign abs_gy = gy[11] ? (~gy + 1'b1) : gy;
    assign mag = abs_gx + abs_gy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row        <= 3'd0;
            col        <= 3'd0;
            edge_out   <= 8'd0;
            edge_valid <= 1'b0;
            frame_done <= 1'b0;
            row0_col0  <= 8'd0;
            row0_col1  <= 8'd0;
            row1_col0  <= 8'd0;
            row1_col1  <= 8'd0;
            row2_col0  <= 8'd0;
            row2_col1  <= 8'd0;
            for (i = 0; i < IMG_WIDTH; i = i + 1) begin
                linebuf1[i] <= 8'd0;
                linebuf2[i] <= 8'd0;
            end
        end else begin
            edge_valid <= 1'b0;
            frame_done <= 1'b0;
            if (pixel_valid) begin
                if ((row >= 3'd2) && (col >= 3'd2)) begin
                    edge_valid <= 1'b1;
                    if (mag > 13'd255)
                        edge_out <= 8'd255;
                    else
                        edge_out <= mag[7:0];
                end else begin
                    edge_valid <= 1'b0;
                    edge_out   <= 8'd0;
                end
                linebuf2[col] <= row1_col2;
                linebuf1[col] <= pixel_in;
                if (col == 3'(IMG_WIDTH-1)) begin
                    row0_col0 <= 8'd0;
                    row0_col1 <= 8'd0;
                    row1_col0 <= 8'd0;
                    row1_col1 <= 8'd0;
                    row2_col0 <= 8'd0;
                    row2_col1 <= 8'd0;
                    col <= 3'd0;
                    if (row == 3'(IMG_HEIGHT-1)) begin
                        row <= 3'd0;
                        frame_done <= 1'b1;
                    end else begin
                        row <= row + 3'd1;
                    end
                end else begin
                    row0_col0 <= row0_col1;
                    row0_col1 <= pixel_in;
                    row1_col0 <= row1_col1;
                    row1_col1 <= row1_col2;
                    row2_col0 <= row2_col1;
                    row2_col1 <= row2_col2;
                    col <= col + 3'd1;
                end
            end
        end
    end
endmodule
