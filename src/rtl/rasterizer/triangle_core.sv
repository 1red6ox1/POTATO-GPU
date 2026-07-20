module triangle_core (
	input logic clk_i,
	input logic rst_ni,

	input  rasterizer_pkg::triangle_param_t param_i,
	input  logic            in_valid_i,
	output logic            in_ready_o,

	output logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x_o,
	output logic [rasterizer_pkg::TILE_Y_WIDTH-1:0] tile_y_o,
	output rasterizer_pkg::triangle_param_t         param_o,
	output logic                    out_valid_o,
	input  logic                    out_ready_i,
	
	output logic triangle_rasrized_o,
	output logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0] triangle_rasrized_id_o
);

	import rasterizer_pkg::*;

	logic unsigned [TILE_X_WIDTH-1:0] bbox_min_x_q;
	logic unsigned [TILE_X_WIDTH-1:0] bbox_max_x_q;
	logic unsigned [TILE_Y_WIDTH-1:0] bbox_max_y_q;
	logic unsigned [TILE_X_WIDTH-1:0] tile_x_q;
	logic unsigned [TILE_Y_WIDTH-1:0] tile_y_q;
	triangle_param_t param_q;

	assign tile_x_o = tile_x_q;
	assign tile_y_o = tile_y_q;
	assign param_o  = param_q;
	assign triangle_rasrized_id_o = param_q.triangle_id;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			in_ready_o          <= 1'b1;
			out_valid_o         <= 1'b0;
			triangle_rasrized_o <= 1'b0;
		end else begin
			triangle_rasrized_o <= 1'b0;

			if (in_valid_i && in_ready_o) begin
				in_ready_o  <= 1'b0;
				out_valid_o <= 1'b1;
			end else if (out_valid_o && out_ready_i && tile_x_q == bbox_max_x_q && tile_y_q == bbox_max_y_q) begin
				in_ready_o          <= 1'b1;
				out_valid_o         <= 1'b0;
				triangle_rasrized_o <= 1'b1;
			end
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			bbox_min_x_q <= '0;
			bbox_max_x_q <= '0;
			bbox_max_y_q <= '0;
			tile_x_q     <= '0;
			tile_y_q     <= '0;
			param_q      <= '0;
		end else if (in_valid_i && in_ready_o) begin
			bbox_min_x_q <= param_i.bbox_min_x;
			bbox_max_x_q <= param_i.bbox_max_x;
			bbox_max_y_q <= param_i.bbox_max_y;
			tile_x_q     <= param_i.bbox_min_x;
			tile_y_q     <= param_i.bbox_min_y;
			param_q      <= param_i;
		end else if (out_valid_o && out_ready_i) begin
			if (tile_x_q == bbox_max_x_q) begin
				tile_x_q <= bbox_min_x_q;
				tile_y_q <= tile_y_q + 1'b1;
			end else begin
				tile_x_q <= tile_x_q + 1'b1;
			end
		end
	end

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			$display("triangle_core,%0t,input,bbox_min_x,%0d,bbox_max_x,%0d,bbox_min_y,%0d,bbox_max_y,%0d",
				$time,
				$signed(param_i.bbox_min_x), $signed(param_i.bbox_max_x),
				$signed(param_i.bbox_min_y), $signed(param_i.bbox_max_y));
		end

		if (out_valid_o && out_ready_i) begin
			$display("triangle_core,%0t,output,tile_x,%0d,tile_y,%0d",
				$time, $signed(tile_x_o), $signed(tile_y_o));
		end
	end
`endif

endmodule
