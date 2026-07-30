// Copyright 2026 Ruslan Kharasov.

module rasterizer_status (
	input logic clk_i,
	input logic rst_ni,

	input  tlul_pkg::tl_h2d_t tl_i,
	output tlul_pkg::tl_d2h_t tl_o,

	input  logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0] triangle_id_i,
	input  logic in_valid_i,
	output logic in_ready_o,

	output logic out_valid_o,
	input  logic out_ready_i,
	input  logic writer_busy_i
);

	import rasterizer_status_reg_pkg::*;
	import rasterizer_pkg::*;

	rasterizer_status_hw2reg_t hw2reg;
	logic completion_pending_q;
	logic completion_marker;
	logic completion_set_q;

	assign completion_marker = in_valid_i && triangle_id_i == COMPLETION_TRIANGLE_ID;
	assign in_ready_o = completion_marker ? 1'b1 : out_ready_i;
	assign out_valid_o = in_valid_i && triangle_id_i != COMPLETION_TRIANGLE_ID;

	rasterizer_status_reg_top rasterizer_status_reg_top_i (
		.clk_i,
		.rst_ni,
		.tl_i,
		.tl_o,
		.hw2reg,
		.devmode_i(1'b1)
	);

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			completion_pending_q <= 1'b0;
			completion_set_q <= 1'b0;
		end else begin
			completion_set_q <= 1'b0;

			if (completion_pending_q && !writer_busy_i) begin
				completion_pending_q <= 1'b0;
				completion_set_q <= 1'b1;
			end

			if (completion_marker && in_ready_o) begin
				completion_pending_q <= 1'b1;
			end
		end
	end

	assign hw2reg.status.d  = 1'b1;
	assign hw2reg.status.de = completion_set_q;

endmodule
