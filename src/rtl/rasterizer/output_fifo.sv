module output_fifo #(
	parameter int unsigned Depth = 4
) (
	input logic clk_i,
	input logic rst_ni,

	input logic [1:0] fbid_color_i,
	input logic [1:0] fbid_depth_i,
	input logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x_i,
	input logic [rasterizer_pkg::FRAME_Y_WIDTH-1:0] y_i,
	input logic [rasterizer_pkg::TILE_WIDTH-1:0] coverage_mask_i,
	input logic metadata_valid_i,
	output logic metadata_ready_o,

	input logic [rasterizer_pkg::TILE_WIDTH-1:0][rasterizer_pkg::DEPTH_WIDTH-1:0] z_i,
	input logic [rasterizer_pkg::TILE_WIDTH-1:0] depth_mask_i,
	input logic depth_valid_i,
	output logic depth_ready_o,

	input logic [255:0] red_i,
	input logic [255:0] green_i,
	input logic [255:0] blue_i,
	input logic color_valid_i,
	input logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0] triangle_id_i,
	output logic color_ready_o,

	output logic [1:0] fbid_color_o,
	output logic [1:0] fbid_depth_o,
	output logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0] triangle_id_o,
	output logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x_o,
	output logic [rasterizer_pkg::FRAME_Y_WIDTH-1:0] y_o,
	output logic [255:0] red_o,
	output logic [255:0] green_o,
	output logic [255:0] blue_o,
	output logic [255:0] depth1_o,
	output logic [255:0] depth2_o,
	output logic [rasterizer_pkg::TILE_WIDTH-1:0] mask_o,
	output logic out_valid_o,
	input logic out_ready_i
);

	import rasterizer_pkg::*;

	localparam int unsigned METADATA_WIDTH = 2 + 2 + TILE_X_WIDTH + FRAME_Y_WIDTH + TILE_WIDTH;
	localparam int unsigned OUTPUT_WIDTH = METADATA_WIDTH + TRIANGLE_ID_WIDTH + 256 + 256 + 256 + 256 + 256;

	logic [METADATA_WIDTH-1:0] metadata_i;
	logic [METADATA_WIDTH-1:0] metadata_o;
	logic metadata_valid;
	logic metadata_ready;

	logic [OUTPUT_WIDTH-1:0] data_i;
	logic [OUTPUT_WIDTH-1:0] data_o;
	logic data_ready;
	logic [TILE_WIDTH-1:0] mask_i;

	assign metadata_i = {
		fbid_color_i,
		fbid_depth_i,
		tile_x_i,
		y_i,
		coverage_mask_i
	};

	assign metadata_ready_o = metadata_ready;
	assign depth_ready_o = metadata_valid && color_valid_i && data_ready;
	assign color_ready_o = metadata_valid && depth_valid_i && data_ready;
	assign mask_i = metadata_o[TILE_WIDTH-1:0] & depth_mask_i;

	always_comb begin
		data_i = {
			metadata_o[METADATA_WIDTH-1:TILE_WIDTH],
			mask_i,
			triangle_id_i,
			red_i,
			green_i,
			blue_i,
			z_i[TILE_WIDTH / 2 - 1:0],
			z_i[TILE_WIDTH - 1:TILE_WIDTH / 2]
		};
	end

	assign {
		fbid_color_o,
		fbid_depth_o,
		tile_x_o,
		y_o,
		mask_o,
		triangle_id_o,
		red_o,
		green_o,
		blue_o,
		depth1_o,
		depth2_o
	} = data_o;

	my_fifo #(
		.Width (METADATA_WIDTH),
		.Pass  (1'b0),
		.Depth (Depth)
	) metadata_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i     (1'b0),
		.in_data_i   (metadata_i),
		.in_valid_i  (metadata_valid_i),
		.in_ready_o  (metadata_ready),
		.out_data_o  (metadata_o),
		.out_valid_o (metadata_valid),
		.out_ready_i (depth_valid_i && color_valid_i && data_ready),
		.depth_o     ()
	);

	my_fifo #(
		.Width (OUTPUT_WIDTH),
		.Pass  (1'b0),
		.Depth (Depth)
	) data_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i     (1'b0),
		.in_data_i   (data_i),
		.in_valid_i  (metadata_valid && depth_valid_i && color_valid_i),
		.in_ready_o  (data_ready),
		.out_data_o  (data_o),
		.out_valid_o,
		.out_ready_i,
		.depth_o     ()
	);

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (metadata_valid_i && metadata_ready_o) begin
			$display("output_fifo,%0t,input,fbid_color,%0d,fbid_depth,%0d,tile_x,%0d,y,%0d,coverage_mask,%h",
				$time, fbid_color_i, fbid_depth_i, tile_x_i, y_i, coverage_mask_i);
		end

		if (metadata_valid && depth_valid_i && color_valid_i && data_ready) begin
			$display("output_fifo,%0t,input_data,triangle_id,%h,z,%h,depth_mask,%h,red,%h,green,%h,blue,%h",
				$time, triangle_id_i, z_i, depth_mask_i, red_i, green_i, blue_i);
		end

		if (out_valid_o && out_ready_i) begin
			$display("output_fifo,%0t,output,fbid_color,%0d,fbid_depth,%0d,triangle_id,%h,tile_x,%0d,y,%0d,red,%h,green,%h,blue,%h,depth1,%h,depth2,%h,mask,%h",
				$time, fbid_color_o, fbid_depth_o, triangle_id_o, tile_x_o, y_o,
				red_o, green_o, blue_o, depth1_o, depth2_o, mask_o);
		end
	end
`endif

endmodule
