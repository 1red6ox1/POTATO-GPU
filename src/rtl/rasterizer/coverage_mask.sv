module coverage_mask
import rasterizer_pkg::*;
#(
	parameter int unsigned FIFO_DEPTH = 8
) (
	input logic clk_i,
	input logic rst_ni,

	input rasterization_param_t                        param_i,
	input logic [$clog2(FRAME_WIDTH / TILE_WIDTH)-1:0] tile_x_i,
	input logic [$clog2(FRAME_HEIGHT)-1:0]             y_i,
	input logic                                        in_valid_i,
	output logic                                       in_ready_o,

	output logic [TILE_WIDTH-1:0] mask_o,
	output logic                  out_valid_o,
	input logic                   out_ready_i
);

	logic signed [COORD_WIDTH-1:0] pixel_x;
	logic signed [COORD_WIDTH-1:0] pixel_y;
	logic signed [EDGE_WIDTH-1:0] e1_row;
	logic signed [EDGE_WIDTH-1:0] e2_row;
	logic signed [EDGE_WIDTH-1:0] e3_row;
	logic signed [EDGE_WIDTH-1:0] dx1_y;
	logic signed [EDGE_WIDTH-1:0] dx2_y;
	logic signed [EDGE_WIDTH-1:0] dx3_y;
	logic signed [EDGE_WIDTH-1:0] dy1_x;
	logic signed [EDGE_WIDTH-1:0] dy2_x;
	logic signed [EDGE_WIDTH-1:0] dy3_x;
	logic signed [EDGE_WIDTH-1:0] mask_dy1;
	logic signed [EDGE_WIDTH-1:0] mask_dy2;
	logic signed [EDGE_WIDTH-1:0] mask_dy3;
	logic [TILE_WIDTH-1:0]        mask_i;
	logic                          fifo_in_ready;

	assign pixel_x = $signed(COORD_WIDTH'(tile_x_i) << $clog2(TILE_WIDTH));
	assign pixel_y = $signed(COORD_WIDTH'(y_i));
	assign in_ready_o = fifo_in_ready;

	// e1/e2/e3 are the edge values at pixel (0, 0).
	always_comb begin
		dx1_y = $signed(param_i.dx1) * $signed(pixel_y);
		dx2_y = $signed(param_i.dx2) * $signed(pixel_y);
		dx3_y = $signed(param_i.dx3) * $signed(pixel_y);
		dy1_x = $signed(param_i.dy1) * $signed(pixel_x);
		dy2_x = $signed(param_i.dy2) * $signed(pixel_x);
		dy3_x = $signed(param_i.dy3) * $signed(pixel_x);
		mask_dy1 = {{(EDGE_WIDTH-COORD_WIDTH){param_i.dy1[COORD_WIDTH-1]}},
		            param_i.dy1};
		mask_dy2 = {{(EDGE_WIDTH-COORD_WIDTH){param_i.dy2[COORD_WIDTH-1]}},
		            param_i.dy2};
		mask_dy3 = {{(EDGE_WIDTH-COORD_WIDTH){param_i.dy3[COORD_WIDTH-1]}},
		            param_i.dy3};

		e1_row = $signed(param_i.e1) + dx1_y - dy1_x;
		e2_row = $signed(param_i.e2) + dx2_y - dy2_x;
		e3_row = $signed(param_i.e3) + dx3_y - dy3_x;

		mask_i = '0;
		for (int i = 0; i < TILE_WIDTH; i++) begin
			logic signed [EDGE_WIDTH-1:0] e1_pixel;
			logic signed [EDGE_WIDTH-1:0] e2_pixel;
			logic signed [EDGE_WIDTH-1:0] e3_pixel;

			e1_pixel = e1_row;
			e2_pixel = e2_row;
			e3_pixel = e3_row;

			if (i[0]) begin
				e1_pixel = e1_pixel - mask_dy1;
				e2_pixel = e2_pixel - mask_dy2;
				e3_pixel = e3_pixel - mask_dy3;
			end
			if (i[1]) begin
				e1_pixel = e1_pixel - (mask_dy1 <<< 1);
				e2_pixel = e2_pixel - (mask_dy2 <<< 1);
				e3_pixel = e3_pixel - (mask_dy3 <<< 1);
			end
			if (i[2]) begin
				e1_pixel = e1_pixel - (mask_dy1 <<< 2);
				e2_pixel = e2_pixel - (mask_dy2 <<< 2);
				e3_pixel = e3_pixel - (mask_dy3 <<< 2);
			end
			if (i[3]) begin
				e1_pixel = e1_pixel - (mask_dy1 <<< 3);
				e2_pixel = e2_pixel - (mask_dy2 <<< 3);
				e3_pixel = e3_pixel - (mask_dy3 <<< 3);
			end
			if (i[4]) begin
				e1_pixel = e1_pixel - (mask_dy1 <<< 4);
				e2_pixel = e2_pixel - (mask_dy2 <<< 4);
				e3_pixel = e3_pixel - (mask_dy3 <<< 4);
			end

			mask_i[i] = e1_pixel >= 0 && e2_pixel >= 0 && e3_pixel >= 0;
		end
	end

	my_fifo #(
		.Width (TILE_WIDTH),
		.Pass  (1'b0),
		.Depth (FIFO_DEPTH)
	) mask_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i      (1'b0),
		.in_data_i    (mask_i),
		.in_valid_i   (in_valid_i),
		.in_ready_o   (fifo_in_ready),
		.out_data_o   (mask_o),
		.out_valid_o,
		.out_ready_i,
		.depth_o      ()
	);

endmodule
