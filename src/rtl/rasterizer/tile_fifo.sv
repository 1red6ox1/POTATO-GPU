module tile_fifo #(
	parameter bit          Pass  = 1'b0,
	parameter int unsigned Depth = 2
) (
	input logic clk_i,
	input logic rst_ni,

	input  logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x_i,
	input  logic [rasterizer_pkg::TILE_Y_WIDTH-1:0] tile_y_i,
	input  rasterizer_pkg::triangle_param_t param_i,
	input  logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] e1_i,
	input  logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] e2_i,
	input  logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] e3_i,
	input  logic reject_i,
	input  logic in_valid_i,
	output logic in_ready_o,

	output logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x_o,
	output logic [rasterizer_pkg::TILE_Y_WIDTH-1:0] tile_y_o,
	output rasterizer_pkg::triangle_param_t param_o,
	output logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] e1_o,
	output logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] e2_o,
	output logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] e3_o,
	output logic reject_o,
	output logic out_valid_o,
	input  logic out_ready_i
);

	import rasterizer_pkg::*;

	typedef struct packed {
		logic [TILE_X_WIDTH-1:0] tile_x;
		logic [TILE_Y_WIDTH-1:0] tile_y;
		triangle_param_t param;
		logic signed [EDGE_WIDTH-1:0] e1;
		logic signed [EDGE_WIDTH-1:0] e2;
		logic signed [EDGE_WIDTH-1:0] e3;
		logic reject;
	} tile_t;

	tile_t tile_i;
	tile_t tile_o;

	always_comb begin
		tile_i.tile_x = tile_x_i;
		tile_i.tile_y = tile_y_i;
		tile_i.param  = param_i;
		tile_i.e1     = e1_i;
		tile_i.e2     = e2_i;
		tile_i.e3     = e3_i;
		tile_i.reject = reject_i;
	end

	assign tile_x_o = tile_o.tile_x;
	assign tile_y_o = tile_o.tile_y;
	assign param_o  = tile_o.param;
	assign e1_o     = tile_o.e1;
	assign e2_o     = tile_o.e2;
	assign e3_o     = tile_o.e3;
	assign reject_o = tile_o.reject;

	my_fifo #(
		.Width ($bits(tile_t)),
		.Pass  (Pass),
		.Depth (Depth)
	) tile_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i     (1'b0),
		.in_data_i   (tile_i),
		.in_valid_i,
		.in_ready_o,
		.out_data_o  (tile_o),
		.out_valid_o,
		.out_ready_i,
		.depth_o     ()
	);

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			$display("tile_fifo,%0t,input,tile_x,%0d,tile_y,%0d,param,%h,e1,%h,e2,%h,e3,%h,reject,%0d",
				$time, tile_x_i, tile_y_i, param_i, e1_i, e2_i, e3_i, reject_i);
		end

		if (out_valid_o && out_ready_i) begin
			$display("tile_fifo,%0t,output,tile_x,%0d,tile_y,%0d,param,%h,e1,%h,e2,%h,e3,%h,reject,%0d",
				$time, tile_x_o, tile_y_o, param_o, e1_o, e2_o, e3_o, reject_o);
		end
	end
`endif

endmodule
