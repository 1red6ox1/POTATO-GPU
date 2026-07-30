module perspective_reciprocal (
	input logic clk_i,
	input logic rst_ni,

	input  logic signed [rasterizer_pkg::UVQ_WIDTH-1:0] q_i,
	input  logic in_valid_i,
	output logic in_ready_o,

	output logic signed [rasterizer_pkg::UVQ_WIDTH-1:0] reciprocal_o,
	output logic out_valid_o,
	input  logic out_ready_i
);

	import rasterizer_pkg::*;

	logic [5:0] msb;
	logic [UVQ_WIDTH-1:0] d_norm;
	logic [3:0] valid_q;
	logic pipe_ready;

	logic [UVQ_WIDTH-1:0] d_input_q;
	logic [5:0] msb_input_q;
	logic invalid_input_q;

	function automatic logic [2 * UVQ_WIDTH-1:0] make_seed(input int unsigned index);
		logic [63:0] denominator;
		logic [63:0] denominator_squared;
		logic [63:0] base;
		logic [63:0] slope;

		denominator         = 64'(513 + 2 * index);
		denominator_squared = denominator * denominator;
		base  = (64'd1099511627776 + (denominator >> 1)) / denominator;
		slope = (64'd562949953421312 + (denominator_squared >> 1)) / denominator_squared;

		make_seed = {base[UVQ_WIDTH-1:0], slope[UVQ_WIDTH-1:0]};
	endfunction

	(* ram_style = "block" *) logic [2 * UVQ_WIDTH-1:0] seed_lut [0:255];
	logic [UVQ_WIDTH-1:0] seed_base_q;
	logic [UVQ_WIDTH-1:0] seed_slope_q;
	logic [UVQ_WIDTH-1:0] d0_q;
	logic [5:0] msb0_q;
	logic invalid0_q;

	logic signed [UVQ_WIDTH:0] seed_delta;
	logic signed [2 * UVQ_WIDTH-1:0] seed_product;
	logic [UVQ_WIDTH-1:0] y_seed;
	logic [2 * UVQ_WIDTH-1:0] product0_q;
	logic [UVQ_WIDTH-1:0] y0_q;
	logic [5:0] msb1_q;
	logic invalid1_q;

	logic [UVQ_WIDTH:0] correction;
	logic [2 * UVQ_WIDTH-1:0] product1_q;
	logic [5:0] msb2_q;
	logic invalid2_q;

	logic [2 * UVQ_WIDTH-1:0] reciprocal_wide;
	logic [UVQ_WIDTH:0] reciprocal_normalized;
	logic [5:0] reciprocal_scale_shift;
	logic signed [UVQ_WIDTH-1:0] reciprocal_q;

	initial begin
		for (int unsigned seed = 0; seed < 256; seed++) begin
			seed_lut[seed] = make_seed(seed);
		end
	end

	assign pipe_ready = out_ready_i || !valid_q[3];
	assign in_ready_o = pipe_ready;
	assign out_valid_o = valid_q[3];
	assign reciprocal_o = reciprocal_q;

	always_comb begin
		msb = '0;

		for (int i = 1; i < UVQ_WIDTH - 1; i++) begin
			if (q_i[i]) begin
				msb = 6'(i);
			end
		end
	end

	assign d_norm = $unsigned(q_i) << (6'd31 - msb);
	assign seed_delta = $signed(33'({1'b0, d0_q[22:0]})) - 33'sh00_400000;
	assign seed_product = $signed({1'b0, seed_slope_q}) * seed_delta;
	assign y_seed = seed_base_q - UVQ_WIDTH'(seed_product >>> 31);
	assign correction = 33'h1_0000_0000 - product0_q[63:31];

	always_comb begin
		reciprocal_wide = '0;
		reciprocal_normalized = {1'b0, product1_q[62:31]};
		reciprocal_scale_shift = '0;

		if (!invalid2_q) begin
			if (msb2_q <= 17) begin
				reciprocal_normalized = reciprocal_normalized + product1_q[30];
				reciprocal_wide = {31'd0, reciprocal_normalized}
					<< (6'd17 - msb2_q);
			end else begin
				reciprocal_scale_shift = msb2_q - 6'd17;
				reciprocal_normalized = reciprocal_normalized
					+ (33'(1) << (reciprocal_scale_shift - 1'b1));
				reciprocal_wide = {31'd0, reciprocal_normalized}
					>> reciprocal_scale_shift;
			end
		end

		if (reciprocal_wide > 64'h0000_0000_7fff_ffff) begin
			reciprocal_q = 32'sh7fff_ffff;
		end else begin
			reciprocal_q = $signed(reciprocal_wide[31:0]);
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			valid_q <= '0;
		end else if (pipe_ready) begin
			valid_q <= {valid_q[2:0], in_valid_i};
		end
	end

	always_ff @(posedge clk_i) begin
		if (pipe_ready) begin
			d_input_q       <= d_norm;
			msb_input_q     <= msb;
			invalid_input_q <= q_i <= 0;

			{seed_base_q, seed_slope_q} <= seed_lut[d_input_q[30:23]];
			d0_q                        <= d_input_q;
			msb0_q                      <= msb_input_q;
			invalid0_q                  <= invalid_input_q;

			product0_q <= d0_q * y_seed;
			y0_q       <= y_seed;
			msb1_q     <= msb0_q;
			invalid1_q <= invalid0_q;

			product1_q <= y0_q * correction;
			msb2_q     <= msb1_q;
			invalid2_q <= invalid1_q;
		end
	end

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			$display("perspective_reciprocal,%0t,input,q,%h", $time, q_i);
		end

		if (out_valid_o && out_ready_i) begin
			$display("perspective_reciprocal,%0t,output,reciprocal,%h",
				$time, reciprocal_o);
		end
	end
`endif

endmodule
