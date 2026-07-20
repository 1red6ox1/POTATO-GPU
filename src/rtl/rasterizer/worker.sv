module worker (
	input logic clk_i,
	input logic rst_ni,

	input  rasterizer_pkg::triangle_param_t param_i,
	input  logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x_i,
	input  logic [rasterizer_pkg::FRAME_Y_WIDTH-1:0] y_i,
	input  logic [rasterizer_pkg::TILE_WIDTH-1:0] coverage_mask_i,
	input  logic in_valid_i,
	output logic in_ready_o,

	output logic [1:0] fbid_color_o,
	output logic [1:0] fbid_depth_o,
	output logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0] triangle_id_o,
	output logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x_o,
	output logic [rasterizer_pkg::FRAME_Y_WIDTH-1:0] y_o,
	output logic [255:0] red_o,
	output logic [255:0] green_o,
	output logic [255:0] blue_o,
	output logic [255:0] depth1_o,
	output logic [255:0] depth2_o,
	output logic [rasterizer_pkg::TILE_WIDTH-1:0] mask_o,
	output logic out_valid_o,
	input  logic out_ready_i,

	output rvlab_ddr_pkg::ddr3_h2d_t ddr1_o,
	input  rvlab_ddr_pkg::ddr3_d2h_t ddr1_i,
	output rvlab_ddr_pkg::ddr3_h2d_t ddr2_o,
	input  rvlab_ddr_pkg::ddr3_d2h_t ddr2_i
);

	import rasterizer_pkg::*;
	import rvlab_ddr_pkg::*;

	localparam int unsigned TextureWidth = 32;
	localparam int unsigned TextureHeight = 32;
	localparam int unsigned TextureUWidth = $clog2(TextureWidth);
	localparam int unsigned TextureVWidth = $clog2(TextureHeight);
	localparam logic signed [UVQ_WIDTH-1:0] UVQ_ONE = UVQ_WIDTH'(1) << UVQ_FRAC_WIDTH;

	logic depth_calculation_ready;
	logic depth_reader1_ready;
	logic depth_reader2_ready;
	logic uq_vq_ready;
	logic one_q_ready;
	logic metadata_ready;

	logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] z_i;
	logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] z_mask;
	logic z_valid;
	logic z_ready;
	logic [255:0] depth1;
	logic depth1_valid;
	logic depth1_ready;
	logic [255:0] depth2;
	logic depth2_valid;
	logic depth2_ready;

	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] uq;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] vq;
	logic [TRIANGLE_ID_WIDTH-1:0] triangle_id;
	logic [TEXTURE_ID_WIDTH-1:0] texture_id;
	logic uq_vq_valid;
	logic uq_vq_output_ready;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] one_q;
	logic one_q_valid;
	logic one_q_output_ready;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] u;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] v;
	logic [TRIANGLE_ID_WIDTH-1:0] uv_triangle_id;
	logic [TEXTURE_ID_WIDTH-1:0] uv_texture_id;
	logic uv_valid;
	logic uv_output_ready;
	logic [TILE_WIDTH-1:0][TextureUWidth-1:0] texture_u;
	logic [TILE_WIDTH-1:0][TextureVWidth-1:0] texture_v;
	logic [TILE_WIDTH-1:0][7:0] texel;
	logic [TILE_WIDTH-1:0][7:0] palette_index;
	logic [TRIANGLE_ID_WIDTH-1:0] texture_triangle_id;
	logic texture_valid;
	logic texture_output_ready;
	logic [TRIANGLE_ID_WIDTH-1:0] palette_triangle_id;
	logic palette_valid;
	logic palette_output_ready;
	logic [TILE_WIDTH-1:0] depth_mask;
	logic depth_valid;
	logic depth_output_ready;
	logic [255:0] red;
	logic [255:0] green;
	logic [255:0] blue;

	assign in_ready_o = depth_calculation_ready && depth_reader1_ready && depth_reader2_ready && uq_vq_ready && one_q_ready && metadata_ready;

	always_comb begin
		texture_u = '0;
		texture_v = '0;
		palette_index = '0;

		for (int pixel = 0; pixel < TILE_WIDTH; pixel++) begin
			if ($signed(u[pixel]) >= UVQ_ONE) begin
				texture_u[pixel] = '1;
			end else if ($signed(u[pixel]) > 0) begin
				texture_u[pixel] = u[pixel][UVQ_FRAC_WIDTH-1 -: TextureUWidth];
			end

			if ($signed(v[pixel]) >= UVQ_ONE) begin
				texture_v[pixel] = '1;
			end else if ($signed(v[pixel]) > 0) begin
				texture_v[pixel] = v[pixel][UVQ_FRAC_WIDTH-1 -: TextureVWidth];
			end

			palette_index[pixel] = texel[pixel];
		end
	end

	depth_calculation depth_calculation_i (
		.clk_i,
		.rst_ni,
		.param_i,
		.tile_x_i,
		.y_i,
		.in_valid_i (in_valid_i && in_ready_o),
		.in_ready_o (depth_calculation_ready),
		.depth_o    (z_i),
		.out_valid_o(z_valid),
		.out_ready_i(z_ready)
	);

	depth_reader #(
		.Half (1'b0)
	) depth_reader1_i (
		.clk_i,
		.rst_ni,
		.fbid_i     (param_i.fbid_depth),
		.tile_x_i,
		.y_i,
		.mask_i     (coverage_mask_i[TILE_WIDTH / 2 - 1:0]),
		.in_valid_i (in_valid_i && in_ready_o),
		.in_ready_o (depth_reader1_ready),
		.out_data_o (depth1),
		.out_valid_o(depth1_valid),
		.out_ready_i(depth1_ready),
		.ddr_o      (ddr1_o),
		.ddr_i      (ddr1_i)
	);

	depth_reader #(
		.Half (1'b1)
	) depth_reader2_i (
		.clk_i,
		.rst_ni,
		.fbid_i     (param_i.fbid_depth),
		.tile_x_i,
		.y_i,
		.mask_i     (coverage_mask_i[TILE_WIDTH - 1:TILE_WIDTH / 2]),
		.in_valid_i (in_valid_i && in_ready_o),
		.in_ready_o (depth_reader2_ready),
		.out_data_o (depth2),
		.out_valid_o(depth2_valid),
		.out_ready_i(depth2_ready),
		.ddr_o      (ddr2_o),
		.ddr_i      (ddr2_i)
	);

	depth_mask depth_mask_i (
		.clk_i,
		.rst_ni,
		.z_i          (z_i),
		.z_valid_i    (z_valid),
		.z_ready_o    (z_ready),
		.depth1_i     (depth1),
		.depth1_valid_i(depth1_valid),
		.depth1_ready_o(depth1_ready),
		.depth2_i     (depth2),
		.depth2_valid_i(depth2_valid),
		.depth2_ready_o(depth2_ready),
		.z_o          (z_mask),
		.mask_o       (depth_mask),
		.out_valid_o  (depth_valid),
		.out_ready_i  (depth_output_ready)
	);

	uq_vq_calculation uq_vq_calculation_i (
		.clk_i,
		.rst_ni,
		.param_i,
		.tile_x_i,
		.y_i,
		.in_valid_i (in_valid_i && in_ready_o),
		.in_ready_o (uq_vq_ready),
		.uq_o       (uq),
		.vq_o       (vq),
		.triangle_id_o(triangle_id),
		.texture_id_o(texture_id),
		.out_valid_o(uq_vq_valid),
		.out_ready_i(uq_vq_output_ready)
	);

	calculate_1q calculate_1q_i (
		.clk_i,
		.rst_ni,
		.param_i,
		.tile_x_i,
		.y_i,
		.in_valid_i (in_valid_i && in_ready_o),
		.in_ready_o (one_q_ready),
		.one_q_o    (one_q),
		.out_valid_o(one_q_valid),
		.out_ready_i(one_q_output_ready)
	);

	calculate_uv calculate_uv_i (
		.clk_i,
		.rst_ni,
		.one_q_i      (one_q),
		.one_q_valid_i(one_q_valid),
		.one_q_ready_o(one_q_output_ready),
		.uq_i         (uq),
		.vq_i         (vq),
		.triangle_id_i(triangle_id),
		.texture_id_i (texture_id),
		.uq_vq_valid_i(uq_vq_valid),
		.uq_vq_ready_o(uq_vq_output_ready),
		.u_o          (u),
		.v_o          (v),
		.triangle_id_o(uv_triangle_id),
		.texture_id_o (uv_texture_id),
		.out_valid_o  (uv_valid),
		.out_ready_i  (uv_output_ready)
	);

	texture_memory #(
		.TextureWidth (TextureWidth),
		.TextureHeight(TextureHeight)
	) texture_memory_i (
		.clk_i,
		.rst_ni,
		.u_i          (texture_u),
		.v_i          (texture_v),
		.texture_id_i (uv_texture_id),
		.triangle_id_i(uv_triangle_id),
		.in_valid_i   (uv_valid),
		.in_ready_o   (uv_output_ready),
		.texel_o      (texel),
		.triangle_id_o(texture_triangle_id),
		.out_valid_o  (texture_valid),
		.out_ready_i  (texture_output_ready)
	);

	texture_palette texture_palette_i (
		.clk_i,
		.rst_ni,
		.index_i      (palette_index),
		.triangle_id_i(texture_triangle_id),
		.in_valid_i   (texture_valid),
		.in_ready_o   (texture_output_ready),
		.red_o        (red),
		.green_o      (green),
		.blue_o       (blue),
		.triangle_id_o(palette_triangle_id),
		.out_valid_o  (palette_valid),
		.out_ready_i  (palette_output_ready)
	);

	output_fifo output_fifo_i (
		.clk_i,
		.rst_ni,
		.fbid_color_i     (param_i.fbid_color),
		.fbid_depth_i     (param_i.fbid_depth),
		.tile_x_i,
		.y_i,
		.coverage_mask_i,
		.metadata_valid_i  (in_valid_i && in_ready_o),
		.metadata_ready_o  (metadata_ready),
		.z_i              (z_mask),
		.depth_mask_i      (depth_mask),
		.depth_valid_i     (depth_valid),
		.depth_ready_o     (depth_output_ready),
		.red_i             (red),
		.green_i           (green),
		.blue_i            (blue),
		.color_valid_i     (palette_valid),
		.triangle_id_i     (palette_triangle_id),
		.color_ready_o     (palette_output_ready),
		.fbid_color_o,
		.fbid_depth_o,
		.triangle_id_o,
		.tile_x_o,
		.y_o,
		.red_o,
		.green_o,
		.blue_o,
		.depth1_o,
		.depth2_o,
		.mask_o,
		.out_valid_o,
		.out_ready_i
	);

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			$display("worker,%0t,input,param,%h,tile_x,%0d,y,%0d,coverage_mask,%h",
				$time, param_i, tile_x_i, y_i, coverage_mask_i);
		end

		if (out_valid_o && out_ready_i) begin
			$display("worker,%0t,output,fbid_color,%0d,fbid_depth,%0d,triangle_id,%h,tile_x,%0d,y,%0d,red,%h,green,%h,blue,%h,depth1,%h,depth2,%h,mask,%h",
				$time, fbid_color_o, fbid_depth_o, triangle_id_o, tile_x_o, y_o,
				red_o, green_o, blue_o, depth1_o, depth2_o, mask_o);
		end
	end
`endif

endmodule
