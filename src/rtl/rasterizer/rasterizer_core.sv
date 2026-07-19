module rasterizer_core
import rasterizer_pkg::*;
(
	input logic clk_i,
	input logic rst_ni,

	input rasterization_param_t param_i,
	input logic                 in_valid_i,
	output logic                 in_ready_o,

	output rasterization_param_t                        param_o,
	output logic [$clog2(FRAME_WIDTH / TILE_WIDTH)-1:0] tile_x_o,
	output logic [$clog2(FRAME_HEIGHT)-1:0]             y_o,
	output logic                                        out_valid_o,
	input logic                                         out_ready_i
);

	localparam logic [$clog2(TILE_HEIGHT)-1:0] LAST_ROW =
		$clog2(TILE_HEIGHT)'(TILE_HEIGHT - 1);

	rasterization_param_t param_q;
	logic [$clog2(FRAME_WIDTH / TILE_WIDTH)-1:0] tile_x_q;
	logic [$clog2(FRAME_HEIGHT / TILE_HEIGHT)-1:0] tile_y_q;
	logic [$clog2(TILE_HEIGHT)-1:0] row_in_tile_q;
	logic scan_active_q;

	logic signed [COORD_WIDTH-1:0] tile_x;
	logic signed [COORD_WIDTH-1:0] tile_y;
	logic signed [EDGE_WIDTH-1:0] e1_tile;
	logic signed [EDGE_WIDTH-1:0] e2_tile;
	logic signed [EDGE_WIDTH-1:0] e3_tile;
	logic signed [EDGE_WIDTH-1:0] e1_max;
	logic signed [EDGE_WIDTH-1:0] e2_max;
	logic signed [EDGE_WIDTH-1:0] e3_max;
	logic signed [EDGE_WIDTH-1:0] dx1_y;
	logic signed [EDGE_WIDTH-1:0] dx2_y;
	logic signed [EDGE_WIDTH-1:0] dx3_y;
	logic signed [EDGE_WIDTH-1:0] dy1_x;
	logic signed [EDGE_WIDTH-1:0] dy2_x;
	logic signed [EDGE_WIDTH-1:0] dy3_x;
	logic signed [EDGE_WIDTH-1:0] dx1_tile_height;
	logic signed [EDGE_WIDTH-1:0] dx2_tile_height;
	logic signed [EDGE_WIDTH-1:0] dx3_tile_height;
	logic signed [EDGE_WIDTH-1:0] dy1_tile_width;
	logic signed [EDGE_WIDTH-1:0] dy2_tile_width;
	logic signed [EDGE_WIDTH-1:0] dy3_tile_width;
	logic tile_visible;
	logic row_fire;

	assign param_o = param_q;
	assign tile_x_o = tile_x_q;
	assign y_o = ($clog2(FRAME_HEIGHT)'(tile_y_q) << $clog2(TILE_HEIGHT))
	           + $clog2(FRAME_HEIGHT)'(row_in_tile_q);
	assign in_ready_o = !scan_active_q;
	assign out_valid_o = scan_active_q && tile_visible;
	assign row_fire = out_valid_o && out_ready_i;

	always_comb begin
		tile_x = COORD_WIDTH'(tile_x_q) <<< $clog2(TILE_WIDTH);
		tile_y = COORD_WIDTH'(tile_y_q) <<< $clog2(TILE_HEIGHT);

		dx1_y = $signed(param_q.dx1) * $signed(tile_y);
		dx2_y = $signed(param_q.dx2) * $signed(tile_y);
		dx3_y = $signed(param_q.dx3) * $signed(tile_y);
		dy1_x = $signed(param_q.dy1) * $signed(tile_x);
		dy2_x = $signed(param_q.dy2) * $signed(tile_x);
		dy3_x = $signed(param_q.dy3) * $signed(tile_x);
		dx1_tile_height = ($signed(param_q.dx1) <<< $clog2(TILE_HEIGHT))
                - $signed(param_q.dx1);
		dx2_tile_height = ($signed(param_q.dx2) <<< $clog2(TILE_HEIGHT))
                - $signed(param_q.dx2);
		dx3_tile_height = ($signed(param_q.dx3) <<< $clog2(TILE_HEIGHT))
                - $signed(param_q.dx3);

		dy1_tile_width = ($signed(param_q.dy1) <<< $clog2(TILE_WIDTH))
               - $signed(param_q.dy1);
		dy2_tile_width = ($signed(param_q.dy2) <<< $clog2(TILE_WIDTH))
               - $signed(param_q.dy2);
		dy3_tile_width = ($signed(param_q.dy3) <<< $clog2(TILE_WIDTH))
               - $signed(param_q.dy3);

		e1_tile = $signed(param_q.e1) + dx1_y - dy1_x;
		e2_tile = $signed(param_q.e2) + dx2_y - dy2_x;
		e3_tile = $signed(param_q.e3) + dx3_y - dy3_x;

		e1_max = e1_tile;
		e2_max = e2_tile;
		e3_max = e3_tile;

		if (param_q.dx1 > 0) begin
			e1_max = e1_max + dx1_tile_height;
		end
		if (param_q.dx2 > 0) begin
			e2_max = e2_max + dx2_tile_height;
		end
		if (param_q.dx3 > 0) begin
			e3_max = e3_max + dx3_tile_height;
		end

		if (param_q.dy1 < 0) begin
			e1_max = e1_max - dy1_tile_width;
		end
		if (param_q.dy2 < 0) begin
			e2_max = e2_max - dy2_tile_width;
		end
		if (param_q.dy3 < 0) begin
			e3_max = e3_max - dy3_tile_width;
		end

		tile_visible = e1_max >= 0 && e2_max >= 0 && e3_max >= 0;
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			param_q       <= '0;
			tile_x_q      <= '0;
			tile_y_q      <= '0;
			row_in_tile_q <= '0;
			scan_active_q <= 1'b0;
		end else if (in_valid_i && in_ready_o) begin
			param_q       <= param_i;
			tile_x_q      <= param_i.bbox_min_x;
			tile_y_q      <= param_i.bbox_min_y;
			row_in_tile_q <= '0;
			scan_active_q <= !(param_i.bbox_min_x > param_i.bbox_max_x
			                  || param_i.bbox_min_y > param_i.bbox_max_y);
		end else if (scan_active_q) begin
			if (!tile_visible || (row_fire && row_in_tile_q == LAST_ROW)) begin
				row_in_tile_q <= '0;
				if (tile_x_q == param_q.bbox_max_x) begin
					tile_x_q <= param_q.bbox_min_x;
					if (tile_y_q == param_q.bbox_max_y) begin
						tile_y_q <= param_q.bbox_min_y;
						scan_active_q <= 1'b0;
					end else begin
						tile_y_q <= tile_y_q + 1'b1;
					end
				end else begin
					tile_x_q <= tile_x_q + 1'b1;
				end
			end else if (row_fire) begin
				row_in_tile_q <= row_in_tile_q + 1'b1;
			end
		end
	end

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			$display("rasterizer_core,%0t,bounds,%0d,%0d,%0d,%0d",
				$time,
				param_i.bbox_min_x, param_i.bbox_min_y,
				param_i.bbox_max_x, param_i.bbox_max_y);
		end

		if (scan_active_q && !tile_visible) begin
			$display("rasterizer_core,%0t,reject,tile,%0d,%0d",
				$time, tile_x_q, tile_y_q);
		end

		if (row_fire) begin
			$display("rasterizer_core,%0t,row,%0d,%0d,pixel,%0d,%0d",
				$time, tile_x_q, y_o,
				COORD_WIDTH'(tile_x_q) << $clog2(TILE_WIDTH), y_o);
		end
	end
`endif

endmodule
