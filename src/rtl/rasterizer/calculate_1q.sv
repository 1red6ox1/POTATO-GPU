module calculate_1q
import rasterizer_pkg::*;
#(
	parameter int unsigned DIVIDERS = 4,
	parameter int unsigned FIFO_DEPTH = 8
) (
	input logic clk_i,
	input logic rst_ni,

	input rasterization_param_t                        param_i,
	input logic [$clog2(FRAME_WIDTH / TILE_WIDTH)-1:0] tile_x_i,
	input logic [$clog2(FRAME_HEIGHT)-1:0]             y_i,
	input logic                                        in_valid_i,
	output logic                                       in_ready_o,

	output logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] one_q_o,
	output logic                                   out_valid_o,
	input logic                                    out_ready_i
);

	localparam int unsigned ANCHOR_COUNT =
		(DIVIDERS == TILE_WIDTH) ? TILE_WIDTH : DIVIDERS + 1;
	localparam int unsigned INTERVAL = TILE_WIDTH / DIVIDERS;

	logic signed [COORD_WIDTH-1:0] x_i;
	logic signed [63:0] q_row;
	logic signed [UVQ_WIDTH-1:0] q_anchor [ANCHOR_COUNT-1:0];
	logic signed [UVQ_WIDTH-1:0] q_anchor_q [ANCHOR_COUNT-1:0];
	logic anchor_valid_q;
	logic anchor_ready;
	logic signed [UVQ_WIDTH-1:0] reciprocal [ANCHOR_COUNT-1:0];
	logic [ANCHOR_COUNT-1:0] reciprocal_in_ready;
	logic [ANCHOR_COUNT-1:0] reciprocal_valid;
	logic reciprocal_out_ready;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] one_q_i;
	logic fifo_in_ready;
	logic in_fire;
	logic out_fire;
	logic [$clog2(FIFO_DEPTH + 1)-1:0] reserved_q;

	assign x_i = $signed(COORD_WIDTH'(tile_x_i) << $clog2(TILE_WIDTH));
	assign q_row = 64'($signed(param_i.q))
	             + $signed(param_i.dq_dx) * x_i
	             + $signed(param_i.dq_dy) * $signed(COORD_WIDTH'(y_i));

	assign in_fire = in_valid_i && in_ready_o;
	assign out_fire = out_valid_o && out_ready_i;
	assign anchor_ready = !anchor_valid_q || &reciprocal_in_ready;
	assign in_ready_o = anchor_ready
	                 && (reserved_q < $clog2(FIFO_DEPTH + 1)'(FIFO_DEPTH) || out_fire);
	assign reciprocal_out_ready = &reciprocal_valid && fifo_in_ready;

	always_comb begin
		for (int anchor = 0; anchor < ANCHOR_COUNT; anchor++) begin
			q_anchor[anchor] = UVQ_WIDTH'(
				q_row + $signed(param_i.dq_dx)
				* $signed(COORD_WIDTH'(anchor * INTERVAL))
			);
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			anchor_valid_q <= 1'b0;
		end else if (anchor_ready) begin
			anchor_valid_q <= in_fire;
			if (in_fire) begin
				for (int anchor = 0; anchor < ANCHOR_COUNT; anchor++) begin
					q_anchor_q[anchor] <= q_anchor[anchor];
				end
			end
		end
	end

	if (DIVIDERS == TILE_WIDTH) begin : gen_every_pixel
		always_comb begin
			for (int pixel = 0; pixel < TILE_WIDTH; pixel++) begin
				one_q_i[pixel] = reciprocal[pixel];
			end
		end
	end else begin : gen_interpolate
		always_comb begin
			for (int pixel = 0; pixel < TILE_WIDTH; pixel++) begin
				int unsigned segment;
				int unsigned offset;
				logic signed [UVQ_WIDTH:0] difference;
				logic signed [UVQ_WIDTH+$clog2(TILE_WIDTH):0] interpolation;

				segment = pixel / INTERVAL;
				offset = pixel % INTERVAL;
				difference = $signed(reciprocal[segment + 1])
				           - $signed(reciprocal[segment]);
				interpolation = difference
				              * $signed($clog2(TILE_WIDTH)'(offset));
				one_q_i[pixel] = UVQ_WIDTH'(
					$signed(reciprocal[segment])
					+ (interpolation >>> $clog2(INTERVAL))
				);
			end
		end
	end

	for (genvar anchor = 0; anchor < ANCHOR_COUNT; anchor++) begin : gen_divider
		perspective_reciprocal perspective_reciprocal_i (
			.clk_i,
			.rst_ni,
			.q_i          (q_anchor_q[anchor]),
			.in_valid_i   (anchor_valid_q),
			.in_ready_o   (reciprocal_in_ready[anchor]),
			.reciprocal_o (reciprocal[anchor]),
			.out_valid_o  (reciprocal_valid[anchor]),
			.out_ready_i  (reciprocal_out_ready)
		);
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			reserved_q <= '0;
		end else begin
			unique case ({in_fire, out_fire})
				2'b10: reserved_q <= reserved_q + 1'b1;
				2'b01: reserved_q <= reserved_q - 1'b1;
				default: ;
			endcase
		end
	end

	my_fifo #(
		.Width (TILE_WIDTH * UVQ_WIDTH),
		.Pass  (1'b0),
		.Depth (FIFO_DEPTH)
	) one_q_fifo_i (
		.clk_i,
		.rst_ni,
		.clear_i      (1'b0),
		.in_data_i    (one_q_i),
		.in_valid_i   (&reciprocal_valid),
		.in_ready_o   (fifo_in_ready),
		.out_data_o   (one_q_o),
		.out_valid_o,
		.out_ready_i,
		.depth_o      ()
	);

endmodule
