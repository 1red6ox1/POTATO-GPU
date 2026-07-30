/*
Copyright 2026 David Schröder.

DDR Bus multiplexer (M:1 socket).
May HOL block if host does not accept response.
*/

module rvlab_ddr_mux #(
	// Lower indices have priority over high ones
	parameter int N = 2, // >= 2
	parameter int MAX_OUTSTANDING = 32 // Power of 2, >= 2
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
	localparam int COUNT_WIDTH = $clog2(MAX_OUTSTANDING + 1);

	reg [DDR_ANCW-1:0] ancillary_mem [MAX_OUTSTANDING-1:0];
	reg [    LOGN-1:0] source_mem    [MAX_OUTSTANDING-1:0];

	logic [   LOG_REQS-1:0] rptr, wptr;
	logic [COUNT_WIDTH-1:0] outstanding_q;

	ddr3_h2d_t       sel_host_h2d;
	logic [LOGN-1:0] sel_host_id;
	logic [LOGN-1:0] response_host_id;
	logic            route_empty;
	logic            route_full;
	logic            request_fire;
	logic            response_fire;

	assign route_empty = outstanding_q == '0;
	assign route_full = outstanding_q == COUNT_WIDTH'(MAX_OUTSTANDING);
	assign response_host_id = source_mem[rptr];
	assign request_fire = dev_o.a_valid && dev_i.a_ready;
	assign response_fire = dev_i.d_valid && dev_o.d_ready;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			rptr          <= '0;
			wptr          <= '0;
			outstanding_q <= '0;
		end else begin
			if (request_fire) begin
				wptr <= wptr + 1'b1;
			end
			if (response_fire) begin
				rptr <= rptr + 1'b1;
			end

			unique case ({request_fire, response_fire})
				2'b10: outstanding_q <= outstanding_q + 1'b1;
				2'b01: outstanding_q <= outstanding_q - 1'b1;
				default: begin
				end
			endcase
		end
	end

	always_ff @(posedge clk_i) begin
		if (request_fire) begin
			ancillary_mem[wptr] <= sel_host_h2d.a_anc;
			source_mem[wptr] <= sel_host_id;
		end
	end

	always_comb begin
		for (int i = 0; i < N; i++) begin
			host_o[i] = '{
				d_valid: dev_i.d_valid && !route_empty && response_host_id == LOGN'(i),
				d_opcode: dev_i.d_opcode,
				d_data: dev_i.d_data,
				d_anc: ancillary_mem[rptr],
				a_ready: dev_i.a_ready && !route_full && sel_host_id == LOGN'(i)
			};
		end
	end

	always_comb begin
		dev_o = sel_host_h2d;
		dev_o.a_valid = sel_host_h2d.a_valid && !route_full;
		dev_o.d_ready = 1'b0;
		if (!route_empty) begin
			dev_o.d_ready = host_i[response_host_id].d_ready;
		end
	end

	// Selected host generation
	always_comb begin
		sel_host_h2d = host_i[0];
		sel_host_id = '0;
		for (int i = 1; i <= N; i++) begin
			if (host_i[N-i].a_valid) begin
				sel_host_h2d = host_i[N-i];
				sel_host_id = LOGN'(N-i);
			end
		end
	end

endmodule
