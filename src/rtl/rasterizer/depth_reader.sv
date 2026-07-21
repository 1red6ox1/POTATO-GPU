module depth_reader #(
	parameter bit          Pass  = 1'b0,
	parameter int unsigned Depth = 8,
	parameter logic        Half  = 1'b0
) (
	input logic clk_i,
	input logic rst_ni,

	input  logic [1:0] fbid_i,
	input  logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x_i,
	input  logic [rasterizer_pkg::FRAME_Y_WIDTH-1:0] y_i,
	input  logic [rasterizer_pkg::TILE_WIDTH / 2 - 1:0] mask_i,
	input  logic                                    in_valid_i,
	output logic                                    in_ready_o,

	output logic [255:0] out_data_o,
	output logic         out_valid_o,
	input  logic         out_ready_i,

	output rvlab_ddr_pkg::ddr3_h2d_t ddr_o,
	input  rvlab_ddr_pkg::ddr3_d2h_t ddr_i
);

	import rasterizer_pkg::*;
	import rvlab_ddr_pkg::*;
	import tlul_pkg::*;

	localparam int unsigned TOKEN_POINTER_WIDTH = (Depth == 1) ? 1 : $clog2(Depth);

	logic [TILE_X_WIDTH-1:0] tile_x_q;
	logic [FRAME_Y_WIDTH-1:0] y_q;
	logic [1:0] fbid_q;
	logic ddr_valid_q;
	logic fifo_in_ready;
	logic mask_empty;
	logic ddr_data_valid;
	logic [255:0] response_data;
	logic response_valid;
	logic response_ready;
	logic [Depth-1:0] zero_q;
	logic [TOKEN_POINTER_WIDTH-1:0] write_pointer_q;
	logic [TOKEN_POINTER_WIDTH-1:0] read_pointer_q;
	logic token_valid;
	logic token_zero;
	logic in_fire;
	logic out_fire;
	logic [$clog2(Depth + 1)-1:0] request_count_q;

	assign mask_empty = ~|mask_i;
	assign ddr_data_valid = ddr_i.d_valid && ddr_i.d_opcode == AccessAckData;
	assign token_valid = request_count_q != '0;
	assign token_zero = zero_q[read_pointer_q];
	assign in_fire = in_valid_i && in_ready_o;
	assign out_fire = out_valid_o && out_ready_i;
	assign in_ready_o = (mask_empty || !ddr_valid_q || ddr_i.a_ready)
		&& request_count_q < $clog2(Depth + 1)'(Depth);
	assign out_data_o = token_zero ? '0 : response_data;
	assign out_valid_o = token_valid && (token_zero || response_valid);
	assign response_ready = token_valid && !token_zero && out_ready_i;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			fbid_q      <= '0;
			tile_x_q    <= '0;
			y_q         <= '0;
			ddr_valid_q <= 1'b0;
		end else begin
			if (ddr_valid_q && ddr_i.a_ready) begin
				ddr_valid_q <= 1'b0;
			end

			if (in_fire && !mask_empty) begin
				fbid_q      <= fbid_i;
				tile_x_q    <= tile_x_i;
				y_q         <= y_i;
				ddr_valid_q <= 1'b1;
			end
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			request_count_q <= '0;
		end else begin
			unique case ({in_fire, out_fire})
				2'b10: request_count_q <= request_count_q + 1'b1;
				2'b01: request_count_q <= request_count_q - 1'b1;
				default: begin
				end
			endcase
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			zero_q          <= '0;
			write_pointer_q <= '0;
			read_pointer_q  <= '0;
		end else begin
			if (in_fire) begin
				zero_q[write_pointer_q] <= mask_empty;
				if (write_pointer_q == TOKEN_POINTER_WIDTH'(Depth - 1)) begin
					write_pointer_q <= '0;
				end else begin
					write_pointer_q <= write_pointer_q + 1'b1;
				end
			end

			if (out_fire) begin
				if (read_pointer_q == TOKEN_POINTER_WIDTH'(Depth - 1)) begin
					read_pointer_q <= '0;
				end else begin
					read_pointer_q <= read_pointer_q + 1'b1;
				end
			end
		end
	end

	my_fifo #(
		.Width (256),
		.Pass  (Pass),
		.Depth (Depth)
	) depth_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i     (1'b0),
		.in_data_i   (ddr_i.d_data),
		.in_valid_i  (ddr_data_valid),
		.in_ready_o  (fifo_in_ready),
		.out_data_o  (response_data),
		.out_valid_o (response_valid),
		.out_ready_i (response_ready),
		.depth_o     ()
	);

	always_comb begin
		ddr_o = '0;
		ddr_o.a_valid   = ddr_valid_q;
		ddr_o.a_opcode  = Get;
		ddr_o.a_address = {4'h2, fbid_q, 11'(y_q), 7'({tile_x_q, Half})};
		ddr_o.a_mask    = '1;
		ddr_o.d_ready   = fifo_in_ready;
	end

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			$display("depth_reader,%0t,input,tile_x,%0d,y,%0d,mask,%h",
				$time, tile_x_i, y_i, mask_i);
		end

		if (out_valid_o && out_ready_i) begin
			$display("depth_reader,%0t,output,data,%h", $time, out_data_o);
		end
	end
`endif

endmodule
