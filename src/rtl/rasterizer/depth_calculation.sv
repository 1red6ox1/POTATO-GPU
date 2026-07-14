module depth_calculation
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

	output logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] depth_o,
	output logic                                   out_valid_o,
	input logic                                    out_ready_i
);

	logic signed [COORD_WIDTH-1:0] x_i;
	logic signed [DEPTH_INTERP_WIDTH-1:0] z_row;
	logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] depth_i;
	logic fifo_in_ready;

	assign x_i = $signed(COORD_WIDTH'(tile_x_i) << $clog2(TILE_WIDTH));
	assign in_ready_o = fifo_in_ready;

	always_comb begin
		z_row = DEPTH_INTERP_WIDTH'(param_i.z)
		      + DEPTH_INTERP_WIDTH'($signed(param_i.dz_dx) * x_i)
		      + DEPTH_INTERP_WIDTH'($signed(param_i.dz_dy) * $signed(COORD_WIDTH'(y_i)));

		for (int i = 0; i < TILE_WIDTH; i++) begin
			logic signed [DEPTH_INTERP_WIDTH-1:0] z_pixel;

			z_pixel = z_row;
			if (i[0]) begin
				z_pixel = z_pixel + $signed(param_i.dz_dx);
			end
			if (i[1]) begin
				z_pixel = z_pixel + ($signed(param_i.dz_dx) <<< 1);
			end
			if (i[2]) begin
				z_pixel = z_pixel + ($signed(param_i.dz_dx) <<< 2);
			end
			if (i[3]) begin
				z_pixel = z_pixel + ($signed(param_i.dz_dx) <<< 3);
			end
			if (i[4]) begin
				z_pixel = z_pixel + ($signed(param_i.dz_dx) <<< 4);
			end

			depth_i[i] = z_pixel[DEPTH_FRAC_WIDTH+:DEPTH_WIDTH];
		end
	end

	my_fifo #(
		.Width (TILE_WIDTH * DEPTH_WIDTH),
		.Pass  (1'b0),
		.Depth (FIFO_DEPTH)
	) depth_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i      (1'b0),
		.in_data_i    (depth_i),
		.in_valid_i   (in_valid_i),
		.in_ready_o   (fifo_in_ready),
		.out_data_o   (depth_o),
		.out_valid_o,
		.out_ready_i,
		.depth_o      ()
	);

endmodule
