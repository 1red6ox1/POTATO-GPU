module triangle2d_input
import triangle2d_input_reg_pkg::*;
import rasterizer_pkg::*;
(
	input logic clk_i,
	input logic rst_ni,

	input  tlul_pkg::tl_h2d_t tl_i,
	output tlul_pkg::tl_d2h_t tl_o,

	output triangle2d_t triangle2d_o,
	input  logic                        out_ready_i,
	output logic                        out_valid_o
);

	triangle2d_input_reg2hw_t reg2hw;
	triangle2d_input_hw2reg_t hw2reg;

	triangle2d_input_reg_top reg_top_i (
		.clk_i,
		.rst_ni,
		.tl_i,
		.tl_o,
		.reg2hw,
		.hw2reg,
		.devmode_i('1)
	);

	triangle2d_t triangle2d_q;
	assign triangle2d_o = triangle2d_q;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			out_valid_o  <= 1'b0;
			triangle2d_q <= '0;
		end else begin
			if (reg2hw.submit.qe && reg2hw.submit.q) begin
				triangle2d_q <= '{
					fbid_color: reg2hw.fbid_color.q,
					fbid_depth: reg2hw.fbid_depth.q,
					ax: reg2hw.ax.q,
					ay: reg2hw.ay.q,
					az: reg2hw.az.q,
					auq: reg2hw.auq.q,
					avq: reg2hw.avq.q,
					aq: reg2hw.aq.q,

					bx: reg2hw.bx.q,
					by: reg2hw.by.q,
					bz: reg2hw.bz.q,
					buq: reg2hw.buq.q,
					bvq: reg2hw.bvq.q,
					bq: reg2hw.bq.q,

					cx: reg2hw.cx.q,
					cy: reg2hw.cy.q,
					cz: reg2hw.cz.q,
					cuq: reg2hw.cuq.q,
					cvq: reg2hw.cvq.q,
					cq: reg2hw.cq.q
					
				};

				out_valid_o <= 1'b1;

			end else if (out_ready_i && out_valid_o) begin
				out_valid_o <= 1'b0;
			end
		end
	end

	assign hw2reg.status.d  = out_valid_o;
	assign hw2reg.status.de = 1'b1;

endmodule
