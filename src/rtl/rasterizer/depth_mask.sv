module depth_mask #(
	parameter int unsigned Depth = 4
) (
	input logic clk_i,
	input logic rst_ni,

	input  logic [rasterizer_pkg::TILE_WIDTH-1:0][rasterizer_pkg::DEPTH_WIDTH-1:0] z_i,
	input  logic z_valid_i,
	output logic z_ready_o,

	input  logic [255:0] depth1_i,
	input  logic depth1_valid_i,
	output logic depth1_ready_o,

	input  logic [255:0] depth2_i,
	input  logic depth2_valid_i,
	output logic depth2_ready_o,

	output logic [rasterizer_pkg::TILE_WIDTH-1:0][rasterizer_pkg::DEPTH_WIDTH-1:0] z_o,
	output logic [rasterizer_pkg::TILE_WIDTH-1:0] mask_o,
	output logic out_valid_o,
	input  logic out_ready_i
);

	import rasterizer_pkg::*;

	logic [TILE_WIDTH-1:0] mask_i;
	logic fifo_in_ready;

	typedef struct packed {
		logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] z;
		logic [TILE_WIDTH-1:0] mask;
	} depth_t;

	depth_t depth_i;
	depth_t depth_o;

	assign z_ready_o = depth1_valid_i && depth2_valid_i && fifo_in_ready;
	assign depth1_ready_o = z_valid_i && depth2_valid_i && fifo_in_ready;
	assign depth2_ready_o = z_valid_i && depth1_valid_i && fifo_in_ready;
	assign z_o = depth_o.z;
	assign mask_o = depth_o.mask;

	always_comb begin
		mask_i = '0;

		for (int x = 0; x < TILE_WIDTH; x++) begin
			if (x < TILE_WIDTH / 2) begin
				mask_i[x] = z_i[x] > depth1_i[DEPTH_WIDTH * x +: DEPTH_WIDTH];
			end else begin
				mask_i[x] = z_i[x] > depth2_i[DEPTH_WIDTH * (x - TILE_WIDTH / 2) +: DEPTH_WIDTH];
			end
		end

		depth_i = '{
			z:    z_i,
			mask: mask_i
		};
	end

	my_fifo #(
		.Width ($bits(depth_t)),
		.Pass  (1'b0),
		.Depth (Depth)
	) depth_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i     (1'b0),
		.in_data_i   (depth_i),
		.in_valid_i  (z_valid_i && depth1_valid_i && depth2_valid_i && fifo_in_ready),
		.in_ready_o  (fifo_in_ready),
		.out_data_o  (depth_o),
		.out_valid_o,
		.out_ready_i,
		.depth_o     ()
	);

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (z_valid_i && depth1_valid_i && depth2_valid_i && z_ready_o) begin
			$display("depth_mask,%0t,input,z,%h,depth1,%h,depth2,%h",
				$time, z_i, depth1_i, depth2_i);
		end

		if (out_valid_o && out_ready_i) begin
			$display("depth_mask,%0t,output,z,%h,mask,%h", $time, z_o, mask_o);
		end
	end
`endif

endmodule
