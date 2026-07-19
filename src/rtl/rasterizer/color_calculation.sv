module color_calculation
import rasterizer_pkg::*;
#(
	parameter int unsigned FIFO_DEPTH = 8
) (
	input logic clk_i,
	input logic rst_ni,

	input logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] u_i,
	input logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] v_i,
	input logic                                 in_valid_i,
	output logic                                in_ready_o,

	output logic [255:0] red_o,
	output logic [255:0] green_o,
	output logic [255:0] blue_o,
	output logic         out_valid_o,
	input logic          out_ready_i
);

	localparam logic signed [63:0] UVQ_ONE = 64'sd1 <<< UVQ_FRAC_WIDTH;

	logic signed [63:0] u_fixed [TILE_WIDTH-1:0];
	logic signed [63:0] v_fixed [TILE_WIDTH-1:0];
	logic signed [63:0] r_fixed [TILE_WIDTH-1:0];
	logic signed [63:0] red_scaled [TILE_WIDTH-1:0];
	logic signed [63:0] green_scaled [TILE_WIDTH-1:0];
	logic signed [63:0] blue_scaled [TILE_WIDTH-1:0];
	logic [255:0] red_i;
	logic [255:0] green_i;
	logic [255:0] blue_i;
	logic red_fifo_in_ready;
	logic green_fifo_in_ready;
	logic blue_fifo_in_ready;
	logic red_fifo_valid;
	logic green_fifo_valid;
	logic blue_fifo_valid;
	logic in_fire;

	assign in_ready_o = red_fifo_in_ready
	                  && green_fifo_in_ready
	                  && blue_fifo_in_ready;
	assign in_fire = in_valid_i && in_ready_o;
	assign out_valid_o = red_fifo_valid
	                   && green_fifo_valid
	                   && blue_fifo_valid;

	always_comb begin
		red_i = '0;
		green_i = '0;
		blue_i = '0;

		for (int pixel = 0; pixel < TILE_WIDTH; pixel++) begin
			u_fixed[pixel] = {{(64-UVQ_WIDTH){u_i[pixel][UVQ_WIDTH-1]}}, u_i[pixel]};
			v_fixed[pixel] = {{(64-UVQ_WIDTH){v_i[pixel][UVQ_WIDTH-1]}}, v_i[pixel]};
			r_fixed[pixel] = UVQ_ONE - u_fixed[pixel] - v_fixed[pixel];
			red_scaled[pixel] = (r_fixed[pixel] <<< 8) - r_fixed[pixel];
			green_scaled[pixel] = (v_fixed[pixel] <<< 8) - v_fixed[pixel];
			blue_scaled[pixel] = (u_fixed[pixel] <<< 8) - u_fixed[pixel];

			if (r_fixed[pixel] >= UVQ_ONE) begin
				red_i[8*pixel+:8] = 8'hff;
			end else if (r_fixed[pixel] > 0) begin
				red_i[8*pixel+:8] = red_scaled[pixel][UVQ_FRAC_WIDTH+:8];
			end

			if (v_fixed[pixel] >= UVQ_ONE) begin
				green_i[8*pixel+:8] = 8'hff;
			end else if (v_fixed[pixel] > 0) begin
				green_i[8*pixel+:8] = green_scaled[pixel][UVQ_FRAC_WIDTH+:8];
			end

			if (u_fixed[pixel] >= UVQ_ONE) begin
				blue_i[8*pixel+:8] = 8'hff;
			end else if (u_fixed[pixel] > 0) begin
				blue_i[8*pixel+:8] = blue_scaled[pixel][UVQ_FRAC_WIDTH+:8];
			end
		end
	end

	my_fifo #(
		.Width (256),
		.Pass  (1'b0),
		.Depth (FIFO_DEPTH)
	) red_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i      (1'b0),
		.in_data_i    (red_i),
		.in_valid_i   (in_fire),
		.in_ready_o   (red_fifo_in_ready),
		.out_data_o   (red_o),
		.out_valid_o  (red_fifo_valid),
		.out_ready_i  (out_ready_i && out_valid_o),
		.depth_o      ()
	);

	my_fifo #(
		.Width (256),
		.Pass  (1'b0),
		.Depth (FIFO_DEPTH)
	) green_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i      (1'b0),
		.in_data_i    (green_i),
		.in_valid_i   (in_fire),
		.in_ready_o   (green_fifo_in_ready),
		.out_data_o   (green_o),
		.out_valid_o  (green_fifo_valid),
		.out_ready_i  (out_ready_i && out_valid_o),
		.depth_o      ()
	);

	my_fifo #(
		.Width (256),
		.Pass  (1'b0),
		.Depth (FIFO_DEPTH)
	) blue_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i      (1'b0),
		.in_data_i    (blue_i),
		.in_valid_i   (in_fire),
		.in_ready_o   (blue_fifo_in_ready),
		.out_data_o   (blue_o),
		.out_valid_o  (blue_fifo_valid),
		.out_ready_i  (out_ready_i && out_valid_o),
		.depth_o      ()
	);

endmodule
