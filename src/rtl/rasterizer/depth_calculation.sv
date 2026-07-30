module depth_calculation #(
	parameter int unsigned Depth = 4
) (
	input logic clk_i,
	input logic rst_ni,

	input  rasterizer_pkg::triangle_param_t param_i,
	input  logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x_i,
	input  logic [rasterizer_pkg::FRAME_Y_WIDTH-1:0] y_i,
	input  logic in_valid_i,
	output logic in_ready_o,

	output logic [rasterizer_pkg::TILE_WIDTH-1:0][rasterizer_pkg::DEPTH_WIDTH-1:0] depth_o,
	output logic out_valid_o,
	input  logic out_ready_i
);

	import rasterizer_pkg::*;

	logic signed [COORD_WIDTH-1:0] x_i;
	logic signed [DEPTH_INTERP_WIDTH-1:0] z_row;
	(* use_dsp = "yes" *)logic signed [TILE_WIDTH-1:0][2 * DEPTH_INTERP_WIDTH-1:0] z_delta;
	logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] depth_i;
	logic fifo_in_ready;

	assign x_i = COORD_WIDTH'(tile_x_i) << $clog2(TILE_WIDTH);
	assign in_ready_o = fifo_in_ready;

	always_comb begin
		z_row = DEPTH_INTERP_WIDTH'(param_i.z)
			    + DEPTH_INTERP_WIDTH'($signed(param_i.dz_dx) * x_i)
			    + DEPTH_INTERP_WIDTH'($signed(param_i.dz_dy) * $signed(COORD_WIDTH'(y_i)));

		for (int x = 0; x < TILE_WIDTH; x++) begin
			logic signed [DEPTH_INTERP_WIDTH-1:0] z_pixel;

			z_delta[x] = $signed(param_i.dz_dx) * $signed(DEPTH_INTERP_WIDTH'(x));
			z_pixel = z_row + DEPTH_INTERP_WIDTH'(z_delta[x]);

			depth_i[x] = z_pixel[DEPTH_FRAC_WIDTH +: DEPTH_WIDTH];
		end
	end

	my_fifo #(
		.Width (TILE_WIDTH * DEPTH_WIDTH),
		.Pass  (1'b0),
		.Depth (Depth)
	) depth_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i     (1'b0),
		.in_data_i   (depth_i),
		.in_valid_i  (in_valid_i),
		.in_ready_o  (fifo_in_ready),
		.out_data_o  (depth_o),
		.out_valid_o,
		.out_ready_i,
		.depth_o     ()
	);

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			$display("depth_calculation,%0t,input,param,%h,tile_x,%0d,y,%0d",
				$time, param_i, tile_x_i, y_i);
		end

		if (out_valid_o && out_ready_i) begin
			$display("depth_calculation,%0t,output,depth,%h", $time, depth_o);
		end
	end
`endif

endmodule
