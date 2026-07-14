module triangle_area_reciprocal (
	input logic clk_i,
	input logic rst_ni,

	input  logic        in_valid_i,
	output logic        in_ready_o,
	input  logic [32:0] area_i,

	output logic        out_valid_o,
	input  logic        out_ready_i,
	output logic [17:0] mantissa_o,
	output logic [5:0]  shift_o
);

	typedef enum logic [1:0] {
		WAIT   = 2'b00,
		DIVIDE = 2'b01,
		OUTPUT = 2'b10
	} state_e;

	state_e state_q;

	logic [5:0]  msb;
	logic [5:0]  shift_q;
	logic [4:0]  bit_q;
	logic [18:0] quotient_q;
	logic [50:0] remainder_q;
	logic [50:0] divisor_q;

	assign in_ready_o  = state_q == WAIT;
	assign out_valid_o = state_q == OUTPUT;
	assign mantissa_o  = quotient_q[18] ? 18'd131072 : quotient_q[17:0];
	assign shift_o     = quotient_q[18] ? shift_q - 1'b1 : shift_q;

	always_comb begin
		priority case (1'b1)
			area_i[32]: msb = 6'd32;
			area_i[31]: msb = 6'd31;
			area_i[30]: msb = 6'd30;
			area_i[29]: msb = 6'd29;
			area_i[28]: msb = 6'd28;
			area_i[27]: msb = 6'd27;
			area_i[26]: msb = 6'd26;
			area_i[25]: msb = 6'd25;
			area_i[24]: msb = 6'd24;
			area_i[23]: msb = 6'd23;
			area_i[22]: msb = 6'd22;
			area_i[21]: msb = 6'd21;
			area_i[20]: msb = 6'd20;
			area_i[19]: msb = 6'd19;
			area_i[18]: msb = 6'd18;
			area_i[17]: msb = 6'd17;
			area_i[16]: msb = 6'd16;
			area_i[15]: msb = 6'd15;
			area_i[14]: msb = 6'd14;
			area_i[13]: msb = 6'd13;
			area_i[12]: msb = 6'd12;
			area_i[11]: msb = 6'd11;
			area_i[10]: msb = 6'd10;
			area_i[9] : msb = 6'd9;
			area_i[8] : msb = 6'd8;
			area_i[7] : msb = 6'd7;
			area_i[6] : msb = 6'd6;
			area_i[5] : msb = 6'd5;
			area_i[4] : msb = 6'd4;
			area_i[3] : msb = 6'd3;
			area_i[2] : msb = 6'd2;
			area_i[1] : msb = 6'd1;
			default   : msb = 6'd0;
		endcase
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			state_q     <= WAIT;
			shift_q     <= '0;
			bit_q       <= '0;
			quotient_q  <= '0;
			remainder_q <= '0;
			divisor_q   <= '0;
		end else begin
			unique case (state_q)
				WAIT: begin
					if (in_valid_i && in_ready_o) begin
						shift_q     <= msb + 6'd18;
						bit_q       <= 5'd18;
						quotient_q  <= '0;
						remainder_q <= 51'(1) << (msb + 6'd18);
						divisor_q   <= 51'(area_i) << 18;
						state_q     <= DIVIDE;
					end
				end

				DIVIDE: begin
					if (remainder_q >= divisor_q) begin
						remainder_q       <= remainder_q - divisor_q;
						quotient_q[bit_q] <= 1'b1;
					end

					if (bit_q == 0) begin
						state_q <= OUTPUT;
					end else begin
						bit_q     <= bit_q - 1'b1;
						divisor_q <= divisor_q >> 1;
					end
				end

				OUTPUT: begin
					if (out_valid_o && out_ready_i) begin
						state_q <= WAIT;
					end
				end

				default: state_q <= WAIT;
			endcase
		end
	end

`ifndef SYNTHESIS
	always_ff @(posedge clk_i) begin
		if (rst_ni && in_valid_i && in_ready_o) begin
			assert (area_i != 0)
				else $error("triangle_area_reciprocal received zero area");
		end
	end
`endif

endmodule
