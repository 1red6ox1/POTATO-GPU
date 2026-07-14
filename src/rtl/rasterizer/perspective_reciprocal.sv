module perspective_reciprocal
import rasterizer_pkg::*;
(
	input logic clk_i,
	input logic rst_ni,

	input logic signed [UVQ_WIDTH-1:0] q_i,
	input logic                        in_valid_i,
	output logic                        in_ready_o,

	output logic signed [UVQ_WIDTH-1:0] reciprocal_o,
	output logic                        out_valid_o,
	input logic                         out_ready_i
);

	logic [5:0] msb;
	logic [UVQ_WIDTH-1:0] d_norm;
	logic [UVQ_WIDTH-1:0] y_seed;

	logic [4:0] valid_q;
	logic pipe_ready;
	logic [UVQ_WIDTH-1:0] d_input_q;
	logic [UVQ_WIDTH-1:0] y_input_q;
	logic [5:0] msb_input_q;
	logic invalid_input_q;

	logic [2*UVQ_WIDTH-1:0] product0_q;
	logic [UVQ_WIDTH-1:0] d0_q;
	logic [UVQ_WIDTH-1:0] y0_q;
	logic [5:0] msb0_q;
	logic invalid0_q;

	logic [2*UVQ_WIDTH-1:0] product1_q;
	logic [UVQ_WIDTH-1:0] d1_q;
	logic [5:0] msb1_q;
	logic invalid1_q;

	logic [2*UVQ_WIDTH-1:0] product2_q;
	logic [UVQ_WIDTH-1:0] y1_q;
	logic [5:0] msb2_q;
	logic invalid2_q;

	logic [2*UVQ_WIDTH-1:0] product3_q;
	logic [5:0] msb3_q;
	logic invalid3_q;

	logic [UVQ_WIDTH:0] correction0;
	logic [UVQ_WIDTH:0] correction1;
	logic [UVQ_WIDTH-1:0] refined_y0;
	logic [UVQ_WIDTH-1:0] refined_y1;
	logic [2*UVQ_WIDTH-1:0] reciprocal_wide;
	logic signed [UVQ_WIDTH-1:0] reciprocal_q;

	assign pipe_ready = out_ready_i || !valid_q[4];
	assign in_ready_o = pipe_ready;
	assign out_valid_o = valid_q[4];
	assign reciprocal_o = reciprocal_q;

	assign correction0 = 33'h1_0000_0000 - product0_q[63:31];
	assign refined_y0 = product1_q[62:31];
	assign correction1 = 33'h1_0000_0000 - product2_q[63:31];
	assign refined_y1 = product3_q[62:31];

	always_comb begin
		priority case (1'b1)
			q_i[30]: msb = 6'd30;
			q_i[29]: msb = 6'd29;
			q_i[28]: msb = 6'd28;
			q_i[27]: msb = 6'd27;
			q_i[26]: msb = 6'd26;
			q_i[25]: msb = 6'd25;
			q_i[24]: msb = 6'd24;
			q_i[23]: msb = 6'd23;
			q_i[22]: msb = 6'd22;
			q_i[21]: msb = 6'd21;
			q_i[20]: msb = 6'd20;
			q_i[19]: msb = 6'd19;
			q_i[18]: msb = 6'd18;
			q_i[17]: msb = 6'd17;
			q_i[16]: msb = 6'd16;
			q_i[15]: msb = 6'd15;
			q_i[14]: msb = 6'd14;
			q_i[13]: msb = 6'd13;
			q_i[12]: msb = 6'd12;
			q_i[11]: msb = 6'd11;
			q_i[10]: msb = 6'd10;
			q_i[9] : msb = 6'd9;
			q_i[8] : msb = 6'd8;
			q_i[7] : msb = 6'd7;
			q_i[6] : msb = 6'd6;
			q_i[5] : msb = 6'd5;
			q_i[4] : msb = 6'd4;
			q_i[3] : msb = 6'd3;
			q_i[2] : msb = 6'd2;
			q_i[1] : msb = 6'd1;
			default: msb = 6'd0;
		endcase
	end

	assign d_norm = $unsigned(q_i) << (6'd31 - msb);

	always_comb begin
		unique case (d_norm[30:27])
			4'h0: y_seed = 32'd2082408386;
			4'h1: y_seed = 32'd1963413621;
			4'h2: y_seed = 32'd1857283155;
			4'h3: y_seed = 32'd1762037865;
			4'h4: y_seed = 32'd1676084798;
			4'h5: y_seed = 32'd1598127366;
			4'h6: y_seed = 32'd1527099483;
			4'h7: y_seed = 32'd1462116526;
			4'h8: y_seed = 32'd1402438301;
			4'h9: y_seed = 32'd1347440720;
			4'ha: y_seed = 32'd1296593901;
			4'hb: y_seed = 32'd1249445032;
			4'hc: y_seed = 32'd1205604855;
			4'hd: y_seed = 32'd1164736894;
			4'he: y_seed = 32'd1126548799;
			4'hf: y_seed = 32'd1090785345;
			default: y_seed = '0;
		endcase
	end

	always_comb begin
		reciprocal_wide = '0;
		if (!invalid3_q) begin
			if (msb3_q <= 17) begin
				reciprocal_wide = {32'd0, refined_y1} << (6'd17 - msb3_q);
			end else begin
				reciprocal_wide = {32'd0, refined_y1} >> (msb3_q - 6'd17);
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
			valid_q <= {valid_q[3:0], in_valid_i};
		end
	end

	always_ff @(posedge clk_i) begin
		if (pipe_ready) begin
			d_input_q <= d_norm;
			y_input_q <= y_seed;
			msb_input_q <= msb;
			invalid_input_q <= q_i <= 0;

			product0_q <= d_input_q * y_input_q;
			d0_q <= d_input_q;
			y0_q <= y_input_q;
			msb0_q <= msb_input_q;
			invalid0_q <= invalid_input_q;

			product1_q <= y0_q * correction0;
			d1_q <= d0_q;
			msb1_q <= msb0_q;
			invalid1_q <= invalid0_q;

			product2_q <= d1_q * refined_y0;
			y1_q <= refined_y0;
			msb2_q <= msb1_q;
			invalid2_q <= invalid1_q;

			product3_q <= y1_q * correction1;
			msb3_q <= msb2_q;
			invalid3_q <= invalid2_q;
		end
	end

endmodule
