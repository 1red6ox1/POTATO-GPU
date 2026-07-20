module texture_palette (
	input logic clk_i,
	input logic rst_ni,

	input  logic [rasterizer_pkg::TILE_WIDTH-1:0][7:0] index_i,
	input  logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0] triangle_id_i,
	input  logic                                           in_valid_i,
	output logic                                           in_ready_o,

	output logic [255:0]                                  red_o,
	output logic [255:0]                                  green_o,
	output logic [255:0]                                  blue_o,
	output logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0] triangle_id_o,
	output logic                                           out_valid_o,
	input  logic                                           out_ready_i
);

	import rasterizer_pkg::*;

	localparam int unsigned PALETTE_DEPTH = 256;
	localparam int unsigned MEMORY_COUNT = TILE_WIDTH / 2;

	logic [TILE_WIDTH-1:0][23:0] color_q;

	assign in_ready_o = !out_valid_o || out_ready_i;

	always_comb begin
		red_o   = '0;
		green_o = '0;
		blue_o  = '0;

		for (int pixel = 0; pixel < TILE_WIDTH; pixel++) begin
			red_o[8 * pixel +: 8]   = color_q[pixel][23:16];
			green_o[8 * pixel +: 8] = color_q[pixel][15:8];
			blue_o[8 * pixel +: 8]  = color_q[pixel][7:0];
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			out_valid_o <= 1'b0;
		end else if (in_ready_o) begin
			out_valid_o <= in_valid_i;
		end
	end

	always_ff @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			triangle_id_o <= triangle_id_i;
		end
	end

	for (genvar memory = 0; memory < MEMORY_COUNT; memory++) begin : gen_texture_palette
		(* ram_style = "block" *) logic [23:0] palette [0:PALETTE_DEPTH-1];

		initial begin
			for (int index = 0; index < PALETTE_DEPTH; index++) begin
				logic [7:0] red;
				logic [7:0] green;
				logic [7:0] blue;

				red   = {index[7:5], index[7:5], index[7:6]};
				green = {index[4:2], index[4:2], index[4:3]};
				blue  = {index[1:0], index[1:0], index[1:0], index[1:0]};

				if (index[4:2] == index[7:5]
					&& index[1:0] == index[7:6]) begin
					green = red;
					blue  = red;
				end

				palette[index] = {red, green, blue};
			end
		end

		always_ff @(posedge clk_i) begin
			if (in_valid_i && in_ready_o) begin
				color_q[2 * memory]
					<= palette[index_i[2 * memory]];
				color_q[2 * memory + 1]
					<= palette[index_i[2 * memory + 1]];
			end
		end
	end

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			$display("texture_palette,%0t,input,index,%h,triangle_id,%h",
				$time, index_i, triangle_id_i);
		end

		if (out_valid_o && out_ready_i) begin
			$display("texture_palette,%0t,output,red,%h,green,%h,blue,%h,triangle_id,%h",
				$time, red_o, green_o, blue_o, triangle_id_o);
		end
	end
`endif

endmodule
