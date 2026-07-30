// Copyright 2026 David Schröder.

module frameclear_dma #(
	parameter int FRAMEW = 1920, // Must be multiple of 32
	parameter int FRAMEH = 1080
) (
	input  logic clk_i,
	input  logic rst_ni,

	input  tlul_pkg::tl_h2d_t tl_i,
	output tlul_pkg::tl_d2h_t tl_o,
	output rvlab_ddr_pkg::ddr3_h2d_t ddr_o,
	input  rvlab_ddr_pkg::ddr3_d2h_t ddr_i
);

	import tlul_pkg::*;
	import rvlab_ddr_pkg::*;
	import frameclear_dma_reg_pkg::*;

	localparam int W_CHUNKS = FRAMEW / 32;
	localparam int D_CHUNKS = FRAMEW / 16;

	frameclear_dma_reg2hw_t reg2hw;
	frameclear_dma_hw2reg_t hw2reg;

	frameclear_dma_reg_top reg_top_i (
		.clk_i,
		.rst_ni,
		.tl_i,
		.tl_o,
		.reg2hw,
		.hw2reg,
		.devmode_i('1)
	);

	logic [ 1:0] clear_fbid;
	logic [23:0] clear_color;
	logic        clear_mode;

	logic [ 7:0] clear_r, clear_g, clear_b;

	assign clear_r     = clear_color[23:16];
	assign clear_g     = clear_color[15: 8];
	assign clear_b     = clear_color[ 7: 0];

	logic [255:0] tiled_r, tiled_g, tiled_b;
	generate
		for (genvar i = 0; i < 32; i++) begin : gen_tiled_colors
			assign tiled_r[8*i+:8] = clear_r;
			assign tiled_g[8*i+:8] = clear_g;
			assign tiled_b[8*i+:8] = clear_b;
		end : gen_tiled_colors
	endgenerate

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			clear_fbid <= '0;
			clear_color <= '0;
			clear_mode <= '0;
		end else begin
			if (reg2hw.status.qe) begin
				clear_fbid <= reg2hw.fbid.q;
				clear_color <= reg2hw.clear_color.q;
				clear_mode <= reg2hw.mode.q;
			end
		end
	end

	typedef enum logic [1:0] {
		RED   = 2'b00,
		GREEN = 2'b01,
		BLUE  = 2'b10
	} state_e;

	logic [ 6:0] cx_q;
	logic [10:0] cy_q;

	state_e state_q;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			cx_q <= '0;
			cy_q <= '0;
			state_q <= RED;
		end else begin
			if (ddr_o.a_valid && ddr_i.a_ready) begin
				if (clear_mode) begin
					cx_q <= cx_q + 1;
					if (cx_q == D_CHUNKS - 1) begin
						cx_q <= '0;
						cy_q <= cy_q + 1;
						if (cy_q == FRAMEH - 1) begin
							cy_q <= '0;
						end
					end
				end else begin
					unique case (state_q)
						RED    : state_q <= GREEN;
						GREEN  : state_q <= BLUE;
						BLUE   : state_q <= RED;
					endcase
					if (state_q == BLUE) begin
						cx_q <= cx_q + 1;
						if (cx_q == W_CHUNKS - 1) begin
							cx_q <= '0;
							cy_q <= cy_q + 1;
							if (cy_q == FRAMEH - 1) begin
								cy_q <= '0;
							end
						end
					end
				end
			end
		end
	end

	always_comb begin
		ddr_o = '{
			a_valid: reg2hw.status.q && ~reg2hw.status.qe,
			a_opcode: PutFullData,
			a_address: '0,
			a_mask: 32'hFFFFFFFF,
			d_ready: '1,
			default: '0
		};
		if (clear_mode) begin
			ddr_o.a_address = {4'h2, clear_fbid, cy_q, cx_q};
			ddr_o.a_data = '0;
		end else begin
			ddr_o.a_address = {3'h0, clear_fbid, cy_q, cx_q[5:0], 2'(state_q)};
			unique case (state_q)
				RED  : ddr_o.a_data = tiled_r;
				GREEN: ddr_o.a_data = tiled_g;
				BLUE : ddr_o.a_data = tiled_b;
			endcase
		end
	end

	assign hw2reg.status.d = '0;
	assign hw2reg.status.de = ddr_o.a_valid && ddr_i.a_ready && cy_q == FRAMEH - 1
								  && ((!clear_mode && state_q == BLUE && cx_q == W_CHUNKS - 1)
									  || (clear_mode && cx_q == D_CHUNKS - 1));

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (reg2hw.status.qe) begin
			$display("frameclear_cmd,%0t,fbid,%0d,mode,%0d,color,%h",
			         $time, reg2hw.fbid.q, reg2hw.mode.q,
			         reg2hw.clear_color.q);
		end
	end
`endif

endmodule
