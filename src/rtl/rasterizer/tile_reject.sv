module tile_reject (
	input rasterizer_pkg::triangle_param_t param_i,
	input logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x_i,
	input logic [rasterizer_pkg::TILE_Y_WIDTH-1:0] tile_y_i,

	output logic reject_o,
	output logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] e1_o,
	output logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] e2_o,
	output logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] e3_o
);

	import rasterizer_pkg::*;
	logic signed [COORD_WIDTH-1:0] tile_x;
	logic signed [COORD_WIDTH-1:0] tile_y;
	logic signed [EDGE_WIDTH-1:0] dx1_y, dx2_y, dx3_y;
	logic signed [EDGE_WIDTH-1:0] dy1_x, dy2_x, dy3_x;
	logic signed [EDGE_WIDTH-1:0] dx1_tile_height;
	logic signed [EDGE_WIDTH-1:0] dx2_tile_height;
	logic signed [EDGE_WIDTH-1:0] dx3_tile_height;
	logic signed [EDGE_WIDTH-1:0] dy1_tile_width;
	logic signed [EDGE_WIDTH-1:0] dy2_tile_width;
	logic signed [EDGE_WIDTH-1:0] dy3_tile_width;
	logic signed [EDGE_WIDTH-1:0] e1_max, e2_max, e3_max;

	always_comb begin
		tile_x = COORD_WIDTH'(tile_x_i) << $clog2(TILE_WIDTH);
		tile_y = COORD_WIDTH'(tile_y_i) << $clog2(TILE_HEIGHT);

		dx1_y = $signed(param_i.dx1) * $signed(tile_y);
		dx2_y = $signed(param_i.dx2) * $signed(tile_y);
		dx3_y = $signed(param_i.dx3) * $signed(tile_y);

		dy1_x = $signed(param_i.dy1) * $signed(tile_x);
		dy2_x = $signed(param_i.dy2) * $signed(tile_x);
		dy3_x = $signed(param_i.dy3) * $signed(tile_x);

		dx1_tile_height = (EDGE_WIDTH'($signed(param_i.dx1)) << $clog2(TILE_HEIGHT)) - EDGE_WIDTH'($signed(param_i.dx1));
		dx2_tile_height = (EDGE_WIDTH'($signed(param_i.dx2)) << $clog2(TILE_HEIGHT)) - EDGE_WIDTH'($signed(param_i.dx2));
		dx3_tile_height = (EDGE_WIDTH'($signed(param_i.dx3)) << $clog2(TILE_HEIGHT)) - EDGE_WIDTH'($signed(param_i.dx3));

		dy1_tile_width = (EDGE_WIDTH'($signed(param_i.dy1)) << $clog2(TILE_WIDTH)) - EDGE_WIDTH'($signed(param_i.dy1));
		dy2_tile_width = (EDGE_WIDTH'($signed(param_i.dy2)) << $clog2(TILE_WIDTH)) - EDGE_WIDTH'($signed(param_i.dy2));
		dy3_tile_width = (EDGE_WIDTH'($signed(param_i.dy3)) << $clog2(TILE_WIDTH)) - EDGE_WIDTH'($signed(param_i.dy3));

		e1_o = $signed(param_i.e1) + dx1_y - dy1_x;
		e2_o = $signed(param_i.e2) + dx2_y - dy2_x;
		e3_o = $signed(param_i.e3) + dx3_y - dy3_x;

		e1_max = e1_o;
		e2_max = e2_o;
		e3_max = e3_o;

		if (param_i.dx1 > 0) begin
			e1_max = e1_max + dx1_tile_height;
		end
		if (param_i.dx2 > 0) begin
			e2_max = e2_max + dx2_tile_height;
		end
		if (param_i.dx3 > 0) begin
			e3_max = e3_max + dx3_tile_height;
		end

		if (param_i.dy1 < 0) begin
			e1_max = e1_max - dy1_tile_width;
		end
		if (param_i.dy2 < 0) begin
			e2_max = e2_max - dy2_tile_width;
		end
		if (param_i.dy3 < 0) begin
			e3_max = e3_max - dy3_tile_width;
		end

		reject_o = !(e1_max >= 0 && e2_max >= 0 && e3_max >= 0);
	end

endmodule
