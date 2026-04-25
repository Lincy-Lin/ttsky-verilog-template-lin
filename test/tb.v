`default_nettype none
`timescale 1ns / 1ps

module tb ();

  // Dump waveform
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  // Signals
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;

  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // Instantiate your module (改这里！)
  tt_um_edge_detect user_project (

`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif

      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );

  // Clock (10ns period)
  initial clk = 0;
  always #5 clk = ~clk;

  integer row, col;

  initial begin
    // Init
    rst_n = 0;
    ena   = 1;
    ui_in = 0;
    uio_in = 0;

    // Reset
    #20;
    rst_n = 1;

    // Wait a bit
    repeat (5) @(posedge clk);

    // Send 64x64 pixel stream
    for (row = 0; row < 64; row = row + 1) begin
      for (col = 0; col < 64; col = col + 1) begin
        @(posedge clk);
        ui_in[0] = 1'b1;         // pixel_valid
        uio_in   = row + col;    // simple gradient pattern
      end
    end

    // Stop valid
    @(posedge clk);
    ui_in[0] = 0;

    // Wait some cycles
    repeat (20) @(posedge clk);

    $finish;
  end

endmodule
