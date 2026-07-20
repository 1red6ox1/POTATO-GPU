module texture_memory #(
	parameter int unsigned TextureWidth  = 32,
	parameter int unsigned TextureHeight = 32,
	parameter int unsigned TextureCount  = 30,
	parameter int unsigned TextureSeed   = 32'h71c3a95d
) (
	input logic clk_i,
	input logic rst_ni,

	input  logic [rasterizer_pkg::TILE_WIDTH-1:0][$clog2(TextureWidth)-1:0]  u_i,
	input  logic [rasterizer_pkg::TILE_WIDTH-1:0][$clog2(TextureHeight)-1:0] v_i,
	input  logic [rasterizer_pkg::TEXTURE_ID_WIDTH-1:0]                    texture_id_i,
	input  logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0]                   triangle_id_i,
	input  logic                                                            in_valid_i,
	output logic                                                            in_ready_o,

	output logic [rasterizer_pkg::TILE_WIDTH-1:0][7:0]                    texel_o,
	output logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0]                  triangle_id_o,
	output logic                                                           out_valid_o,
	input  logic                                                           out_ready_i
);

	import rasterizer_pkg::*;

	localparam int unsigned TEXTURE_U_WIDTH = $clog2(TextureWidth);
	localparam int unsigned TEXTURE_NUMBER_WIDTH = $clog2(TextureCount);
	localparam int unsigned MEMORY_DEPTH = TextureCount * TextureWidth * TextureHeight;
	localparam int unsigned ADDRESS_WIDTH = $clog2(MEMORY_DEPTH);
	localparam int unsigned MEMORY_COUNT = TILE_WIDTH / 2;

	// CC0 32x32 N64-style brick texture by n64guy, converted to RGB332.
	// Every row is stored right-to-left so [8 * u +: 8] reads left-to-right.
	localparam logic [255:0] TEXTURE_DATA [0:31] = '{
		256'h926d929292929292926d6d49494949496d6d926d6d6d6d6d6d6d6d6d6d6d926d,
		256'hdbdbdbb649dbdbb6db92926d9292b66d9292929292b6929292929292929292db,
		256'hdbdbdbb6dbb6dbdbdbdb92dbffffdb926ddbb6ffdbdbb6dbb6dbdbdbdbdbdbdb,
		256'hdbffffffffffffffffffffffffdbdb926db6b6ffdbffffdbffffffffdbdbb6db,
		256'hdbdbb6dbdbdbdbdb6ddbdbdbffffdb926d92dbdbdbdbdbdbdbb6dbdbdbdbdbdb,
		256'hdbdbdbb6dbdbdb6ddbdbdbdbdbffdb926d92dbdbdbdbdbdbdbdbdbdbdbb6b6b6,
		256'hdbb6b6dbdbdb6ddbdbdbdbdbdbdbdb926d92dbdbdbdbdbdbdbdbdbdbdbdbdbdb,
		256'hb6dbdbdb6ddb6d6ddbdbdbdbdbdbdb494992dbdbdbdbdbdbdbdbdbdbdbdbdbdb,
		256'hdbdbdbdbdb6ddbdbdbdbdbdbdbdbdb922492dbdbdbdbdbdbdbdbdbdbdbdbb6db,
		256'hdbdbdbdbdbdbdbdbdbdbdbdbdbdbdb922492b6dbdbdbdbdbdbdbdbdbdbdbdbdb,
		256'hdbdbdbdbdbdbdbdbb6dbdbb6dbffdb494992b6dbb6dbdbdbdbdbdbdbdbdbdbb6,
		256'hdbdbb6dbdbdbdbdbdbdbdbdbffffb6006d92b6dbdbdbdbdbdbdbdbdbdbdbdbdb,
		256'hffffffffffffffdbffdbffffffff49499292dbffffffffffffffffffffffffdb,
		256'hdbdbdbdbdbdbdbdbdbdbdbffff6d49496d6ddbdbdbffb6dbdbdbdbdbdbdbb6b6,
		256'hdbb6db6db6b6dbb6db6d6d496d92926d6d922424dbb6dbb6b6dbdbdbdbdbdbdb,
		256'h6db692926d6d929292926d926db692926ddb24b6b6dbb6b649b692926d929292,
		256'h24496d929292b69292b6b6db9292b6926d929292926d6db6dbb69292dbb69292,
		256'h49b6b6b6b6dbdbb6dbb6dbdbdbdbdbdbdbdbffffdbdbdbb6dbdbdbdbb6db926d,
		256'h4992b6dbdbdbb6dbdbdbdbdbdbdbdbdbdbffffffffdbdbdbdbdbdbdbdbdbdb92,
		256'h92b6dbffffffffdbdbdbdbdbdbdbdbdbdbdbdbdbdbffffffdbdbdbdbffffb6b6,
		256'h6d6ddbdbdbdbffdbdbdbdbdbdbdbdbdbdbdbdb6ddbdbdbdbdbdbdbdbffffdb92,
		256'h6d9292dbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbffdbdb92,
		256'h6d92dbb6dbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdb6ddbdbdbdbdbdbdbffdbdb92,
		256'h6d92dbb6dbdbdbdbdbdbdbdbdbdbdbdbdb6ddb6ddbdbdbdbdbdbdbdbffdbb66d,
		256'h6d92dbdbdbdb6ddbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbffdb926d,
		256'h6d92dbdbdbdbdbb6db6ddbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbffdbb692,
		256'h6d92dbdbdbdbb6dbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbffff926d,
		256'h92b6dbdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbb6b6dbdbdbdbdbdbdbffffdbdb49,
		256'h92b6ffb6dbdbb6dbb6dbdbdbdbdbdbdbdbdbdbdbffdbffffffffffffffdbdb00,
		256'h6db6dbdbdbdbdb24dbffffffffdbdbffdbffffffffffffffdbffffdbffdbdb24,
		256'h6d6ddbdbb6dbb6b649b6b6dbdbdbb66d49b692dbb6b6b6dbdbdbdbdbdbdbdb24,
		256'h6d926d6d926d9249006d6d926d9249929249926d92b6b6b6b69292929292496d
	};

	function automatic logic [7:0] make_random_texel(
		input int unsigned texture_number,
		input int unsigned u,
		input int unsigned v
	);
		logic [31:0] random;

		random = TextureSeed;
		random = random ^ 32'(texture_number * 32'h9e3779b9);
		random = random ^ 32'(u * 32'h85ebca6b);
		random = random ^ 32'(v * 32'hc2b2ae35);
		random = random ^ (random >> 13);
		random = random * 32'h5bd1e995;
		random = random ^ (random >> 15);

		make_random_texel = random[7:0];
	endfunction

	logic [TILE_WIDTH-1:0][ADDRESS_WIDTH-1:0] read_address;
	logic [TEXTURE_NUMBER_WIDTH-1:0] texture_number;

	assign in_ready_o = !out_valid_o || out_ready_i;

	always_comb begin
		texture_number = '0;

		if (texture_id_i < TEXTURE_ID_WIDTH'(TextureCount)) begin
			texture_number = TEXTURE_NUMBER_WIDTH'(texture_id_i);
		end

		for (int pixel = 0; pixel < TILE_WIDTH; pixel++) begin
			read_address[pixel] = {
				texture_number,
				v_i[pixel],
				u_i[pixel]
			};
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

	for (genvar memory = 0; memory < MEMORY_COUNT; memory++) begin : gen_texture_memory
		(* ram_style = "block" *) logic [7:0] texture [0:MEMORY_DEPTH-1];

		initial begin
			for (int texture_number = 0; texture_number < TextureCount; texture_number++) begin
				for (int v = 0; v < TextureHeight; v++) begin
					for (int u = 0; u < TextureWidth; u++) begin
						if (texture_number == 0) begin
							texture[(texture_number * TextureHeight + v) * TextureWidth + u]
								= TEXTURE_DATA[v][8 * u +: 8];
						end else begin
							texture[(texture_number * TextureHeight + v) * TextureWidth + u]
								= make_random_texel(texture_number, u, v);
						end
					end
				end
			end
		end

		always_ff @(posedge clk_i) begin
			if (in_valid_i && in_ready_o) begin
				texel_o[2 * memory]     <= texture[read_address[2 * memory]];
				texel_o[2 * memory + 1] <= texture[read_address[2 * memory + 1]];
			end
		end
	end

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			$display("texture_memory,%0t,input,u,%h,v,%h,texture_id,%h,triangle_id,%h",
				$time, u_i, v_i, texture_id_i, triangle_id_i);
		end

		if (out_valid_o && out_ready_i) begin
			$display("texture_memory,%0t,output,texel,%h,triangle_id,%h",
				$time, texel_o, triangle_id_o);
		end
	end
`endif

endmodule
