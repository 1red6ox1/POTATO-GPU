module uv_calculation
import rasterizer_pkg::*;
#(
	parameter int unsigned FIFO_DEPTH = 8
) (
	input logic clk_i,
	input logic rst_ni,

	input logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] one_q_i,
	input logic                                   one_q_valid_i,
	output logic                                   one_q_ready_o,

	input logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] uq_i,
	input logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] vq_i,
	input logic                                   uq_vq_valid_i,
	output logic                                   uq_vq_ready_o,

	output logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] u_o,
	output logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] v_o,
	output logic                                   out_valid_o,
	input logic                                    out_ready_i
);

	logic signed [2*UVQ_WIDTH-1:0] u_product [TILE_WIDTH-1:0];
	logic signed [2*UVQ_WIDTH-1:0] v_product [TILE_WIDTH-1:0];
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] u_i;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] v_i;
	logic u_fifo_in_ready;
	logic v_fifo_in_ready;
	logic u_valid;
	logic v_valid;
	logic in_fire;

	assign in_fire = one_q_valid_i && uq_vq_valid_i
	              && u_fifo_in_ready && v_fifo_in_ready;
	assign one_q_ready_o = uq_vq_valid_i
	                   && u_fifo_in_ready && v_fifo_in_ready;
	assign uq_vq_ready_o = one_q_valid_i
	                   && u_fifo_in_ready && v_fifo_in_ready;
	assign out_valid_o = u_valid && v_valid;

	always_comb begin
		for (int pixel = 0; pixel < TILE_WIDTH; pixel++) begin
			u_product[pixel] = $signed(uq_i[pixel]) * $signed(one_q_i[pixel]);
			v_product[pixel] = $signed(vq_i[pixel]) * $signed(one_q_i[pixel]);
			u_i[pixel] = UVQ_WIDTH'(u_product[pixel] >>> UVQ_FRAC_WIDTH);
			v_i[pixel] = UVQ_WIDTH'(v_product[pixel] >>> UVQ_FRAC_WIDTH);
		end
	end

	my_fifo #(
		.Width (TILE_WIDTH * UVQ_WIDTH),
		.Pass  (1'b0),
		.Depth (FIFO_DEPTH)
	) u_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i      (1'b0),
		.in_data_i    (u_i),
		.in_valid_i   (in_fire),
		.in_ready_o   (u_fifo_in_ready),
		.out_data_o   (u_o),
		.out_valid_o  (u_valid),
		.out_ready_i  (out_ready_i && out_valid_o),
		.depth_o      ()
	);

	my_fifo #(
		.Width (TILE_WIDTH * UVQ_WIDTH),
		.Pass  (1'b0),
		.Depth (FIFO_DEPTH)
	) v_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i      (1'b0),
		.in_data_i    (v_i),
		.in_valid_i   (in_fire),
		.in_ready_o   (v_fifo_in_ready),
		.out_data_o   (v_o),
		.out_valid_o  (v_valid),
		.out_ready_i  (out_ready_i && out_valid_o),
		.depth_o      ()
	);

endmodule
