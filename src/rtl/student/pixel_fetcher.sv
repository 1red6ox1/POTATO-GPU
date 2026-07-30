// Copyright David Schröder 2026.

module pixel_fetcher #(
	parameter int DEPTH = 8, // Depth of buffers in units of 32 pixels
	parameter int FRAMEW = 1920, // Must be multiple of 32
	parameter int FRAMEH = 1080
) (
	input  logic clk_i,
	input  logic rst_ni,

	output rvlab_ddr_pkg::ddr3_h2d_t req_o,
	input  rvlab_ddr_pkg::ddr3_d2h_t rsp_i,

	output logic [ 7:0] r_o,
	output logic [ 7:0] g_o,
	output logic [ 7:0] b_o,

	input  logic        enable_i,
	input  logic [ 1:0] next_frame_id_i, // may be changed after cx_o = cy_o = 0 = !valid_o
	output logic [10:0] cx_o,
	output logic [10:0] cy_o,
	output logic        valid_o,
	input  logic        consume_i
);

	import rvlab_ddr_pkg::*;

	// Parent should assert enable_i, then wait for
	// valid_o before enabling the HDMI PHY.

	// Physical address of a pixel (in a color channel):
	// +-------+-------+-------+------+---------+-----+
	// | 31:26 | 25:24 | 23:13 | 12:7 |     6:5 | 4:0 |
	// +-------+-------+-------+------+---------+-----+
	// |  6'h0 | frame |    cy |  cxb | channel | cxo |
	// +-------+-------+-------+------+---------+-----+

	// Physical address of a pixel (in a depth channel):
	// +-------+-------+-------+------+---+
	// | 31:25 | 24:23 | 22:12 | 11:1 | 0 |
	// +-------+-------+-------+------+---+
	// |  7'h1 | frame |    cy |   cx | 0 |
	// +-------+-------+-------+------+---+

	// Block address:
	// +-------+-------+-------+------+---------+
	// | 28:26 | 25:24 | 23:13 | 12:7 |     6:5 |
	// +-------+-------+-------+------+---------+
	// |  3'h0 | frame |    cy |   cx | channel |
	// +-------+-------+-------+------+---------+

	localparam int DEPTH_PIX = DEPTH * 32;
	localparam int PIX_SELW = $clog2(DEPTH_PIX);
	localparam int W_CHUNKS = FRAMEW / 32;

	reg [255:0] r_buf_q [DEPTH-1:0];
	reg [255:0] g_buf_q [DEPTH-1:0];
	reg [255:0] b_buf_q [DEPTH-1:0];
	reg [  5:0] cx_q    [DEPTH-1:0];
	reg [ 10:0] cy_q    [DEPTH-1:0];

	// Previous per-pixel validity implementation:
	// reg [DEPTH_PIX-1:0] valid_q; // set when B channel response comes
	logic [DEPTH-1:0] block_valid_q;

	logic [PIX_SELW-1:0] rptr;
	logic [PIX_SELW-6:0] rptr_block;
	logic [PIX_SELW-6:0] wptr; // WPTR is in chunks of 32
	logic [PIX_SELW-6:0] response_block;

	logic [PIX_SELW-1:0] free_size;
	assign free_size = rptr - {wptr, 5'h0};

	assign rptr_block = rptr[PIX_SELW-1:5];
	assign response_block = rsp_i.d_anc[2+:(PIX_SELW-5)];

	logic [ 7:0] pixel_r_q;
	logic [ 7:0] pixel_g_q;
	logic [ 7:0] pixel_b_q;
	logic [10:0] pixel_cx_q;
	logic [10:0] pixel_cy_q;
	logic        pixel_valid_q;

	logic source_valid;
	logic pixel_ready;
	logic load_pixel;

	assign source_valid = block_valid_q[rptr_block];
	assign pixel_ready = ~pixel_valid_q || consume_i;
	assign load_pixel = enable_i && source_valid && pixel_ready;

	assign r_o = pixel_r_q;
	assign g_o = pixel_g_q;
	assign b_o = pixel_b_q;
	assign cx_o = pixel_cx_q;
	assign cy_o = pixel_cy_q;
	assign valid_o = pixel_valid_q;

	// Pixel data and coordinates remain stable while valid_o is waiting
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			pixel_r_q  <= '0;
			pixel_g_q  <= '0;
			pixel_b_q  <= '0;
			pixel_cx_q <= '0;
			pixel_cy_q <= '0;
		end else if (load_pixel) begin
			pixel_r_q  <= r_buf_q[rptr_block][rptr[4:0]*8+:8];
			pixel_g_q  <= g_buf_q[rptr_block][rptr[4:0]*8+:8];
			pixel_b_q  <= b_buf_q[rptr_block][rptr[4:0]*8+:8];
			pixel_cx_q <= {cx_q[rptr_block], rptr[4:0]};
			pixel_cy_q <= cy_q[rptr_block];
		end
	end

	// One-entry ready/valid output stage.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			pixel_valid_q <= 1'b0;
		end else if (!enable_i) begin
			pixel_valid_q <= 1'b0;
		end else if (pixel_ready) begin
			pixel_valid_q <= source_valid;
		end
	end

	logic [ 5:0] fetch_cx;
	logic [10:0] fetch_cy;
	logic [ 1:0] cur_frame_id;

	typedef enum logic [1:0] {
		RED   = 2'b00,
		GREEN = 2'b01,
		BLUE  = 2'b10
	} fetch_state_e;

	fetch_state_e state_q;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			block_valid_q <= '0;
			state_q       <= RED;
			wptr          <= '0;
			rptr          <= '0;
			fetch_cx      <= '0;
			fetch_cy      <= '0;
			cur_frame_id  <= '0;
		end else begin
			if (enable_i) begin
				if (req_o.a_valid && rsp_i.a_ready) begin
					case (state_q)
						RED  : state_q <= GREEN;
						GREEN: state_q <= BLUE;
						BLUE : state_q <= RED;
						default: ;
					endcase
					if (state_q == BLUE) begin
						fetch_cx <= fetch_cx + 1;
						wptr <= wptr + 1;
						if (fetch_cx == W_CHUNKS - 1) begin
							fetch_cx <= '0;
							fetch_cy <= fetch_cy + 1;
							if (fetch_cy == FRAMEH - 1) begin
								fetch_cy <= '0;
								cur_frame_id <= next_frame_id_i;
							end
						end
					end
				end
				if (rsp_i.d_valid && req_o.d_ready) begin
					// channel is given in d_anc field
					if (rsp_i.d_anc[1:0] == BLUE) begin
						block_valid_q[response_block] <= 1'b1;
					end
				end
			end else begin
				block_valid_q <= '0;
				state_q       <= RED;
				wptr          <= '0;
				rptr          <= '0;
				fetch_cx      <= '0;
				fetch_cy      <= '0;
				cur_frame_id  <= '0;
			end

			// rptr points to the next FIFO pixel to move into the output FFs.
			if (load_pixel) begin
				rptr <= rptr + 1;
				if (rptr[4:0] == 5'd31) begin
					block_valid_q[rptr_block] <= 1'b0;
				end
			end
		end
	end

	always_ff @(posedge clk_i) begin
		// CX, CY memory; not resettable
		if (enable_i && req_o.a_valid && rsp_i.a_ready) begin
			cx_q[wptr] <= fetch_cx;
			cy_q[wptr] <= fetch_cy;
		end

		// R, G, B memory; not resettable
		if (enable_i && rsp_i.d_valid && req_o.d_ready) begin
			case (rsp_i.d_anc[1:0])
				RED  : r_buf_q[response_block] <= rsp_i.d_data;
				GREEN: g_buf_q[response_block] <= rsp_i.d_data;
				BLUE : b_buf_q[response_block] <= rsp_i.d_data;
			endcase
		end
	end

	initial begin
		cx_q = '{default: '0};
		cy_q = '{default: '0};
		r_buf_q = '{default: '0};
		g_buf_q = '{default: '0};
		b_buf_q = '{default: '0};
	end

	assign req_o = '{
		a_valid: enable_i && (wptr != (PIX_SELW-5)'(rptr_block - 1)),
		a_opcode: tlul_pkg::Get,
		a_address: {3'h0, cur_frame_id, fetch_cy, fetch_cx, state_q},
		a_mask: '1,
		a_data: '0,
		a_anc: {wptr, state_q},
		d_ready: '1 // We don't issue requests that we can't accomodate
	};

endmodule
