module worker
import rasterizer_pkg::*;
#(
	parameter int unsigned DIVIDERS = 8,
	parameter int unsigned FIFO_DEPTH = 4,
	parameter int unsigned OUTPUT_FIFO_DEPTH = 4
) (
	input logic clk_i,
	input logic rst_ni,

	input rasterization_param_t                        param_i,
	input logic [$clog2(FRAME_WIDTH / TILE_WIDTH)-1:0] tile_x_i,
	input logic [$clog2(FRAME_HEIGHT)-1:0]             y_i,
	input logic                                        in_valid_i,
	output logic                                       in_ready_o,

	output rvlab_ddr_pkg::ddr3_h2d_t ddr_o [2:0],
	input rvlab_ddr_pkg::ddr3_d2h_t ddr_i [2:0]
);

	import rvlab_ddr_pkg::*;

	logic input_fire;
	logic output_fifo_in_ready;
	logic coverage_in_ready;
	logic depth_calculation_in_ready;
	logic depth1_in_ready;
	logic depth2_in_ready;
	logic one_q_in_ready;
	logic uq_vq_in_ready;
	chunk_id_t input_chunk_id;

	logic [TILE_WIDTH-1:0] coverage_data;
	logic coverage_valid;
	logic coverage_ready;
	logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] calculated_depth;
	logic depth_calculation_valid;
	logic depth_calculation_ready;
	logic [255:0] stored_depth1;
	logic [255:0] stored_depth2;
	logic stored_depth1_valid;
	logic stored_depth2_valid;
	logic stored_depth1_ready;
	logic stored_depth2_ready;

	logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] depth_mask_depth;
	logic [TILE_WIDTH-1:0] depth_mask_data;
	logic depth_mask_valid;
	logic depth_mask_ready;
	logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] masked_depth;
	logic [TILE_WIDTH-1:0] masked_data;
	logic masked_valid;
	logic masked_ready;

	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] one_q_data;
	logic one_q_valid;
	logic one_q_ready;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] uq_data;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] vq_data;
	logic uq_vq_valid;
	logic uq_vq_ready;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] u_data;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] v_data;
	logic uv_valid;
	logic uv_ready;
	logic [255:0] red_data;
	logic [255:0] green_data;
	logic [255:0] blue_data;
	logic color_valid;
	logic color_ready;

	logic [255:0] writer_data;
	logic [31:0] writer_mask;
	logic [23:0] writer_address;
	logic writer_valid;
	logic writer_ready;

	assign input_chunk_id = '{
		fbid_color: param_i.fbid_color,
		fbid_depth: param_i.fbid_depth,
		tile_x: tile_x_i,
		y: y_i
	};

	assign in_ready_o = output_fifo_in_ready
	                 && coverage_in_ready
	                 && depth_calculation_in_ready
	                 && depth1_in_ready
	                 && depth2_in_ready
	                 && one_q_in_ready
	                 && uq_vq_in_ready;
	assign input_fire = in_valid_i && in_ready_o;

	coverage_mask #(
		.FIFO_DEPTH (FIFO_DEPTH)
	) coverage_mask_i (
		.clk_i,
		.rst_ni,
		.param_i,
		.tile_x_i,
		.y_i,
		.in_valid_i  (input_fire),
		.in_ready_o  (coverage_in_ready),
		.mask_o      (coverage_data),
		.out_valid_o (coverage_valid),
		.out_ready_i (coverage_ready)
	);

	depth_calculation #(
		.FIFO_DEPTH (FIFO_DEPTH)
	) depth_calculation_i (
		.clk_i,
		.rst_ni,
		.param_i,
		.tile_x_i,
		.y_i,
		.in_valid_i  (input_fire),
		.in_ready_o  (depth_calculation_in_ready),
		.depth_o     (calculated_depth),
		.out_valid_o (depth_calculation_valid),
		.out_ready_i (depth_calculation_ready)
	);

	depth_reader #(
		.DEPTH_PART (1'b0),
		.FIFO_DEPTH (FIFO_DEPTH)
	) depth_reader1_i (
		.clk_i,
		.rst_ni,
		.fbid_depth_i (param_i.fbid_depth),
		.tile_x_i,
		.y_i,
		.in_valid_i   (input_fire),
		.in_ready_o   (depth1_in_ready),
		.out_data_o   (stored_depth1),
		.out_valid_o  (stored_depth1_valid),
		.out_ready_i  (stored_depth1_ready),
		.ddr_o        (ddr_o[1]),
		.ddr_i        (ddr_i[1])
	);

	depth_reader #(
		.DEPTH_PART (1'b1),
		.FIFO_DEPTH (FIFO_DEPTH)
	) depth_reader2_i (
		.clk_i,
		.rst_ni,
		.fbid_depth_i (param_i.fbid_depth),
		.tile_x_i,
		.y_i,
		.in_valid_i   (input_fire),
		.in_ready_o   (depth2_in_ready),
		.out_data_o   (stored_depth2),
		.out_valid_o  (stored_depth2_valid),
		.out_ready_i  (stored_depth2_ready),
		.ddr_o        (ddr_o[2]),
		.ddr_i        (ddr_i[2])
	);

	depth_mask #(
		.FIFO_DEPTH (FIFO_DEPTH)
	) depth_mask_i (
		.clk_i,
		.rst_ni,
		.z_i             (calculated_depth),
		.z_valid_i       (depth_calculation_valid),
		.z_ready_o       (depth_calculation_ready),
		.depth1_i        (stored_depth1),
		.depth1_valid_i  (stored_depth1_valid),
		.depth1_ready_o  (stored_depth1_ready),
		.depth2_i        (stored_depth2),
		.depth2_valid_i  (stored_depth2_valid),
		.depth2_ready_o  (stored_depth2_ready),
		.z_o             (depth_mask_depth),
		.mask_o          (depth_mask_data),
		.out_valid_o     (depth_mask_valid),
		.out_ready_i     (depth_mask_ready)
	);

	mask #(
		.FIFO_DEPTH (FIFO_DEPTH)
	) mask_i (
		.clk_i,
		.rst_ni,
		.coverage_mask_i (coverage_data),
		.coverage_valid_i(coverage_valid),
		.coverage_ready_o(coverage_ready),
		.z_i             (depth_mask_depth),
		.depth_mask_i    (depth_mask_data),
		.depth_valid_i   (depth_mask_valid),
		.depth_ready_o   (depth_mask_ready),
		.z_o             (masked_depth),
		.mask_o          (masked_data),
		.out_valid_o     (masked_valid),
		.out_ready_i     (masked_ready)
	);

	calculate_1q #(
		.DIVIDERS   (DIVIDERS),
		.FIFO_DEPTH (FIFO_DEPTH)
	) calculate_1q_i (
		.clk_i,
		.rst_ni,
		.param_i,
		.tile_x_i,
		.y_i,
		.in_valid_i  (input_fire),
		.in_ready_o  (one_q_in_ready),
		.one_q_o     (one_q_data),
		.out_valid_o (one_q_valid),
		.out_ready_i (one_q_ready)
	);

	uq_vq_calculation #(
		.FIFO_DEPTH (FIFO_DEPTH)
	) uq_vq_calculation_i (
		.clk_i,
		.rst_ni,
		.param_i,
		.tile_x_i,
		.y_i,
		.in_valid_i  (input_fire),
		.in_ready_o  (uq_vq_in_ready),
		.uq_o        (uq_data),
		.vq_o        (vq_data),
		.out_valid_o (uq_vq_valid),
		.out_ready_i (uq_vq_ready)
	);

	uv_calculation #(
		.FIFO_DEPTH (FIFO_DEPTH)
	) uv_calculation_i (
		.clk_i,
		.rst_ni,
		.one_q_i       (one_q_data),
		.one_q_valid_i (one_q_valid),
		.one_q_ready_o (one_q_ready),
		.uq_i           (uq_data),
		.vq_i           (vq_data),
		.uq_vq_valid_i  (uq_vq_valid),
		.uq_vq_ready_o  (uq_vq_ready),
		.u_o            (u_data),
		.v_o            (v_data),
		.out_valid_o    (uv_valid),
		.out_ready_i    (uv_ready)
	);

	color_calculation #(
		.FIFO_DEPTH (FIFO_DEPTH)
	) color_calculation_i (
		.clk_i,
		.rst_ni,
		.u_i         (u_data),
		.v_i         (v_data),
		.in_valid_i  (uv_valid),
		.in_ready_o  (uv_ready),
		.red_o       (red_data),
		.green_o     (green_data),
		.blue_o      (blue_data),
		.out_valid_o (color_valid),
		.out_ready_i (color_ready)
	);

	worker_fifo #(
		.FIFO_DEPTH (OUTPUT_FIFO_DEPTH)
	) worker_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i       (1'b0),
		.chunk_id_i    (input_chunk_id),
		.in_valid_i    (input_fire),
		.in_ready_o    (output_fifo_in_ready),
		.mask_i        (masked_data),
		.depth_i       (masked_depth),
		.mask_valid_i  (masked_valid),
		.mask_ready_o  (masked_ready),
		.red_i         (red_data),
		.green_i       (green_data),
		.blue_i        (blue_data),
		.color_valid_i (color_valid),
		.color_ready_o (color_ready),
		.data_o        (writer_data),
		.write_mask_o  (writer_mask),
		.address_o     (writer_address),
		.out_valid_o   (writer_valid),
		.out_ready_i   (writer_ready)
	);

	writer writer_i (
		.clk_i,
		.rst_ni,
		.data_i     (writer_data),
		.mask_i     (writer_mask),
		.address_i  (writer_address),
		.in_valid_i (writer_valid),
		.in_ready_o (writer_ready),
		.ddr_o      (ddr_o[0]),
		.ddr_i      (ddr_i[0])
	);

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (input_fire) begin
			$display("worker,%0t,input,tile,%0d,y,%0d", $time, tile_x_i, y_i);
		end
	end
`endif

endmodule
