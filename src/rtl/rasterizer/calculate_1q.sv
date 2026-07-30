module calculate_1q #(
	parameter int unsigned Depth = 4
) (
	input logic clk_i,
	input logic rst_ni,

	input  rasterizer_pkg::triangle_param_t param_i,
	input  logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x_i,
	input  logic [rasterizer_pkg::FRAME_Y_WIDTH-1:0] y_i,
	input  logic in_valid_i,
	output logic in_ready_o,

	output logic [rasterizer_pkg::TILE_WIDTH-1:0][rasterizer_pkg::UVQ_WIDTH-1:0] one_q_o,
	output logic out_valid_o,
	input  logic out_ready_i
);

	import rasterizer_pkg::*;

	logic signed [COORD_WIDTH-1:0] x_i;
	logic signed [63:0] q_row;
	logic signed [UVQ_WIDTH-1:0] q0_i;
	logic signed [UVQ_WIDTH-1:0] q1_i;
	logic signed [UVQ_WIDTH-1:0] q2_i;
	logic signed [UVQ_WIDTH-1:0] q3_i;
	logic signed [UVQ_WIDTH-1:0] q4_i;
	logic signed [UVQ_WIDTH-1:0] q0_q;
	logic signed [UVQ_WIDTH-1:0] q1_q;
	logic signed [UVQ_WIDTH-1:0] q2_q;
	logic signed [UVQ_WIDTH-1:0] q3_q;
	logic signed [UVQ_WIDTH-1:0] q4_q;
	logic q_valid_q;

	logic signed [UVQ_WIDTH-1:0] reciprocal0;
	logic signed [UVQ_WIDTH-1:0] reciprocal1;
	logic signed [UVQ_WIDTH-1:0] reciprocal2;
	logic signed [UVQ_WIDTH-1:0] reciprocal3;
	logic signed [UVQ_WIDTH-1:0] reciprocal4;
	logic reciprocal0_ready;
	logic reciprocal1_ready;
	logic reciprocal2_ready;
	logic reciprocal3_ready;
	logic reciprocal4_ready;
	logic reciprocal0_valid;
	logic reciprocal1_valid;
	logic reciprocal2_valid;
	logic reciprocal3_valid;
	logic reciprocal4_valid;
	logic reciprocal_out_ready;

	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] one_q_i;
	logic fifo_in_ready;

	assign x_i = COORD_WIDTH'(tile_x_i) << $clog2(TILE_WIDTH);
	assign q_row = 64'($signed(param_i.q))
		+ $signed(param_i.dq_dx) * x_i
		+ $signed(param_i.dq_dy) * $signed(COORD_WIDTH'(y_i));

	assign q0_i = UVQ_WIDTH'(q_row);
	assign q1_i = UVQ_WIDTH'(q_row + $signed(param_i.dq_dx) * 8);
	assign q2_i = UVQ_WIDTH'(q_row + $signed(param_i.dq_dx) * 16);
	assign q3_i = UVQ_WIDTH'(q_row + $signed(param_i.dq_dx) * 24);
	assign q4_i = UVQ_WIDTH'(q_row + $signed(param_i.dq_dx) * 32);

	assign in_ready_o = !q_valid_q || (reciprocal0_ready && reciprocal1_ready
		&& reciprocal2_ready && reciprocal3_ready && reciprocal4_ready);
	assign reciprocal_out_ready = fifo_in_ready && reciprocal0_valid && reciprocal1_valid && reciprocal2_valid && reciprocal3_valid	&& reciprocal4_valid;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			q0_q <= '0;
			q1_q <= '0;
			q2_q <= '0;
			q3_q <= '0;
			q4_q <= '0;
			q_valid_q <= 1'b0;
		end else if (in_ready_o) begin
			q_valid_q <= in_valid_i;
			if (in_valid_i) begin
				q0_q <= q0_i;
				q1_q <= q1_i;
				q2_q <= q2_i;
				q3_q <= q3_i;
				q4_q <= q4_i;
			end
		end
	end

	always_comb begin
		for (int pixel = 0; pixel < 8; pixel++) begin
			logic signed [UVQ_WIDTH:0] difference;
			logic signed [UVQ_WIDTH:0] step;
			logic signed [UVQ_WIDTH + $clog2(TILE_WIDTH):0] interpolation;

			difference = $signed(reciprocal1) - $signed(reciprocal0);
			step = difference >>> 3;
			interpolation = step * $signed(4'(pixel));
			one_q_i[pixel] = UVQ_WIDTH'($signed(reciprocal0) + interpolation);
		end

		for (int pixel = 0; pixel < 8; pixel++) begin
			logic signed [UVQ_WIDTH:0] difference;
			logic signed [UVQ_WIDTH:0] step;
			logic signed [UVQ_WIDTH + $clog2(TILE_WIDTH):0] interpolation;

			difference = $signed(reciprocal2) - $signed(reciprocal1);
			step = difference >>> 3;
			interpolation = step * $signed(4'(pixel));
			one_q_i[8 + pixel] = UVQ_WIDTH'($signed(reciprocal1) + interpolation);
		end

		for (int pixel = 0; pixel < 8; pixel++) begin
			logic signed [UVQ_WIDTH:0] difference;
			logic signed [UVQ_WIDTH:0] step;
			logic signed [UVQ_WIDTH + $clog2(TILE_WIDTH):0] interpolation;

			difference = $signed(reciprocal3) - $signed(reciprocal2);
			step = difference >>> 3;
			interpolation = step * $signed(4'(pixel));
			one_q_i[16 + pixel] = UVQ_WIDTH'($signed(reciprocal2) + interpolation);
		end

		for (int pixel = 0; pixel < 8; pixel++) begin
			logic signed [UVQ_WIDTH:0] difference;
			logic signed [UVQ_WIDTH:0] step;
			logic signed [UVQ_WIDTH + $clog2(TILE_WIDTH):0] interpolation;

			difference = $signed(reciprocal4) - $signed(reciprocal3);
			step = difference >>> 3;
			interpolation = step * $signed(4'(pixel));
			one_q_i[24 + pixel] = UVQ_WIDTH'($signed(reciprocal3) + interpolation);
		end
	end

	perspective_reciprocal reciprocal0_i (
		.clk_i,
		.rst_ni,
		.q_i          (q0_q),
		.in_valid_i   (q_valid_q && reciprocal0_ready && reciprocal1_ready
			&& reciprocal2_ready && reciprocal3_ready && reciprocal4_ready),
		.in_ready_o   (reciprocal0_ready),
		.reciprocal_o (reciprocal0),
		.out_valid_o  (reciprocal0_valid),
		.out_ready_i  (reciprocal_out_ready)
	);

	perspective_reciprocal reciprocal1_i (
		.clk_i,
		.rst_ni,
		.q_i          (q1_q),
		.in_valid_i   (q_valid_q && reciprocal0_ready && reciprocal1_ready
			&& reciprocal2_ready && reciprocal3_ready && reciprocal4_ready),
		.in_ready_o   (reciprocal1_ready),
		.reciprocal_o (reciprocal1),
		.out_valid_o  (reciprocal1_valid),
		.out_ready_i  (reciprocal_out_ready)
	);

	perspective_reciprocal reciprocal2_i (
		.clk_i,
		.rst_ni,
		.q_i          (q2_q),
		.in_valid_i   (q_valid_q && reciprocal0_ready && reciprocal1_ready
			&& reciprocal2_ready && reciprocal3_ready && reciprocal4_ready),
		.in_ready_o   (reciprocal2_ready),
		.reciprocal_o (reciprocal2),
		.out_valid_o  (reciprocal2_valid),
		.out_ready_i  (reciprocal_out_ready)
	);

	perspective_reciprocal reciprocal3_i (
		.clk_i,
		.rst_ni,
		.q_i          (q3_q),
		.in_valid_i   (q_valid_q && reciprocal0_ready && reciprocal1_ready
			&& reciprocal2_ready && reciprocal3_ready && reciprocal4_ready),
		.in_ready_o   (reciprocal3_ready),
		.reciprocal_o (reciprocal3),
		.out_valid_o  (reciprocal3_valid),
		.out_ready_i  (reciprocal_out_ready)
	);

	perspective_reciprocal reciprocal4_i (
		.clk_i,
		.rst_ni,
		.q_i          (q4_q),
		.in_valid_i   (q_valid_q && reciprocal0_ready && reciprocal1_ready
			&& reciprocal2_ready && reciprocal3_ready && reciprocal4_ready),
		.in_ready_o   (reciprocal4_ready),
		.reciprocal_o (reciprocal4),
		.out_valid_o  (reciprocal4_valid),
		.out_ready_i  (reciprocal_out_ready)
	);

	my_fifo #(
		.Width   (TILE_WIDTH * UVQ_WIDTH),
		.Pass    (1'b0),
		.Depth   (Depth),
		.UseBram (1'b1)
	) one_q_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i     (1'b0),
		.in_data_i   (one_q_i),
		.in_valid_i  (reciprocal0_valid && reciprocal1_valid && reciprocal2_valid && reciprocal3_valid && reciprocal4_valid),
		.in_ready_o  (fifo_in_ready),
		.out_data_o  (one_q_o),
		.out_valid_o,
		.out_ready_i,
		.depth_o     ()
	);

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			$display("calculate_1q,%0t,input,param,%h,tile_x,%0d,y,%0d",
				$time, param_i, tile_x_i, y_i);
		end

		if (out_valid_o && out_ready_i) begin
			$display("calculate_1q,%0t,output,one_q,%h", $time, one_q_o);
		end
	end
`endif

endmodule
