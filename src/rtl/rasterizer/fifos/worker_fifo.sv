module worker_fifo
import rasterizer_pkg::*;
#(
	parameter int unsigned FIFO_DEPTH = 8
) (
	input logic clk_i,
	input logic rst_ni,
	input logic clear_i,

	input chunk_id_t chunk_id_i,
	input logic      in_valid_i,
	output logic      in_ready_o,

	input logic [TILE_WIDTH-1:0]                  mask_i,
	input logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] depth_i,
	input logic                                    mask_valid_i,
	output logic                                    mask_ready_o,

	input logic [255:0] red_i,
	input logic [255:0] green_i,
	input logic [255:0] blue_i,
	input logic         color_valid_i,
	output logic         color_ready_o,

	output logic [255:0] data_o,
	output logic [31:0]  write_mask_o,
	output logic [23:0]  address_o,
	output logic         out_valid_o,
	input logic          out_ready_i
);

	typedef enum logic [2:0] {
		DEPTH1 = 3'd0,
		DEPTH2 = 3'd1,
		RED    = 3'd2,
		GREEN  = 3'd3,
		BLUE   = 3'd4
	} part_e;

	chunk_id_t chunk_id_o;
	logic chunk_valid;
	logic chunk_ready;
	logic [4:0] required_part;
	logic [4:0] sent_part_q;
	logic [4:0] candidate_part_mask;
	part_e candidate_part;
	logic row_valid;
	logic row_done;
	logic out_fire;

	assign row_valid = chunk_valid && mask_valid_i && color_valid_i;
	assign required_part = {
		mask_i != '0,
		mask_i != '0,
		mask_i != '0,
		mask_i[TILE_WIDTH-1:TILE_WIDTH/2] != '0,
		mask_i[TILE_WIDTH/2-1:0] != '0
	};
	assign out_fire = out_valid_o && out_ready_i;
	assign row_done = row_valid
	               && (required_part == '0
	                   || (out_fire
	                       && (required_part & ~sent_part_q) == candidate_part_mask));
	assign chunk_ready = row_done;
	assign mask_ready_o = row_done;
	assign color_ready_o = row_done;

	always_comb begin
		candidate_part = DEPTH1;
		candidate_part_mask = '0;
		out_valid_o = 1'b0;
		data_o = '0;
		write_mask_o = '0;
		address_o = '0;

		if (row_valid) begin
			if (required_part[DEPTH1] && !sent_part_q[DEPTH1]) begin
				candidate_part = DEPTH1;
				candidate_part_mask[DEPTH1] = 1'b1;
				out_valid_o = 1'b1;
				for (int pixel = 0; pixel < TILE_WIDTH / 2; pixel++) begin
					data_o[DEPTH_WIDTH*pixel+:DEPTH_WIDTH] = depth_i[pixel];
					write_mask_o[2*pixel+:2] = {2{mask_i[pixel]}};
				end
				address_o = {4'h1, chunk_id_o.fbid_depth,
				             11'(chunk_id_o.y),
				             7'({chunk_id_o.tile_x, 1'b0})};
			end else if (required_part[DEPTH2] && !sent_part_q[DEPTH2]) begin
				candidate_part = DEPTH2;
				candidate_part_mask[DEPTH2] = 1'b1;
				out_valid_o = 1'b1;
				for (int pixel = 0; pixel < TILE_WIDTH / 2; pixel++) begin
					data_o[DEPTH_WIDTH*pixel+:DEPTH_WIDTH] =
						depth_i[pixel + TILE_WIDTH / 2];
					write_mask_o[2*pixel+:2] =
						{2{mask_i[pixel + TILE_WIDTH / 2]}};
				end
				address_o = {4'h1, chunk_id_o.fbid_depth,
				             11'(chunk_id_o.y),
				             7'({chunk_id_o.tile_x, 1'b1})};
			end else if (required_part[RED] && !sent_part_q[RED]) begin
				candidate_part = RED;
				candidate_part_mask[RED] = 1'b1;
				out_valid_o = 1'b1;
				data_o = red_i;
				write_mask_o = mask_i;
				address_o = {3'h0, chunk_id_o.fbid_color,
				             11'(chunk_id_o.y),
				             6'(chunk_id_o.tile_x), 2'b00};
			end else if (required_part[GREEN] && !sent_part_q[GREEN]) begin
				candidate_part = GREEN;
				candidate_part_mask[GREEN] = 1'b1;
				out_valid_o = 1'b1;
				data_o = green_i;
				write_mask_o = mask_i;
				address_o = {3'h0, chunk_id_o.fbid_color,
				             11'(chunk_id_o.y),
				             6'(chunk_id_o.tile_x), 2'b01};
			end else if (required_part[BLUE] && !sent_part_q[BLUE]) begin
				candidate_part = BLUE;
				candidate_part_mask[BLUE] = 1'b1;
				out_valid_o = 1'b1;
				data_o = blue_i;
				write_mask_o = mask_i;
				address_o = {3'h0, chunk_id_o.fbid_color,
				             11'(chunk_id_o.y),
				             6'(chunk_id_o.tile_x), 2'b10};
			end
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			sent_part_q <= '0;
		end else if (clear_i || row_done) begin
			sent_part_q <= '0;
		end else if (out_fire) begin
			sent_part_q[candidate_part] <= 1'b1;
		end
	end

	my_fifo #(
		.Width ($bits(chunk_id_t)),
		.Pass  (1'b0),
		.Depth (FIFO_DEPTH)
	) chunk_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i,
		.in_data_i    (chunk_id_i),
		.in_valid_i,
		.in_ready_o,
		.out_data_o   (chunk_id_o),
		.out_valid_o  (chunk_valid),
		.out_ready_i  (chunk_ready),
		.depth_o      ()
	);

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			$display("worker_fifo,%0t,allocate,tile,%0d,y,%0d",
				$time, chunk_id_i.tile_x, chunk_id_i.y);
		end
		if (out_fire) begin
			$display("worker_fifo,%0t,sent,tile,%0d,y,%0d,part,%0d",
				$time, chunk_id_o.tile_x, chunk_id_o.y, candidate_part);
		end
	end
`endif

endmodule
