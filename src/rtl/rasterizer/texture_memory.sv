module texture_memory
	import tlul_pkg::*;
#(
	parameter int unsigned TextureWidth  = 32,
	parameter int unsigned TextureHeight = 32,
	parameter int unsigned TextureCount  = 32,
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
	input  logic                                                           out_ready_i,

	input  tl_h2d_t tl_i,
	output tl_d2h_t tl_o
);

	import rasterizer_pkg::*;

	localparam int unsigned TEXTURE_U_WIDTH = $clog2(TextureWidth);
	localparam int unsigned TEXTURE_NUMBER_WIDTH = $clog2(TextureCount);
	localparam int unsigned MEMORY_DEPTH = TextureCount * TextureWidth * TextureHeight;
	localparam int unsigned ADDRESS_WIDTH = $clog2(MEMORY_DEPTH);
	localparam int unsigned MEMORY_COUNT = TILE_WIDTH / 2;

	logic [TILE_WIDTH-1:0][ADDRESS_WIDTH-1:0] read_address;
	logic [TILE_WIDTH-1:0][              1:0] ra_offset_q;
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

	// Texture DPRAM with TileLink access

	logic                     tl_req;
	logic                     tl_we;
	logic [ADDRESS_WIDTH-1:0] tl_addr;
	logic [             31:0] tl_wdata;
	logic [             31:0] tl_rdata;
	logic                     tl_rvalid;

	tlul_adapter_sram #(
		.SramAw     (ADDRESS_WIDTH - 2),
		.SramDw     (32),
		.ByteAccess (0)
	) tex_adapter_i (
		.clk_i,
		.rst_ni,
		.tl_i,
		.tl_o,

		.req_o   (tl_req),
		.gnt_i   (!in_valid_i),
		.we_o    (tl_we),
		.addr_o  (tl_addr),
		.wdata_o (tl_wdata),
		.wmask_o (),
		.rdata_i (tl_rdata),
		.rvalid_i(tl_rvalid),
		.rerror_i('0)
	);

	always @(posedge clk_i, negedge rst_ni) begin
	    if (!rst_ni) begin
	      tl_rvalid <= '0;
	      ra_offset_q <= '{default: '0};
	    end else begin
	      tl_rvalid <= tl_req && !in_valid_i && !tl_we;
	      if (in_valid_i && in_ready_o) begin
		      for (int i = 0; i < TILE_WIDTH; i++) begin
		      	ra_offset_q[i] <= read_address[i][1:0];
		      end
	  	  end
	    end
	end

	for (genvar memory = 0; memory < MEMORY_COUNT; memory++) begin : gen_texture_memory

		// TL-UL channel for Texture DPRAM access can only be used when in_valid_i is 0,
		// i.e. when there is currently no ongoing rasterization.

		logic [31:0] rdata1;
		logic [31:0] rdata2;

		if (memory == 0) assign tl_rdata = rdata1;

		assign texel_o[2*memory] = rdata1[8*(ra_offset_q[2*memory]) +: 8];
		assign texel_o[2*memory+1] = rdata2[8*(ra_offset_q[2*memory+1]) +: 8];

		dpram #(
			.DATA_WIDTH(32),
			.DEPTH     (MEMORY_DEPTH / 4),
			.ADDR_WIDTH(ADDRESS_WIDTH - 2)
		) tex_dpram_i (
			.clk_i    (clk_i),

			.rw_addr_i(in_valid_i ? read_address[2 * memory][ADDRESS_WIDTH-1:2] : tl_addr),
			.rw_en_i  (in_valid_i ? in_valid_i && in_ready_o : tl_req),
			.rw_we_i  (in_valid_i ? '0 : tl_we),
			.rw_data_i(in_valid_i ? '0 : tl_wdata),
			.rw_data_o(rdata1),

			.r_addr_i(read_address[2 * memory + 1][ADDRESS_WIDTH-1:2]),
			.r_en_i  (in_valid_i && in_ready_o),
			.r_data_o(rdata2)
		);
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
