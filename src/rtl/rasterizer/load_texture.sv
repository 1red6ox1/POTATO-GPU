module load_texture (
	input logic clk_i,
	input logic rst_ni,

	input  tlul_pkg::tl_h2d_t tl_i,
	output tlul_pkg::tl_d2h_t tl_o,

	input  logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0] triangle_id_i,
	input  logic                                         in_valid_i,
	output logic                                         in_ready_o,

	output logic [rasterizer_pkg::TEXTURE_ID_WIDTH-1:0] texture_id_o,
	output logic                                        out_valid_o,
	input  logic                                        out_ready_i
);

	import rasterizer_pkg::*;

	logic req;
	logic we;
	logic [TRIANGLE_ID_WIDTH-1:0] addr;
	logic [31:0] wdata;
	logic valid_q;

	assign in_ready_o = !valid_q || out_ready_i;
	assign out_valid_o = valid_q;

	tlul_adapter_sram #(
		.SramDw(32),
		.SramAw(TRIANGLE_ID_WIDTH),
		.Outstanding(1),
		.ByteAccess(1),
		.ErrOnWrite(0),
		.ErrOnRead(1)
	) tlul_adapter_sram_i (
		.clk_i,
		.rst_ni,
		.tl_i,
		.tl_o,
		.req_o   (req),
		.gnt_i   (1'b1),
		.we_o    (we),
		.addr_o  (addr),
		.wdata_o (wdata),
		.wmask_o (),
		.rdata_i ('0),
		.rvalid_i(1'b0),
		.rerror_i(2'b00)
	);

	dpram #(
		.DATA_WIDTH(TEXTURE_ID_WIDTH),
		.DEPTH(1 << TRIANGLE_ID_WIDTH),
		.ADDR_WIDTH(TRIANGLE_ID_WIDTH)
	) texture_id_memory_i (
		.clk_i,
		.rw_addr_i(addr),
		.rw_en_i  (req && we),
		.rw_we_i  (req && we),
		.rw_data_i(TEXTURE_ID_WIDTH'(wdata)),
		.rw_data_o(),
		.r_addr_i (triangle_id_i),
		.r_en_i   (in_valid_i && in_ready_o),
		.r_data_o (texture_id_o)
	);

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			valid_q <= 1'b0;
		end else if (in_ready_o) begin
			valid_q <= in_valid_i;
		end
	end

endmodule
