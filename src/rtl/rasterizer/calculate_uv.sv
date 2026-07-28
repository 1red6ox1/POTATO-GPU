module calculate_uv #(
	parameter int unsigned Depth = 4
) (
	input logic clk_i,
	input logic rst_ni,

	input  logic [rasterizer_pkg::TILE_WIDTH-1:0][rasterizer_pkg::UVQ_WIDTH-1:0] one_q_i,
	input  logic one_q_valid_i,
	output logic one_q_ready_o,

	input  logic [rasterizer_pkg::TILE_WIDTH-1:0][rasterizer_pkg::UVQ_WIDTH-1:0] uq_i,
	input  logic [rasterizer_pkg::TILE_WIDTH-1:0][rasterizer_pkg::UVQ_WIDTH-1:0] vq_i,
	input  logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0] triangle_id_i,
	input  logic [rasterizer_pkg::TEXTURE_ID_WIDTH-1:0] texture_id_i,
	input  logic uq_vq_valid_i,
	output logic uq_vq_ready_o,

	output logic [rasterizer_pkg::TILE_WIDTH-1:0][rasterizer_pkg::UVQ_WIDTH-1:0] u_o,
	output logic [rasterizer_pkg::TILE_WIDTH-1:0][rasterizer_pkg::UVQ_WIDTH-1:0] v_o,
	output logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0] triangle_id_o,
	output logic [rasterizer_pkg::TEXTURE_ID_WIDTH-1:0] texture_id_o,
	output logic out_valid_o,
	input  logic out_ready_i
);

	import rasterizer_pkg::*;

	typedef struct packed {
		logic [TRIANGLE_ID_WIDTH-1:0] triangle_id;
		logic [TEXTURE_ID_WIDTH-1:0] texture_id;
		logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] u;
		logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] v;
	} uv_t;

	uv_t uv_i;
	uv_t uv_o;
	logic uv_fifo_in_ready;
	logic uv_valid;

	assign one_q_ready_o = uq_vq_valid_i && uv_fifo_in_ready;
	assign uq_vq_ready_o = one_q_valid_i && uv_fifo_in_ready;
	assign u_o = uv_o.u;
	assign v_o = uv_o.v;
	assign triangle_id_o = uv_o.triangle_id;
	assign texture_id_o = uv_o.texture_id;
	assign out_valid_o = uv_valid;

	always_comb begin
		uv_i = '0;
		uv_i.triangle_id = triangle_id_i;
		uv_i.texture_id = texture_id_i;

		for (int pixel = 0; pixel < TILE_WIDTH; pixel++) begin
			logic signed [2 * UVQ_WIDTH-1:0] u_product;
			logic signed [2 * UVQ_WIDTH-1:0] v_product;

			u_product = $signed(uq_i[pixel]) * $signed(one_q_i[pixel]);
			v_product = $signed(vq_i[pixel]) * $signed(one_q_i[pixel]);
			uv_i.u[pixel] = UVQ_WIDTH'(u_product >>> UVQ_FRAC_WIDTH);
			uv_i.v[pixel] = UVQ_WIDTH'(v_product >>> UVQ_FRAC_WIDTH);
		end
	end

	my_fifo #(
		.Width ($bits(uv_t)),
		.Pass  (1'b0),
		.Depth (Depth)
	) uv_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i     (1'b0),
		.in_data_i   (uv_i),
		.in_valid_i  (one_q_valid_i && uq_vq_valid_i),
		.in_ready_o  (uv_fifo_in_ready),
		.out_data_o  (uv_o),
		.out_valid_o (uv_valid),
		.out_ready_i,
		.depth_o     ()
	);

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (one_q_valid_i && one_q_ready_o) begin
			$display("calculate_uv,%0t,input,one_q,%h,uq,%h,vq,%h,triangle_id,%h,texture_id,%h",
				$time, one_q_i, uq_i, vq_i, triangle_id_i, texture_id_i);
		end

		if (out_valid_o && out_ready_i) begin
			$display("calculate_uv,%0t,output,u,%h,v,%h,triangle_id,%h,texture_id,%h",
				$time, u_o, v_o, triangle_id_o, texture_id_o);
		end
	end
`endif

endmodule
