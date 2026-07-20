module uq_vq_calculation #(
	parameter int unsigned Depth = 4
) (
	input logic clk_i,
	input logic rst_ni,

	input  rasterizer_pkg::triangle_param_t param_i,
	input  logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x_i,
	input  logic [rasterizer_pkg::FRAME_Y_WIDTH-1:0] y_i,
	input  logic in_valid_i,
	output logic in_ready_o,

	output logic [rasterizer_pkg::TILE_WIDTH-1:0][rasterizer_pkg::UVQ_WIDTH-1:0] uq_o,
	output logic [rasterizer_pkg::TILE_WIDTH-1:0][rasterizer_pkg::UVQ_WIDTH-1:0] vq_o,
	output logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0] triangle_id_o,
	output logic [rasterizer_pkg::TEXTURE_ID_WIDTH-1:0] texture_id_o,
	output logic out_valid_o,
	input  logic out_ready_i
);

	import rasterizer_pkg::*;

	logic signed [COORD_WIDTH-1:0] x_i;
	logic signed [63:0] uq_row;
	logic signed [63:0] vq_row;
	logic fifo_in_ready;

	typedef struct packed {
		logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] uq;
		logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] vq;
		logic [TRIANGLE_ID_WIDTH-1:0] triangle_id;
		logic [TEXTURE_ID_WIDTH-1:0] texture_id;
	} uq_vq_t;

	uq_vq_t uq_vq_i;
	uq_vq_t uq_vq_o;

	assign x_i = COORD_WIDTH'(tile_x_i) << $clog2(TILE_WIDTH);
	assign in_ready_o = fifo_in_ready;
	assign uq_o = uq_vq_o.uq;
	assign vq_o = uq_vq_o.vq;
	assign triangle_id_o = uq_vq_o.triangle_id;
	assign texture_id_o = uq_vq_o.texture_id;

	always_comb begin
		uq_row = 64'($signed(param_i.uq)) + $signed(param_i.duq_dx) * x_i + $signed(param_i.duq_dy) * $signed(COORD_WIDTH'(y_i));
		vq_row = 64'($signed(param_i.vq)) + $signed(param_i.dvq_dx) * x_i + $signed(param_i.dvq_dy) * $signed(COORD_WIDTH'(y_i));

		for (int x = 0; x < TILE_WIDTH; x++) begin
			uq_vq_i.uq[x] = UVQ_WIDTH'($signed(uq_row) + $signed(param_i.duq_dx) * $signed(COORD_WIDTH'(x)));
			uq_vq_i.vq[x] = UVQ_WIDTH'($signed(vq_row) + $signed(param_i.dvq_dx) * $signed(COORD_WIDTH'(x)));
		end

		uq_vq_i.triangle_id = param_i.triangle_id;
		uq_vq_i.texture_id = param_i.texture_id;
	end

	my_fifo #(
		.Width   ($bits(uq_vq_t)),
		.Pass    (1'b0),
		.Depth   (Depth),
		.UseBram (1'b1)
	) uq_vq_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i     (1'b0),
		.in_data_i   (uq_vq_i),
		.in_valid_i  (in_valid_i && in_ready_o),
		.in_ready_o  (fifo_in_ready),
		.out_data_o  (uq_vq_o),
		.out_valid_o,
		.out_ready_i,
		.depth_o     ()
	);

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			$display("uq_vq_calculation,%0t,input,param,%h,tile_x,%0d,y,%0d",
				$time, param_i, tile_x_i, y_i);
		end

		if (out_valid_o && out_ready_i) begin
			$display("uq_vq_calculation,%0t,output,triangle_id,%h,uq,%h,vq,%h",
				$time, triangle_id_o, uq_o, vq_o);
		end
	end
`endif

endmodule
