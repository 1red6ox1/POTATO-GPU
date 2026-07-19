module depth_reader
import rasterizer_pkg::*;
#(
	parameter logic DEPTH_PART = 1'b0,
	parameter int unsigned FIFO_DEPTH = 8
) (
	input logic clk_i,
	input logic rst_ni,

	input logic [1:0]                                                                  fbid_depth_i,
	input logic [$clog2(rasterizer_pkg::FRAME_WIDTH / rasterizer_pkg::TILE_WIDTH)-1:0] tile_x_i,
	input logic [$clog2(rasterizer_pkg::FRAME_HEIGHT)-1:0]                             y_i,
	input logic                                                                        in_valid_i,
	output logic                                                                       in_ready_o,

	output logic [255:0] out_data_o,
	output logic         out_valid_o,
	input logic          out_ready_i,

	output rvlab_ddr_pkg::ddr3_h2d_t ddr_o,
	input rvlab_ddr_pkg::ddr3_d2h_t ddr_i
);

	import rvlab_ddr_pkg::*;
	import tlul_pkg::*;

	logic [1:0]                                  fbid_depth_q;
	logic [$clog2(FRAME_WIDTH / TILE_WIDTH)-1:0] tile_x_q;
	logic [$clog2(FRAME_HEIGHT)-1:0]             y_q;
	logic                                         request_valid_q;
	logic [$clog2(FIFO_DEPTH + 1)-1:0]           reserved_q;

	logic         fifo_in_valid;
	logic         fifo_in_ready;
	logic         in_fire;
	logic         out_fire;

	assign in_fire  = in_valid_i && in_ready_o;
	assign out_fire = out_valid_o && out_ready_i;

	assign in_ready_o = (!request_valid_q || ddr_i.a_ready)
	                 && (reserved_q < $clog2(FIFO_DEPTH + 1)'(FIFO_DEPTH) || out_fire);
	assign fifo_in_valid = ddr_i.d_valid && (ddr_i.d_opcode == AccessAckData);

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			fbid_depth_q    <= '0;
			tile_x_q        <= '0;
			y_q             <= '0;
			request_valid_q <= 1'b0;
			reserved_q      <= '0;
		end else begin
			if (request_valid_q && ddr_i.a_ready) begin
				request_valid_q <= 1'b0;
			end

			if (in_fire) begin
				fbid_depth_q    <= fbid_depth_i;
				tile_x_q        <= tile_x_i;
				y_q             <= y_i;
				request_valid_q <= 1'b1;
			end

			unique case ({in_fire, out_fire})
				2'b10: reserved_q <= reserved_q + 1'b1;
				2'b01: reserved_q <= reserved_q - 1'b1;
				default: ;
			endcase
		end
	end

	my_fifo #(
		.Width (256),
		.Pass  (1'b0),
		.Depth (FIFO_DEPTH)
	) depth_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i      (1'b0),
		.in_data_i    (ddr_i.d_data),
		.in_valid_i   (fifo_in_valid),
		.in_ready_o   (fifo_in_ready),
		.out_data_o,
		.out_valid_o,
		.out_ready_i,
		.depth_o      ()
	);

	assign ddr_o = '{
		a_valid:  request_valid_q,
		a_opcode: Get,
		a_address: {4'h1, fbid_depth_q, 11'(y_q), 7'({tile_x_q, DEPTH_PART})},
		a_mask:   '1,
		a_data:   '0,
		a_anc:    '0,
		d_ready:  fifo_in_ready
	};

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (ddr_o.a_valid && ddr_i.a_ready) begin
			$display("depth_reader,%0t,request,part,%0d,tile,%0d,y,%0d",
				$time, DEPTH_PART, tile_x_q, y_q);
		end

		if (fifo_in_valid && fifo_in_ready) begin
			$display("depth_reader,%0t,response,part,%0d,anc,%0d",
				$time, DEPTH_PART, ddr_i.d_anc);
		end
	end
`endif

endmodule
