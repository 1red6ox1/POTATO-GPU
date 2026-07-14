module uq_vq_calculation
import rasterizer_pkg::*;
#(
	parameter int unsigned FIFO_DEPTH = 8
) (
	input logic clk_i,
	input logic rst_ni,

	input rasterization_param_t                        param_i,
	input logic [$clog2(FRAME_WIDTH / TILE_WIDTH)-1:0] tile_x_i,
	input logic [$clog2(FRAME_HEIGHT)-1:0]             y_i,
	input logic                                        in_valid_i,
	output logic                                       in_ready_o,

	output logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] uq_o,
	output logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] vq_o,
	output logic                                   out_valid_o,
	input logic                                    out_ready_i
);

	logic signed [COORD_WIDTH-1:0] x_i;
	logic signed [63:0] uq_row;
	logic signed [63:0] vq_row;
	logic signed [UVQ_WIDTH-1:0] uq_row_q;
	logic signed [UVQ_WIDTH-1:0] vq_row_q;
	logic signed [UVQ_WIDTH-1:0] duq_dx_q;
	logic signed [UVQ_WIDTH-1:0] dvq_dx_q;
	logic row_valid_q;
	logic row_ready;
	logic row_fire;
	logic in_fire;
	(* use_dsp = "yes" *) logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] uq_i;
	(* use_dsp = "yes" *) logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] vq_i;
	logic uq_fifo_in_ready;
	logic vq_fifo_in_ready;
	logic uq_valid;
	logic vq_valid;

	assign x_i = $signed(COORD_WIDTH'(tile_x_i) << $clog2(TILE_WIDTH));
	assign row_ready = !row_valid_q || (uq_fifo_in_ready && vq_fifo_in_ready);
	assign in_ready_o = row_ready;
	assign in_fire = in_valid_i && in_ready_o;
	assign row_fire = row_valid_q && uq_fifo_in_ready && vq_fifo_in_ready;
	assign out_valid_o = uq_valid && vq_valid;

	always_comb begin
		uq_row = 64'($signed(param_i.uq))
		       + $signed(param_i.duq_dx) * x_i
		       + $signed(param_i.duq_dy) * $signed(COORD_WIDTH'(y_i));
		vq_row = 64'($signed(param_i.vq))
		       + $signed(param_i.dvq_dx) * x_i
		       + $signed(param_i.dvq_dy) * $signed(COORD_WIDTH'(y_i));

		for (int i = 0; i < TILE_WIDTH; i++) begin
			uq_i[i] = UVQ_WIDTH'(
				$signed(uq_row_q)
				+ $signed(duq_dx_q) * $signed(6'(i))
			);
			vq_i[i] = UVQ_WIDTH'(
				$signed(vq_row_q)
				+ $signed(dvq_dx_q) * $signed(6'(i))
			);
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			row_valid_q <= 1'b0;
		end else if (row_ready) begin
			row_valid_q <= in_fire;
			if (in_fire) begin
				uq_row_q <= UVQ_WIDTH'(uq_row);
				vq_row_q <= UVQ_WIDTH'(vq_row);
				duq_dx_q <= param_i.duq_dx;
				dvq_dx_q <= param_i.dvq_dx;
			end
		end
	end

	my_fifo #(
		.Width (TILE_WIDTH * UVQ_WIDTH),
		.Pass  (1'b0),
		.Depth (FIFO_DEPTH)
	) uq_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i      (1'b0),
		.in_data_i    (uq_i),
		.in_valid_i   (row_fire),
		.in_ready_o   (uq_fifo_in_ready),
		.out_data_o   (uq_o),
		.out_valid_o  (uq_valid),
		.out_ready_i  (out_ready_i && out_valid_o),
		.depth_o      ()
	);

	my_fifo #(
		.Width (TILE_WIDTH * UVQ_WIDTH),
		.Pass  (1'b0),
		.Depth (FIFO_DEPTH)
	) vq_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i      (1'b0),
		.in_data_i    (vq_i),
		.in_valid_i   (row_fire),
		.in_ready_o   (vq_fifo_in_ready),
		.out_data_o   (vq_o),
		.out_valid_o  (vq_valid),
		.out_ready_i  (out_ready_i && out_valid_o),
		.depth_o      ()
	);

endmodule
