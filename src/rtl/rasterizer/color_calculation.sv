module color_calculation #(
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
	input  logic uq_vq_valid_i,
	output logic uq_vq_ready_o,

	output logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0] triangle_id_o,
	output logic [255:0] red_o,
	output logic [255:0] green_o,
	output logic [255:0] blue_o,
	output logic out_valid_o,
	input  logic out_ready_i
);

	import rasterizer_pkg::*;

	localparam logic signed [63:0] UVQ_ONE = 64'sd1 << UVQ_FRAC_WIDTH;

	typedef struct packed {
		logic [TRIANGLE_ID_WIDTH-1:0] triangle_id;
		logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] u;
		logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] v;
	} uv_t;

	uv_t uv_i;
	uv_t uv_o;
	logic uv_fifo_in_ready;
	logic uv_valid;

	assign one_q_ready_o = uq_vq_valid_i && uv_fifo_in_ready;
	assign uq_vq_ready_o = one_q_valid_i && uv_fifo_in_ready;
	assign triangle_id_o = uv_o.triangle_id;
	assign out_valid_o = uv_valid;

	always_comb begin
		uv_i = '0;
		uv_i.triangle_id = triangle_id_i;
		red_o   = '0;
		green_o = '0;
		blue_o  = '0;

		for (int pixel = 0; pixel < TILE_WIDTH; pixel++) begin
			logic signed [2 * UVQ_WIDTH-1:0] u_product;
			logic signed [2 * UVQ_WIDTH-1:0] v_product;
			logic signed [UVQ_WIDTH-1:0] u;
			logic signed [UVQ_WIDTH-1:0] v;
			logic signed [63:0] u_fixed;
			logic signed [63:0] v_fixed;
			logic signed [63:0] r_fixed;
			logic signed [63:0] red_scaled;
			logic signed [63:0] green_scaled;
			logic signed [63:0] blue_scaled;

			u_product = $signed(uq_i[pixel]) * $signed(one_q_i[pixel]);
			v_product = $signed(vq_i[pixel]) * $signed(one_q_i[pixel]);
			uv_i.u[pixel] = UVQ_WIDTH'(u_product >>> UVQ_FRAC_WIDTH);
			uv_i.v[pixel] = UVQ_WIDTH'(v_product >>> UVQ_FRAC_WIDTH);

			u = uv_o.u[pixel];
			v = uv_o.v[pixel];

			u_fixed = 64'($signed(u));
			v_fixed = 64'($signed(v));
			r_fixed = UVQ_ONE - u_fixed - v_fixed;

			red_scaled   = (r_fixed << 8) - r_fixed;
			green_scaled = (v_fixed << 8) - v_fixed;
			blue_scaled  = (u_fixed << 8) - u_fixed;

			if (r_fixed >= UVQ_ONE) begin
				red_o[8 * pixel +: 8] = 8'hff;
			end else if (r_fixed > 0) begin
				red_o[8 * pixel +: 8] = red_scaled[UVQ_FRAC_WIDTH +: 8];
			end

			if (v_fixed >= UVQ_ONE) begin
				green_o[8 * pixel +: 8] = 8'hff;
			end else if (v_fixed > 0) begin
				green_o[8 * pixel +: 8] = green_scaled[UVQ_FRAC_WIDTH +: 8];
			end

			if (u_fixed >= UVQ_ONE) begin
				blue_o[8 * pixel +: 8] = 8'hff;
			end else if (u_fixed > 0) begin
				blue_o[8 * pixel +: 8] = blue_scaled[UVQ_FRAC_WIDTH +: 8];
			end
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
		.out_ready_i (out_ready_i),
		.depth_o     ()
	);

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (one_q_valid_i && one_q_ready_o) begin
			$display("color_calculation,%0t,input,one_q,%h,uq,%h,vq,%h,triangle_id,%h",
				$time, one_q_i, uq_i, vq_i, triangle_id_i);
		end

		if (out_valid_o && out_ready_i) begin
			$display("color_calculation,%0t,output,red,%h,green,%h,blue,%h,triangle_id,%h",
				$time, red_o, green_o, blue_o, triangle_id_o);
		end
	end
`endif

endmodule
