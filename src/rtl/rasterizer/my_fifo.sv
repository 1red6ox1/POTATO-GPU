// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

module my_fifo #(
	parameter int unsigned Width = 16,
	parameter bit          Pass  = 1'b0,
	parameter int unsigned Depth = 4,
	parameter bit          UseBram = 1'b0,
	localparam int unsigned FIFO_DEPTH_WIDTH = (Depth == 0) ? 1 : $clog2(Depth + 1)
) (
	input logic clk_i,
	input logic rst_ni,
	input logic clear_i,

	input  logic [Width-1:0] in_data_i,
	input  logic in_valid_i,
	output logic in_ready_o,

	output logic [Width-1:0] out_data_o,
	output logic out_valid_o,
	input  logic out_ready_i,

	output logic [FIFO_DEPTH_WIDTH-1:0] depth_o
);

	if (Depth == 0) begin : passthrough_fifo
		assign in_ready_o  = out_ready_i;
		assign out_data_o  = in_data_i;
		assign out_valid_o = in_valid_i;
		assign depth_o     = '0;
	end else if (Depth == 1) begin : register_fifo
		logic [Width-1:0] data_q;
		logic valid_q;

		assign in_ready_o = !valid_q || out_ready_i;
		assign out_data_o = (Pass && !valid_q) ? in_data_i : data_q;
		assign out_valid_o = valid_q || (Pass && in_valid_i);
		assign depth_o = FIFO_DEPTH_WIDTH'(valid_q);

		always_ff @(posedge clk_i) begin
			if (in_valid_i && in_ready_o
				&& !(Pass && !valid_q && out_ready_i)) begin
				data_q <= in_data_i;
			end
		end

		always_ff @(posedge clk_i or negedge rst_ni) begin
			if (~rst_ni) begin
				valid_q <= 1'b0;
			end else if (clear_i) begin
				valid_q <= 1'b0;
			end else if (in_ready_o) begin
				valid_q <= in_valid_i
					&& !(Pass && !valid_q && out_ready_i);
			end
		end
	end else if (Depth <= 10 && !UseBram) begin : distributed_fifo
		localparam int unsigned FIFO_POINTER_WIDTH = $clog2(Depth);

		(* ram_style = "distributed" *) logic [Width-1:0] memory [0:Depth-1];
		logic [FIFO_POINTER_WIDTH-1:0] write_pointer_q;
		logic [FIFO_POINTER_WIDTH-1:0] read_pointer_q;
		logic [FIFO_DEPTH_WIDTH-1:0] depth_q;
		logic [Width-1:0] data_q;
		logic valid_q;

		assign in_ready_o = depth_q < FIFO_DEPTH_WIDTH'(Depth)
			|| (valid_q && out_ready_i);
		assign out_data_o = (Pass && !valid_q && depth_q == '0) ? in_data_i : data_q;
		assign out_valid_o = valid_q
			|| (Pass && !valid_q && depth_q == '0 && in_valid_i);
		assign depth_o = depth_q;

		always_ff @(posedge clk_i) begin
			if (in_valid_i && in_ready_o
				&& !(Pass && !valid_q && depth_q == '0)) begin
				memory[write_pointer_q] <= in_data_i;
			end

			if ((!valid_q && depth_q != '0)
				|| (valid_q && out_ready_i && depth_q > FIFO_DEPTH_WIDTH'(1))) begin
				data_q <= memory[read_pointer_q];
			end else if (Pass && !valid_q && depth_q == '0
				&& in_valid_i && !out_ready_i) begin
				data_q <= in_data_i;
			end
		end

		always_ff @(posedge clk_i or negedge rst_ni) begin
			if (~rst_ni) begin
				write_pointer_q <= '0;
			end else if (clear_i) begin
				write_pointer_q <= '0;
			end else if (in_valid_i && in_ready_o
				&& !(Pass && !valid_q && depth_q == '0)) begin
				if (write_pointer_q == FIFO_POINTER_WIDTH'(Depth - 1)) begin
					write_pointer_q <= '0;
				end else begin
					write_pointer_q <= write_pointer_q + 1'b1;
				end
			end
		end

		always_ff @(posedge clk_i or negedge rst_ni) begin
			if (~rst_ni) begin
				read_pointer_q <= '0;
			end else if (clear_i) begin
				read_pointer_q <= '0;
			end else if ((!valid_q && depth_q != '0)
				|| (valid_q && out_ready_i && depth_q > FIFO_DEPTH_WIDTH'(1))) begin
				if (read_pointer_q == FIFO_POINTER_WIDTH'(Depth - 1)) begin
					read_pointer_q <= '0;
				end else begin
					read_pointer_q <= read_pointer_q + 1'b1;
				end
			end
		end

		always_ff @(posedge clk_i or negedge rst_ni) begin
			if (~rst_ni) begin
				depth_q <= '0;
			end else if (clear_i) begin
				depth_q <= '0;
			end else begin
				unique case ({
					(in_valid_i && in_ready_o
						&& !(Pass && !valid_q && depth_q == '0))
					|| (Pass && !valid_q && depth_q == '0
						&& in_valid_i && !out_ready_i),
					valid_q && out_ready_i
				})
					2'b10: depth_q <= depth_q + 1'b1;
					2'b01: depth_q <= depth_q - 1'b1;
					default: begin
					end
				endcase
			end
		end

		always_ff @(posedge clk_i or negedge rst_ni) begin
			if (~rst_ni) begin
				valid_q <= 1'b0;
			end else if (clear_i) begin
				valid_q <= 1'b0;
			end else if ((!valid_q && depth_q != '0)
				|| (valid_q && out_ready_i && depth_q > FIFO_DEPTH_WIDTH'(1))
				|| (Pass && !valid_q && depth_q == '0
					&& in_valid_i && !out_ready_i)) begin
				valid_q <= 1'b1;
			end else if (valid_q && out_ready_i) begin
				valid_q <= 1'b0;
			end
		end
	end else begin : block_fifo
		localparam int unsigned FIFO_POINTER_WIDTH = (Depth == 1) ? 1 : $clog2(Depth);

		(* ram_style = "block" *) logic [Width-1:0] memory [0:Depth-1];
		logic [FIFO_POINTER_WIDTH-1:0] write_pointer_q;
		logic [FIFO_POINTER_WIDTH-1:0] read_pointer_q;
		logic [FIFO_DEPTH_WIDTH-1:0] depth_q;
		logic [Width-1:0] data_q;
		logic valid_q;

		assign in_ready_o = depth_q < FIFO_DEPTH_WIDTH'(Depth)
			|| (valid_q && out_ready_i);
		assign out_data_o = (Pass && !valid_q && depth_q == '0) ? in_data_i : data_q;
		assign out_valid_o = valid_q
			|| (Pass && !valid_q && depth_q == '0 && in_valid_i);
		assign depth_o = depth_q;

		always_ff @(posedge clk_i) begin
			if (in_valid_i && in_ready_o
				&& !(Pass && !valid_q && depth_q == '0)) begin
				memory[write_pointer_q] <= in_data_i;
			end

			if ((!valid_q && depth_q != '0)
				|| (valid_q && out_ready_i && depth_q > FIFO_DEPTH_WIDTH'(1))) begin
				data_q <= memory[read_pointer_q];
			end else if (Pass && !valid_q && depth_q == '0
				&& in_valid_i && !out_ready_i) begin
				data_q <= in_data_i;
			end
		end

		always_ff @(posedge clk_i or negedge rst_ni) begin
			if (~rst_ni) begin
				write_pointer_q <= '0;
			end else if (clear_i) begin
				write_pointer_q <= '0;
			end else if (in_valid_i && in_ready_o
				&& !(Pass && !valid_q && depth_q == '0)) begin
				if (write_pointer_q == FIFO_POINTER_WIDTH'(Depth - 1)) begin
					write_pointer_q <= '0;
				end else begin
					write_pointer_q <= write_pointer_q + 1'b1;
				end
			end
		end

		always_ff @(posedge clk_i or negedge rst_ni) begin
			if (~rst_ni) begin
				read_pointer_q <= '0;
			end else if (clear_i) begin
				read_pointer_q <= '0;
			end else if ((!valid_q && depth_q != '0)
				|| (valid_q && out_ready_i && depth_q > FIFO_DEPTH_WIDTH'(1))) begin
				if (read_pointer_q == FIFO_POINTER_WIDTH'(Depth - 1)) begin
					read_pointer_q <= '0;
				end else begin
					read_pointer_q <= read_pointer_q + 1'b1;
				end
			end
		end

		always_ff @(posedge clk_i or negedge rst_ni) begin
			if (~rst_ni) begin
				depth_q <= '0;
			end else if (clear_i) begin
				depth_q <= '0;
			end else begin
				unique case ({
					(in_valid_i && in_ready_o
						&& !(Pass && !valid_q && depth_q == '0))
					|| (Pass && !valid_q && depth_q == '0
						&& in_valid_i && !out_ready_i),
					valid_q && out_ready_i
				})
					2'b10: depth_q <= depth_q + 1'b1;
					2'b01: depth_q <= depth_q - 1'b1;
					default: begin
					end
				endcase
			end
		end

		always_ff @(posedge clk_i or negedge rst_ni) begin
			if (~rst_ni) begin
				valid_q <= 1'b0;
			end else if (clear_i) begin
				valid_q <= 1'b0;
			end else if ((!valid_q && depth_q != '0)
				|| (valid_q && out_ready_i && depth_q > FIFO_DEPTH_WIDTH'(1))
				|| (Pass && !valid_q && depth_q == '0
					&& in_valid_i && !out_ready_i)) begin
				valid_q <= 1'b1;
			end else if (valid_q && out_ready_i) begin
				valid_q <= 1'b0;
			end
		end
	end

endmodule
