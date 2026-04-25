`timescale 1ns/1ps

module tt_um_edge_detect #(
    parameter IMG_WIDTH       = 8,
    parameter IMG_HEIGHT      = 8,
    parameter FIFO_DEPTH      = 64,
    parameter FIFO_ADDR_WIDTH = 8
)(
    input  wire       VGND,
    input  wire       VDPWR,

    input  wire       clk,
    input  wire       rst_n,

    input  wire       in_wr_en,
    input  wire [7:0] in_pixel,
    output wire       in_full,

    input  wire       out_rd_en,
    output wire [7:0] out_pixel,
    output wire       out_empty,

    output wire       frame_done
);

    wire [7:0] input_fifo_dout;
    wire       input_fifo_empty;
    wire       input_fifo_rd_en;
    wire [FIFO_ADDR_WIDTH:0] input_fifo_count;

    reg        input_fifo_valid_d;

    wire [7:0] sobel_edge;
    wire       sobel_valid;

    wire       output_fifo_full;
    wire [FIFO_ADDR_WIDTH:0] output_fifo_count;

    wire _unused = &{VGND, VDPWR};

    // Read input FIFO when it has data and output FIFO can accept Sobel output.
    assign input_fifo_rd_en = (!input_fifo_empty) && (!output_fifo_full);

    // fifo_sync is synchronous-read, so data is valid one clock after rd_en.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            input_fifo_valid_d <= 1'b0;
        else
            input_fifo_valid_d <= input_fifo_rd_en;
    end

    fifo_sync #(
        .DATA_WIDTH(8),
        .DEPTH(FIFO_DEPTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) input_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(in_wr_en),
        .din(in_pixel),
        .full(in_full),
        .rd_en(input_fifo_rd_en),
        .dout(input_fifo_dout),
        .empty(input_fifo_empty),
        .count(input_fifo_count)
    );

    sobel_stream_core #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) sobel_core (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(input_fifo_dout),
        .pixel_valid(input_fifo_valid_d),
        .edge_out(sobel_edge),
        .edge_valid(sobel_valid),
        .frame_done(frame_done)
    );

    fifo_sync #(
        .DATA_WIDTH(8),
        .DEPTH(FIFO_DEPTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) output_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(sobel_valid),
        .din(sobel_edge),
        .full(output_fifo_full),
        .rd_en(out_rd_en),
        .dout(out_pixel),
        .empty(out_empty),
        .count(output_fifo_count)
    );

endmodule
