module core_fifo
import rasterizer_pkg::*;
#(
  parameter int unsigned FIFO_DEPTH = 4
) (
  input logic clk_i,
  input logic rst_ni,
  input logic clear_i,

  input rasterization_param_t                        param_i,
  input logic [$clog2(FRAME_WIDTH / TILE_WIDTH)-1:0] tile_x_i,
  input logic [$clog2(FRAME_HEIGHT)-1:0]             y_i,
  input logic                                        in_valid_i,
  output logic                                       in_ready_o,

  output rasterization_param_t                        param_o,
  output logic [$clog2(FRAME_WIDTH / TILE_WIDTH)-1:0] tile_x_o,
  output logic [$clog2(FRAME_HEIGHT)-1:0]             y_o,
  output logic                                        out_valid_o,
  input logic                                         out_ready_i,
  output logic [((($clog2(FIFO_DEPTH + 1)) == 0) ? 1 : $clog2(FIFO_DEPTH + 1))-1:0] depth_o
);

  logic param_in_ready;
  logic tile_x_in_ready;
  logic y_in_ready;
  logic param_valid;
  logic tile_x_valid;
  logic y_valid;

  assign in_ready_o  = param_in_ready && tile_x_in_ready && y_in_ready;
  assign out_valid_o = param_valid && tile_x_valid && y_valid;

  my_fifo #(
    .Width ($bits(rasterization_param_t)),
    .Pass  (1'b0),
    .Depth (FIFO_DEPTH)
  ) param_fifo_i (
    .clk_i,
    .rst_ni,
    .clear_i,
    .in_data_i  (param_i),
    .in_valid_i (in_valid_i && in_ready_o),
    .in_ready_o (param_in_ready),
    .out_data_o (param_o),
    .out_valid_o(param_valid),
    .out_ready_i(out_ready_i && out_valid_o),
    .depth_o    (depth_o)
  );

  my_fifo #(
    .Width ($clog2(FRAME_WIDTH / TILE_WIDTH)),
    .Pass  (1'b0),
    .Depth (FIFO_DEPTH)
  ) tile_x_fifo_i (
    .clk_i,
    .rst_ni,
    .clear_i,
    .in_data_i  (tile_x_i),
    .in_valid_i (in_valid_i && in_ready_o),
    .in_ready_o (tile_x_in_ready),
    .out_data_o (tile_x_o),
    .out_valid_o(tile_x_valid),
    .out_ready_i(out_ready_i && out_valid_o),
    .depth_o    ()
  );

  my_fifo #(
    .Width ($clog2(FRAME_HEIGHT)),
    .Pass  (1'b0),
    .Depth (FIFO_DEPTH)
  ) y_fifo_i (
    .clk_i,
    .rst_ni,
    .clear_i,
    .in_data_i  (y_i),
    .in_valid_i (in_valid_i && in_ready_o),
    .in_ready_o (y_in_ready),
    .out_data_o (y_o),
    .out_valid_o(y_valid),
    .out_ready_i(out_ready_i && out_valid_o),
    .depth_o    ()
  );

endmodule
