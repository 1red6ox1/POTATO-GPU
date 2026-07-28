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
	input  logic                                           out_ready_i,

	input  tlul_pkg::tl_h2d_t tl_i,
	output tlul_pkg::tl_d2h_t tl_o
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

	// Palette DPRAM with TileLink access

	logic                             tl_req;
	logic                             tl_we;
	logic [$clog2(PALETTE_DEPTH)-1:0] tl_addr;
	logic [                     31:0] tl_wdata;
	logic [                     31:0] tl_rdata;
	logic                             tl_rvalid;

	tlul_adapter_sram #(
		.SramAw     ($clog2(PALETTE_DEPTH)),
		.SramDw     (32)
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
		.rdata_i ({24'h0, color_q[0]}),
		.rvalid_i(tl_rvalid),
		.rerror_i('0)
	);

	always @(posedge clk_i, negedge rst_ni) begin
	    if (!rst_ni) begin
	      tl_rvalid <= '0;
	    end else begin
	      tl_rvalid <= tl_req && !in_valid_i && !tl_we;
	    end
	end

	for (genvar memory = 0; memory < MEMORY_COUNT; memory++) begin : gen_texture_palette
		dpram #(
			.DATA_WIDTH(24),
			.DEPTH     (PALETTE_DEPTH),
			.ADDR_WIDTH($clog2(PALETTE_DEPTH))
		) palette_dpram_i (
			.clk_i,

			.rw_addr_i(in_valid_i ? index_i[2 * memory] : tl_addr),
			.rw_en_i  (in_valid_i ? in_valid_i && in_ready_o : tl_req),
			.rw_we_i  (in_valid_i ? '0 : tl_we),
			.rw_data_i(in_valid_i ? '0 : tl_wdata),
			.rw_data_o(color_q[2 * memory]),

			.r_addr_i(index_i[2 * memory + 1]),
			.r_en_i  (in_valid_i && in_ready_o),
			.r_data_o(color_q[2 * memory + 1])
		);
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
