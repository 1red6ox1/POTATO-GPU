// Copyright POTATO GPU Contributors 2026.

module matmul #(
	parameter int ID_WIDTH = 16
) (
	input  logic clk_i,
	input  logic rst_ni,

	input  tlul_pkg::tl_h2d_t tl_ctrl_i,
	output tlul_pkg::tl_d2h_t tl_ctrl_o,

	input  logic signed [31:0] data_i [3:0],
	output logic signed [31:0] data_o [3:0],

	input  logic                  valid_i,
	input  logic [ID_WIDTH-1:0]   id_i,
	output logic                  ready_o,

	output logic                  valid_o,
	output logic [ID_WIDTH-1:0]   id_o,
	input  logic                  ready_i
);

	import matmul_ctrl_reg_pkg::*;

	matmul_ctrl_reg2hw_t reg2hw;

	matmul_ctrl_reg_top reg_top_i (
		.clk_i,
		.rst_ni,
		.tl_i     (tl_ctrl_i),
		.tl_o     (tl_ctrl_o),
		.reg2hw   (reg2hw),
		.devmode_i('1)
	);

	logic signed [31:0] matrix      [3:0][3:0];
	logic signed [63:0] mult_result [3:0][3:0];
	logic [1:0] valid_shift;
	logic [ID_WIDTH-1:0] id_shift [1:0];

	assign ready_o = ready_i;
	assign valid_o = valid_shift[1];
	assign id_o = id_shift[1];

	// Row-major order
	assign matrix[0][0] = $signed(reg2hw.mat_0_0.q);
	assign matrix[0][1] = $signed(reg2hw.mat_0_1.q);
	assign matrix[0][2] = $signed(reg2hw.mat_0_2.q);
	assign matrix[0][3] = $signed(reg2hw.mat_0_3.q);
	assign matrix[1][0] = $signed(reg2hw.mat_1_0.q);
	assign matrix[1][1] = $signed(reg2hw.mat_1_1.q);
	assign matrix[1][2] = $signed(reg2hw.mat_1_2.q);
	assign matrix[1][3] = $signed(reg2hw.mat_1_3.q);
	assign matrix[2][0] = $signed(reg2hw.mat_2_0.q);
	assign matrix[2][1] = $signed(reg2hw.mat_2_1.q);
	assign matrix[2][2] = $signed(reg2hw.mat_2_2.q);
	assign matrix[2][3] = $signed(reg2hw.mat_2_3.q);
	assign matrix[3][0] = $signed(reg2hw.mat_3_0.q);
	assign matrix[3][1] = $signed(reg2hw.mat_3_1.q);
	assign matrix[3][2] = $signed(reg2hw.mat_3_2.q);
	assign matrix[3][3] = $signed(reg2hw.mat_3_3.q);

	always_ff @(posedge clk_i) begin
		if (~rst_ni) begin
			for (int i = 0; i < 4; i++) begin
				for (int j = 0; j < 4; j++) begin
					mult_result[i][j] <= '0;
				end
				data_o[i] <= '0;
			end
			valid_shift <= '0;
			for (int stage = 0; stage < 2; stage++) begin
				id_shift[stage] <= '0;
			end
		end else if (ready_i) begin
			valid_shift <= {valid_shift[0], valid_i};
			id_shift[0] <= id_i;
			id_shift[1] <= id_shift[0];

			for (int i = 0; i < 4; i++) begin
				for (int j = 0; j < 4; j++) begin
					mult_result[i][j] <= matrix[i][j] * data_i[j];
				end
				data_o[i] <= (mult_result[i][0][47:16] + mult_result[i][1][47:16])
				           + (mult_result[i][2][47:16] + mult_result[i][3][47:16]);
			end
		end
	end

endmodule
