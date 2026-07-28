module triangle_input (
	input logic clk_i,
	input logic rst_ni,

	input  tlul_pkg::tl_h2d_t tl_i,
	output tlul_pkg::tl_d2h_t tl_o,

	output logic [1:0]                fbid_color_o,
	output logic [1:0]                fbid_depth_o,
	output rasterizer_pkg::triangle_t triangle_o,
	output logic                      out_valid_o,
	input  logic                      out_ready_i
);

	import triangle_input_reg_pkg::*;

	triangle_input_reg2hw_t reg2hw;
	triangle_input_hw2reg_t hw2reg;

	triangle_input_reg_top reg_top_i (
		.clk_i,
		.rst_ni,
		.tl_i,
		.tl_o,
		.reg2hw,
		.hw2reg,
		.devmode_i(1'b1)
	);

	import rasterizer_pkg::*;
	triangle_t triangle_q;
	assign fbid_color_o = reg2hw.fbid_color.q;
	assign fbid_depth_o = reg2hw.fbid_depth.q;
	assign triangle_o = triangle_q;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			triangle_q  <= '0;
			out_valid_o <= 1'b0;
		end else begin
			if (reg2hw.submit.qe && reg2hw.submit.q && !out_valid_o) begin
				triangle_q <= '{
					triangle_id: TRIANGLE_ID_WIDTH'(reg2hw.triangle_id.q),
					fbid_color: reg2hw.fbid_color.q,
					fbid_depth: reg2hw.fbid_depth.q,
					ax: COORD_WIDTH'($signed(reg2hw.ax.q)),
					ay: COORD_WIDTH'($signed(reg2hw.ay.q)),
					az: reg2hw.az.q,
					auq: reg2hw.auq.q,
					avq: reg2hw.avq.q,
					aq: reg2hw.aq.q,
					bx: COORD_WIDTH'($signed(reg2hw.bx.q)),
					by: COORD_WIDTH'($signed(reg2hw.by.q)),
					bz: reg2hw.bz.q,
					buq: reg2hw.buq.q,
					bvq: reg2hw.bvq.q,
					bq: reg2hw.bq.q,
					cx: COORD_WIDTH'($signed(reg2hw.cx.q)),
					cy: COORD_WIDTH'($signed(reg2hw.cy.q)),
					cz: reg2hw.cz.q,
					cuq: reg2hw.cuq.q,
					cvq: reg2hw.cvq.q,
					cq: reg2hw.cq.q
				};
				out_valid_o <= 1'b1;
			end else if (out_valid_o && out_ready_i) begin
				out_valid_o <= 1'b0;
			end
		end
	end

	assign hw2reg.status.d  = out_valid_o;
	assign hw2reg.status.de = 1'b1;

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (reg2hw.submit.qe && reg2hw.submit.q && !out_valid_o) begin
			$display("triangle_input,%0t,input,triangle_id,%0d,fbid_color,%0d,fbid_depth,%0d,ax,%0d,ay,%0d,az,%0d,auq,%0d,avq,%0d,aq,%0d,bx,%0d,by,%0d,bz,%0d,buq,%0d,bvq,%0d,bq,%0d,cx,%0d,cy,%0d,cz,%0d,cuq,%0d,cvq,%0d,cq,%0d",
				$time,
				reg2hw.triangle_id.q,
				reg2hw.fbid_color.q, reg2hw.fbid_depth.q,
				$signed(reg2hw.ax.q), $signed(reg2hw.ay.q), reg2hw.az.q,
				$signed(reg2hw.auq.q), $signed(reg2hw.avq.q), $signed(reg2hw.aq.q),
				$signed(reg2hw.bx.q), $signed(reg2hw.by.q), reg2hw.bz.q,
				$signed(reg2hw.buq.q), $signed(reg2hw.bvq.q), $signed(reg2hw.bq.q),
				$signed(reg2hw.cx.q), $signed(reg2hw.cy.q), reg2hw.cz.q,
				$signed(reg2hw.cuq.q), $signed(reg2hw.cvq.q), $signed(reg2hw.cq.q));
		end

		if (out_valid_o && out_ready_i) begin
			$display("triangle_input,%0t,output,triangle_id,%0d,fbid_color,%0d,fbid_depth,%0d,ax,%0d,ay,%0d,az,%0d,auq,%0d,avq,%0d,aq,%0d,bx,%0d,by,%0d,bz,%0d,buq,%0d,bvq,%0d,bq,%0d,cx,%0d,cy,%0d,cz,%0d,cuq,%0d,cvq,%0d,cq,%0d",
				$time,
				triangle_q.triangle_id,
				triangle_q.fbid_color, triangle_q.fbid_depth,
				$signed(triangle_q.ax), $signed(triangle_q.ay), triangle_q.az,
				$signed(triangle_q.auq), $signed(triangle_q.avq), $signed(triangle_q.aq),
				$signed(triangle_q.bx), $signed(triangle_q.by), triangle_q.bz,
				$signed(triangle_q.buq), $signed(triangle_q.bvq), $signed(triangle_q.bq),
				$signed(triangle_q.cx), $signed(triangle_q.cy), triangle_q.cz,
				$signed(triangle_q.cuq), $signed(triangle_q.cvq), $signed(triangle_q.cq));
		end
	end
`endif

endmodule
