`timescale 1ns/1ps
module tt_um_edge_detect #(
    parameter IMG_WIDTH       = 8,
    parameter IMG_HEIGHT      = 8,
    parameter FIFO_DEPTH      = 16,
    parameter FIFO_ADDR_WIDTH = 4
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
    // Map TT ports to internal signals
    wire       in_wr_en  = ui_in[0];
    wire       out_rd_en = ui_in[1];
    wire [7:0] in_pixel  = uio_in;

    wire       in_full;
    wire [7:0] out_pixel;
    wire       out_empty;
    wire       frame_done;

    assign uo_out[0]   = in_full;
    assign uo_out[1]   = out_empty;
    assign uo_out[2]   = frame_done;
    assign uo_out[7:3] = 5'b0;
    assign uio_out     = out_pixel;
    assign uio_oe      = 8'hFF;

    wire [7:0] input_fifo_dout;
    wire       input_fifo_empty;
    wire       input_fifo_rd_en;
    wire [FIFO_ADDR_WIDTH:0] input_fifo_count;
    reg        input_fifo_valid_d;
    wire [7:0] sobel_edge;
    wire       sobel_valid;
    wire       output_fifo_full;
    wire [FIFO_ADDR_WIDTH:0] output_fifo_count;

    // suppress unused warnings
    wire _unused = &{ena, uio_in, input_fifo_count, output_fifo_count};

    assign input_fifo_rd_en = (!input_fifo_empty) && (!output_fifo_full);

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
