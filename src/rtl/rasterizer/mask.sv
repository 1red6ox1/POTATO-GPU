module mask
import rasterizer_pkg::*;
#(
	parameter int unsigned FIFO_DEPTH = 8
) (
	input logic clk_i,
	input logic rst_ni,

	input logic [TILE_WIDTH-1:0] coverage_mask_i,
	input logic                  coverage_valid_i,
	output logic                 coverage_ready_o,

	input logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] z_i,
	input logic [TILE_WIDTH-1:0]                  depth_mask_i,
	input logic                                   depth_valid_i,
	output logic                                  depth_ready_o,

	output logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] z_o,
	output logic [TILE_WIDTH-1:0]                  mask_o,
	output logic                                   out_valid_o,
	input logic                                    out_ready_i
);

	logic [TILE_WIDTH-1:0] mask_i;
	logic z_fifo_in_ready;
	logic mask_fifo_in_ready;
	logic z_fifo_valid;
	logic mask_fifo_valid;
	logic in_fire;

	assign mask_i = coverage_mask_i & depth_mask_i;
	assign in_fire = coverage_valid_i && depth_valid_i && z_fifo_in_ready && mask_fifo_in_ready;
	assign coverage_ready_o = depth_valid_i && z_fifo_in_ready && mask_fifo_in_ready;
	assign depth_ready_o = coverage_valid_i && z_fifo_in_ready && mask_fifo_in_ready;
	assign out_valid_o = z_fifo_valid && mask_fifo_valid;

	my_fifo #(
		.Width (TILE_WIDTH * DEPTH_WIDTH),
		.Pass  (1'b0),
		.Depth (FIFO_DEPTH)
	) z_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i      (1'b0),
		.in_data_i    (z_i),
		.in_valid_i   (in_fire),
		.in_ready_o   (z_fifo_in_ready),
		.out_data_o   (z_o),
		.out_valid_o  (z_fifo_valid),
		.out_ready_i  (out_ready_i && out_valid_o),
		.depth_o      ()
	);

	my_fifo #(
		.Width (TILE_WIDTH),
		.Pass  (1'b0),
		.Depth (FIFO_DEPTH)
	) mask_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i      (1'b0),
		.in_data_i    (mask_i),
		.in_valid_i   (in_fire),
		.in_ready_o   (mask_fifo_in_ready),
		.out_data_o   (mask_o),
		.out_valid_o  (mask_fifo_valid),
		.out_ready_i  (out_ready_i && out_valid_o),
		.depth_o      ()
	);

endmodule
