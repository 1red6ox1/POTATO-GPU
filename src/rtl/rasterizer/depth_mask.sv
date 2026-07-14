module depth_mask
import rasterizer_pkg::*;
#(
	parameter int unsigned FIFO_DEPTH = 8
) (
	input logic clk_i,
	input logic rst_ni,

	input logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] z_i,
	input logic                                   z_valid_i,
	output logic                                   z_ready_o,

	input logic [255:0] depth1_i,
	input logic         depth1_valid_i,
	output logic         depth1_ready_o,

	input logic [255:0] depth2_i,
	input logic         depth2_valid_i,
	output logic         depth2_ready_o,

	output logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] z_o,
	output logic [TILE_WIDTH-1:0]                  mask_o,
	output logic                                    out_valid_o,
	input logic                                     out_ready_i
);

	logic [TILE_WIDTH-1:0] mask_i;
	logic z_fifo_in_ready;
	logic mask_fifo_in_ready;
	logic z_fifo_valid;
	logic mask_fifo_valid;
	logic in_fire;

	assign in_fire = z_valid_i && depth1_valid_i && depth2_valid_i
	               && z_fifo_in_ready && mask_fifo_in_ready;
	assign z_ready_o = depth1_valid_i && depth2_valid_i
	                && z_fifo_in_ready && mask_fifo_in_ready;
	assign depth1_ready_o = z_valid_i && depth2_valid_i
	                     && z_fifo_in_ready && mask_fifo_in_ready;
	assign depth2_ready_o = z_valid_i && depth1_valid_i
	                     && z_fifo_in_ready && mask_fifo_in_ready;
	assign out_valid_o = z_fifo_valid && mask_fifo_valid;

	always_comb begin
		mask_i = '0;
		for (int i = 0; i < TILE_WIDTH; i++) begin
			if (i < TILE_WIDTH / 2) begin
				mask_i[i] = z_i[i] > depth1_i[16*i+:16];
			end else begin
				mask_i[i] = z_i[i] > depth2_i[16*(i - TILE_WIDTH / 2)+:16];
			end
		end
	end

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
