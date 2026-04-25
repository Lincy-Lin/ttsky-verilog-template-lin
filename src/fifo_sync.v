`timescale 1ns/1ps

module fifo_sync #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 64,
    parameter ADDR_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] din,
    output wire                  full,

    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] dout,
    output wire                  empty,

    output reg  [ADDR_WIDTH:0]   count
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;

    assign full  = (count == DEPTH);
    assign empty = (count == 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {ADDR_WIDTH{1'b0}};
            rd_ptr <= {ADDR_WIDTH{1'b0}};
            dout   <= {DATA_WIDTH{1'b0}};
            count  <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: begin
                    mem[wr_ptr] <= din;
                    wr_ptr <= wr_ptr + 1'b1;
                    count  <= count + 1'b1;
                end

                2'b01: begin
                    dout   <= mem[rd_ptr];
                    rd_ptr <= rd_ptr + 1'b1;
                    count  <= count - 1'b1;
                end

                2'b11: begin
                    mem[wr_ptr] <= din;
                    wr_ptr <= wr_ptr + 1'b1;

                    dout   <= mem[rd_ptr];
                    rd_ptr <= rd_ptr + 1'b1;

                    count  <= count;
                end

                default: begin
                    count <= count;
                end
            endcase
        end
    end

endmodule
