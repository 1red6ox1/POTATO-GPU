module line_fifo #(
	parameter bit          Pass  = 1'b0,
	parameter int unsigned Depth = 10
) (
	input logic clk_i,
	input logic rst_ni,

	input  logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x_i,
	input  logic [rasterizer_pkg::TILE_Y_WIDTH-1:0] tile_y_i,
	input  rasterizer_pkg::triangle_param_t param_i,
	input  logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] e1_i,
	input  logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] e2_i,
	input  logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] e3_i,
	input  logic in_valid_i,
	output logic in_ready_o,

	output logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x_o,
	output logic [rasterizer_pkg::FRAME_Y_WIDTH-1:0] y_o,
	output rasterizer_pkg::triangle_param_t param_o,
	output logic [rasterizer_pkg::TILE_WIDTH-1:0] mask_o,
	output logic out_valid_o,
	input  logic out_ready_i
);

	import rasterizer_pkg::*;

	localparam int unsigned LINE_FIFO_DEPTH_WIDTH = $clog2(Depth + 1);

	logic writing_q;
	logic [$clog2(TILE_HEIGHT)-1:0] line_q;
	logic [TILE_X_WIDTH-1:0] tile_x_q;
	logic [FRAME_Y_WIDTH-1:0] y_q;
	logic signed [EDGE_WIDTH-1:0] e1_q;
	logic signed [EDGE_WIDTH-1:0] e2_q;
	logic signed [EDGE_WIDTH-1:0] e3_q;
	triangle_param_t param_q;
	logic [LINE_FIFO_DEPTH_WIDTH-1:0] line_depth;
	logic signed [EDGE_WIDTH-1:0] line_e1;
	logic signed [EDGE_WIDTH-1:0] line_e2;
	logic signed [EDGE_WIDTH-1:0] line_e3;
	logic [TILE_WIDTH-1:0] line_mask;
	logic [TILE_X_WIDTH-1:0] line_tile_x;
	logic [FRAME_Y_WIDTH-1:0] line_y;
	triangle_param_t line_param;

	typedef struct packed {
		logic [TILE_X_WIDTH-1:0] tile_x;
		logic [FRAME_Y_WIDTH-1:0] y;
		triangle_param_t param;
		logic [TILE_WIDTH-1:0] mask;
	} line_t;

	line_t line_i;
	line_t line_o;

	assign in_ready_o = !writing_q && line_depth <= LINE_FIFO_DEPTH_WIDTH'(Depth - TILE_HEIGHT);

	always_comb begin
		line_tile_x = tile_x_q;
		line_y      = y_q;
		line_e1     = e1_q;
		line_e2     = e2_q;
		line_e3     = e3_q;
		line_param  = param_q;

		if (in_valid_i && in_ready_o) begin
			line_tile_x = tile_x_i;
			line_y      = FRAME_Y_WIDTH'(tile_y_i << $clog2(TILE_HEIGHT));
			line_e1     = e1_i;
			line_e2     = e2_i;
			line_e3     = e3_i;
			line_param  = param_i;
		end
	end

	always_comb begin
		line_mask = '0;

		for (int x = 0; x < TILE_WIDTH; x++) begin
			logic signed [EDGE_WIDTH-1:0] e1_pixel;
			logic signed [EDGE_WIDTH-1:0] e2_pixel;
			logic signed [EDGE_WIDTH-1:0] e3_pixel;

			e1_pixel = line_e1 - EDGE_WIDTH'($signed(line_param.dy1)) * x;
			e2_pixel = line_e2 - EDGE_WIDTH'($signed(line_param.dy2)) * x;
			e3_pixel = line_e3 - EDGE_WIDTH'($signed(line_param.dy3)) * x;

			line_mask[x] = e1_pixel >= 0 && e2_pixel >= 0 && e3_pixel >= 0;
		end

		line_i = '{
			tile_x: line_tile_x,
			y:      line_y,
			param:  line_param,
			mask:   line_mask
		};
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			writing_q <= 1'b0;
			line_q    <= '0;
			tile_x_q  <= '0;
			y_q       <= '0;
			e1_q      <= '0;
			e2_q      <= '0;
			e3_q      <= '0;
			param_q   <= '0;
		end else if (in_valid_i && in_ready_o) begin
			writing_q <= 1'b1;
			line_q    <= 1;
			tile_x_q  <= tile_x_i;
			y_q       <= FRAME_Y_WIDTH'(tile_y_i << $clog2(TILE_HEIGHT)) + 1'b1;
			e1_q      <= e1_i + EDGE_WIDTH'($signed(param_i.dx1));
			e2_q      <= e2_i + EDGE_WIDTH'($signed(param_i.dx2));
			e3_q      <= e3_i + EDGE_WIDTH'($signed(param_i.dx3));
			param_q   <= param_i;
		end else if (writing_q) begin
			if (line_q == $clog2(TILE_HEIGHT)'(TILE_HEIGHT - 1)) begin
				writing_q <= 1'b0;
			end else begin
				line_q <= line_q + 1'b1;
				y_q    <= y_q + 1'b1;
				e1_q   <= e1_q + EDGE_WIDTH'($signed(param_q.dx1));
				e2_q   <= e2_q + EDGE_WIDTH'($signed(param_q.dx2));
				e3_q   <= e3_q + EDGE_WIDTH'($signed(param_q.dx3));
			end
		end
	end

	assign tile_x_o = line_o.tile_x;
	assign y_o      = line_o.y;
	assign param_o  = line_o.param;
	assign mask_o   = line_o.mask;

	my_fifo #(
		.Width ($bits(line_t)),
		.Pass  (Pass),
		.Depth (Depth)
	) line_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i     (1'b0),
		.in_data_i   (line_i),
		.in_valid_i  ((writing_q || (in_valid_i && in_ready_o)) && |line_mask),
		.in_ready_o  (),
		.out_data_o  (line_o),
		.out_valid_o,
		.out_ready_i,
		.depth_o     (line_depth)
	);

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			$display("line_fifo,%0t,input,tile_x,%0d,tile_y,%0d,param,%h,e1,%h,e2,%h,e3,%h",
				$time, tile_x_i, tile_y_i, param_i, e1_i, e2_i, e3_i);
		end

		if (out_valid_o && out_ready_i) begin
			$display("line_fifo,%0t,output,tile_x,%0d,y,%0d,param,%h,mask,%h",
				$time, tile_x_o, y_o, param_o, mask_o);
		end
	end
`endif

endmodule
