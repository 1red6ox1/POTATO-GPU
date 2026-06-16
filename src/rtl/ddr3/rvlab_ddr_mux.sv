/*
Copyright 2026 David Schröder.

DDR Bus multiplexer (M:1 socket).
May HOL block if host does not accept response.
*/

module rvlab_ddr_mux #(
	// Lower indices have priority over high ones
	parameter int N = 2, // >= 2
	parameter int MAX_OUTSTANDING = 16 // Power of 2, >= 2
) (
	input  logic clk_i,
	input  logic rst_ni,

	input  rvlab_ddr_pkg::ddr3_h2d_t host_i [N-1:0],
	output rvlab_ddr_pkg::ddr3_d2h_t host_o [N-1:0],
	output rvlab_ddr_pkg::ddr3_h2d_t dev_o,
	input  rvlab_ddr_pkg::ddr3_d2h_t dev_i
);

	import rvlab_ddr_pkg::*;

	localparam int LOGN = $clog2(N);
	localparam int LOG_REQS = $clog2(MAX_OUTSTANDING);

	reg [DDR_ANCW-1:0] ancillary_mem [MAX_OUTSTANDING-1:0];
	reg [    LOGN-1:0]    source_mem [MAX_OUTSTANDING-1:0];

	logic [LOG_REQS-1:0] rptr, wptr;

	ddr3_h2d_t sel_host_h2d;
	logic [LOGN-1:0] sel_host_id;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			rptr <= '0;
			wptr <= '0;
		end else begin
			if (dev_o.a_valid && dev_i.a_ready) begin
				wptr <= wptr + 1;
			end
			if (dev_i.d_valid && dev_o.d_ready) begin
				rptr <= rptr + 1;
			end
		end
	end

	always_ff @(posedge clk_i) begin
		if (dev_o.a_valid && dev_i.a_ready) begin
			ancillary_mem[wptr] <= sel_host_h2d.a_anc;
			source_mem[wptr] <= sel_host_id;
		end
	end

	always_comb begin
		for (int i = 0; i < N; i++) begin
			host_o[i] = '{
				d_valid: dev_i.d_valid && source_mem[rptr] == i,
				d_opcode: dev_i.d_opcode,
				d_data: dev_i.d_data,
				d_anc: ancillary_mem[rptr],
				a_ready: dev_i.a_ready && sel_host_id == i
			};
		end
	end

	assign dev_o = sel_host_h2d;

	// Selected host generation
	always_comb begin
		sel_host_h2d = host_i[0];
		sel_host_id = 0;
		for (int i = 1; i <= N; i++) begin
			if (host_i[N-i].a_valid) begin
				sel_host_h2d = host_i[N-i];
				sel_host_id = N-i;
			end
		end
	end

endmodule
