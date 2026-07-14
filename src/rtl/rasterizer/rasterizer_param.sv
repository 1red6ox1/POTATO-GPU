module rasterizer_param
import rasterizer_pkg::*;
(
	input logic clk_i,
	input logic rst_ni,

	input  triangle2d_t triangle2d_i,
	input  logic                        in_valid_i,
	output logic                        in_ready_o,

	output rasterization_param_t param_o,
	output logic                                  out_valid_o,
	input  logic                                  out_ready_i
);

	triangle2d_t triangle2d_q;
	rasterization_param_t param_q;

	typedef enum logic [2:0] {
		WAIT     = 3'd0,
		E        = 3'd1,
		AREA     = 3'd2,
		PARAM0   = 3'd3,
		PARAM1   = 3'd4,
		PARAM2   = 3'd5,
		PARAM3   = 3'd6,
		OUTPUT   = 3'd7
	} state_e;

	typedef enum logic [1:0] {
		Z  = 2'b00,
		UQ = 2'b01,
		VQ = 2'b10,
		Q  = 2'b11
	} attribute_e;

	state_e state_q;
	attribute_e attribute_q;

	logic signed [COORD_WIDTH-1:0] bbox_min_x, bbox_max_x;
	logic signed [COORD_WIDTH-1:0] bbox_min_y, bbox_max_y;
	logic signed [COORD_WIDTH-1:0] dx1, dx2, dx3;
	logic signed [COORD_WIDTH-1:0] dy1, dy2, dy3;
	logic signed [EDGE_WIDTH-1:0] e1, e2, e3;
	logic signed [2*COORD_WIDTH-1:0] area_product0, area_product1;
	logic signed [2*COORD_WIDTH:0] triangle_area;
	logic [2*COORD_WIDTH:0] triangle_area_q;
	logic area_sent_q;
	logic reciprocal_in_ready;
	logic reciprocal_valid;
	logic [17:0] reciprocal_mantissa;
	logic [5:0] reciprocal_shift;
	logic [17:0] reciprocal_mantissa_q;
	logic [5:0] reciprocal_shift_q;

	logic signed [UVQ_WIDTH-1:0] attr_a, attr_b, attr_c;
	logic signed [UVQ_WIDTH-1:0] attr_a_q;
	logic signed [UVQ_WIDTH-1:0] attr1, attr2;
	logic signed [UVQ_WIDTH-1:0] attr1_q, attr2_q;
	logic signed [UVQ_NUM_WIDTH-1:0] attr_num_dx, attr_num_dy;
	logic signed [UVQ_NUM_WIDTH-1:0] attr_num_dx_q, attr_num_dy_q;

	logic signed [63:0] attr_product_dx, attr_product_dy;
	logic signed [UVQ_WIDTH-1:0] attr_dx, attr_dy;
	logic signed [UVQ_WIDTH-1:0] attr_dx_q, attr_dy_q;
	logic signed [63:0] attr_wide;
	logic signed [UVQ_WIDTH-1:0] attr_calc;

	assign param_o     = param_q;
	assign in_ready_o  = (state_q == WAIT);
	assign out_valid_o = (state_q == OUTPUT);

	triangle_area_reciprocal triangle_area_reciprocal_i (
		.clk_i,
		.rst_ni,
		.in_valid_i (state_q == AREA && !area_sent_q),
		.in_ready_o (reciprocal_in_ready),
		.area_i     (triangle_area_q),
		.out_valid_o(reciprocal_valid),
		.out_ready_i(state_q == AREA),
		.mantissa_o (reciprocal_mantissa),
		.shift_o    (reciprocal_shift)
	);

	always_comb begin
		bbox_min_x = '0;
		bbox_max_x = '0;
		bbox_min_y = '0;
		bbox_max_y = '0;
		dx1 = '0;
		dy1 = '0;
		dx2 = '0;
		dy2 = '0;
		dx3 = '0;
		dy3 = '0;
		e1 = '0;
		e2 = '0;
		e3 = '0;
		area_product0 = '0;
		area_product1 = '0;
		triangle_area = '0;

		if (state_q == E) begin
			bbox_min_x = (triangle2d_q.ax < triangle2d_q.bx) ?
			             ((triangle2d_q.ax < triangle2d_q.cx) ? triangle2d_q.ax : triangle2d_q.cx) :
			             ((triangle2d_q.bx < triangle2d_q.cx) ? triangle2d_q.bx : triangle2d_q.cx);
			bbox_max_x = (triangle2d_q.ax > triangle2d_q.bx) ?
			             ((triangle2d_q.ax > triangle2d_q.cx) ? triangle2d_q.ax : triangle2d_q.cx) :
			             ((triangle2d_q.bx > triangle2d_q.cx) ? triangle2d_q.bx : triangle2d_q.cx);
			bbox_min_y = (triangle2d_q.ay < triangle2d_q.by) ?
			             ((triangle2d_q.ay < triangle2d_q.cy) ? triangle2d_q.ay : triangle2d_q.cy) :
			             ((triangle2d_q.by < triangle2d_q.cy) ? triangle2d_q.by : triangle2d_q.cy);
			bbox_max_y = (triangle2d_q.ay > triangle2d_q.by) ?
			             ((triangle2d_q.ay > triangle2d_q.cy) ? triangle2d_q.ay : triangle2d_q.cy) :
			             ((triangle2d_q.by > triangle2d_q.cy) ? triangle2d_q.by : triangle2d_q.cy);

			e1 = EDGE_WIDTH'(triangle2d_q.ax) * EDGE_WIDTH'(triangle2d_q.by)
			   - EDGE_WIDTH'(triangle2d_q.ay) * EDGE_WIDTH'(triangle2d_q.bx);
			e2 = EDGE_WIDTH'(triangle2d_q.bx) * EDGE_WIDTH'(triangle2d_q.cy)
			   - EDGE_WIDTH'(triangle2d_q.by) * EDGE_WIDTH'(triangle2d_q.cx);
			e3 = EDGE_WIDTH'(triangle2d_q.cx) * EDGE_WIDTH'(triangle2d_q.ay)
			   - EDGE_WIDTH'(triangle2d_q.cy) * EDGE_WIDTH'(triangle2d_q.ax);

			dx1 = triangle2d_q.bx - triangle2d_q.ax;
			dy1 = triangle2d_q.by - triangle2d_q.ay;
			dx2 = triangle2d_q.cx - triangle2d_q.bx;
			dy2 = triangle2d_q.cy - triangle2d_q.by;
			dx3 = triangle2d_q.ax - triangle2d_q.cx;
			dy3 = triangle2d_q.ay - triangle2d_q.cy;

			area_product0 = $signed(dx1) * $signed(dy2);
			area_product1 = $signed(dy1) * $signed(dx2);
			triangle_area =
				$signed({area_product0[2*COORD_WIDTH-1], area_product0})
				- $signed({area_product1[2*COORD_WIDTH-1], area_product1});
		end
	end

	always_comb begin
		attr_a = '0;
		attr_b = '0;
		attr_c = '0;

		unique case (attribute_q)
			Z: begin
				attr_a = UVQ_WIDTH'($signed({1'b0, triangle2d_q.az,
				                         {DEPTH_FRAC_WIDTH{1'b0}}}));
				attr_b = UVQ_WIDTH'($signed({1'b0, triangle2d_q.bz,
				                         {DEPTH_FRAC_WIDTH{1'b0}}}));
				attr_c = UVQ_WIDTH'($signed({1'b0, triangle2d_q.cz,
				                         {DEPTH_FRAC_WIDTH{1'b0}}}));
			end
			UQ: begin
				attr_a = triangle2d_q.auq;
				attr_b = triangle2d_q.buq;
				attr_c = triangle2d_q.cuq;
			end
			VQ: begin
				attr_a = triangle2d_q.avq;
				attr_b = triangle2d_q.bvq;
				attr_c = triangle2d_q.cvq;
			end
			Q: begin
				attr_a = triangle2d_q.aq;
				attr_b = triangle2d_q.bq;
				attr_c = triangle2d_q.cq;
			end
			default: ;
		endcase
	end

	always_comb begin
		attr1 = '0;
		attr2 = '0;
		if (state_q == PARAM0) begin
			attr1 = attr_b - attr_a;
			attr2 = attr_c - attr_b;
		end
	end

	always_comb begin
		attr_num_dx = '0;
		attr_num_dy = '0;
		if (state_q == PARAM1) begin
			attr_num_dx =
				$signed(attr1_q) * $signed(param_q.dy2)
				- $signed(attr2_q) * $signed(param_q.dy1);

			attr_num_dy =
				$signed(param_q.dx1) * $signed(attr2_q)
				- $signed(param_q.dx2) * $signed(attr1_q);
		end
	end

	always_comb begin
		attr_product_dx = '0;
		attr_product_dy = '0;
		attr_dx = '0;
		attr_dy = '0;

		if (state_q == PARAM2) begin
			attr_product_dx = $signed(attr_num_dx_q)
			                * $signed({1'b0, reciprocal_mantissa_q});
			attr_product_dy = $signed(attr_num_dy_q)
			                * $signed({1'b0, reciprocal_mantissa_q});

			attr_dx = UVQ_WIDTH'(
				$signed(attr_product_dx >>> reciprocal_shift_q));
			attr_dy = UVQ_WIDTH'(
				$signed(attr_product_dy >>> reciprocal_shift_q));
		end
	end

	always_comb begin
		attr_wide = '0;
		attr_calc = '0;
		if (state_q == PARAM3) begin
			attr_wide = 64'($signed(attr_a_q));
			attr_wide = attr_wide - $signed(attr_dx_q) * $signed(triangle2d_q.ax);
			attr_wide = attr_wide - $signed(attr_dy_q) * $signed(triangle2d_q.ay);
			attr_calc = attr_wide[UVQ_WIDTH-1:0];
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (!rst_ni) begin
			triangle2d_q <= '0;
			param_q       <= '0;
			state_q       <= WAIT;
			attribute_q   <= Z;
			attr_a_q      <= '0;
			attr1_q       <= '0;
			attr2_q       <= '0;
			attr_num_dx_q <= '0;
			attr_num_dy_q <= '0;
			attr_dx_q     <= '0;
			attr_dy_q     <= '0;
			reciprocal_mantissa_q <= '0;
			reciprocal_shift_q    <= '0;
			triangle_area_q       <= '0;
			area_sent_q           <= 1'b0;
		end else begin
			unique case (state_q)
				WAIT: begin
					if (in_valid_i && in_ready_o) begin
						triangle2d_q <= triangle2d_i;
						state_q      <= E;
					end
				end

				E: begin
					param_q.fbid_color <= triangle2d_q.fbid_color;
					param_q.fbid_depth <= triangle2d_q.fbid_depth;
					param_q.bbox_min_x <= $clog2(FRAME_WIDTH / TILE_WIDTH)'(
						bbox_min_x >>> $clog2(TILE_WIDTH));
					param_q.bbox_max_x <= $clog2(FRAME_WIDTH / TILE_WIDTH)'(
						bbox_max_x >>> $clog2(TILE_WIDTH));
					param_q.bbox_min_y <= $clog2(FRAME_HEIGHT / TILE_HEIGHT)'(
						bbox_min_y >>> $clog2(TILE_HEIGHT));
					param_q.bbox_max_y <= $clog2(FRAME_HEIGHT / TILE_HEIGHT)'(
						bbox_max_y >>> $clog2(TILE_HEIGHT));
					param_q.dx1 <= dx1;
					param_q.dy1 <= dy1;
					param_q.e1  <= e1;
					param_q.dx2 <= dx2;
					param_q.dy2 <= dy2;
					param_q.e2  <= e2;
					param_q.dx3 <= dx3;
					param_q.dy3 <= dy3;
					param_q.e3  <= e3;
					triangle_area_q <= triangle_area;
					attribute_q <= Z;
					state_q     <= AREA;
				end

				AREA: begin
					if (!area_sent_q && reciprocal_in_ready) begin
						area_sent_q <= 1'b1;
					end
					if (reciprocal_valid) begin
						reciprocal_mantissa_q <= reciprocal_mantissa;
						reciprocal_shift_q    <= reciprocal_shift;
						area_sent_q            <= 1'b0;
						state_q               <= PARAM0;
					end
				end

				PARAM0: begin
					attr_a_q <= attr_a;
					attr1_q  <= attr1;
					attr2_q  <= attr2;
					state_q  <= PARAM1;
				end

				PARAM1: begin
					attr_num_dx_q <= attr_num_dx;
					attr_num_dy_q <= attr_num_dy;
					state_q       <= PARAM2;
				end

				PARAM2: begin
					attr_dx_q <= attr_dx;
					attr_dy_q <= attr_dy;
					state_q   <= PARAM3;
				end

				PARAM3: begin
					unique case (attribute_q)
						Z: begin
							param_q.z <= attr_calc[DEPTH_INTERP_WIDTH-1:0];
							param_q.dz_dx <= attr_dx_q[DEPTH_INTERP_WIDTH-1:0];
							param_q.dz_dy <= attr_dy_q[DEPTH_INTERP_WIDTH-1:0];
							attribute_q <= UQ;
							state_q <= PARAM0;
						end
						UQ: begin
							param_q.uq <= attr_calc;
							param_q.duq_dx <= attr_dx_q;
							param_q.duq_dy <= attr_dy_q;
							attribute_q <= VQ;
							state_q <= PARAM0;
						end
						VQ: begin
							param_q.vq <= attr_calc;
							param_q.dvq_dx <= attr_dx_q;
							param_q.dvq_dy <= attr_dy_q;
							attribute_q <= Q;
							state_q <= PARAM0;
						end
						Q: begin
							param_q.q <= attr_calc;
							param_q.dq_dx <= attr_dx_q;
							param_q.dq_dy <= attr_dy_q;
							state_q <= OUTPUT;
						end
						default: state_q <= WAIT;
					endcase
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
		if (rst_ni && state_q == E) begin
			assert (triangle_area > 0)
				else $error("rasterizer_param requires a positive nonzero triangle area");
			$display("rasterizer_param,%0t,bbox,%0d,%0d,%0d,%0d,edge1,%0d,%0d,%0d,edge2,%0d,%0d,%0d,edge3,%0d,%0d,%0d",
			         $time,
			         bbox_min_x, bbox_min_y, bbox_max_x, bbox_max_y,
			         dx1, dy1, e1,
			         dx2, dy2, e2,
			         dx3, dy3, e3);
		end

		if (rst_ni && state_q == AREA && reciprocal_valid) begin
			$display("rasterizer_param,%0t,area,%0d,reciprocal,%0d,shift,%0d",
			         $time, triangle_area_q, reciprocal_mantissa, reciprocal_shift);
		end

		if (rst_ni && state_q == PARAM3) begin
			unique case (attribute_q)
				Z:  $display("rasterizer_param,%0t,z,origin,%0d,dx,%0d,dy,%0d",
				             $time, attr_calc, attr_dx_q, attr_dy_q);
				UQ: $display("rasterizer_param,%0t,uq,origin,%0d,dx,%0d,dy,%0d",
				             $time, attr_calc, attr_dx_q, attr_dy_q);
				VQ: $display("rasterizer_param,%0t,vq,origin,%0d,dx,%0d,dy,%0d",
				             $time, attr_calc, attr_dx_q, attr_dy_q);
				Q:  $display("rasterizer_param,%0t,q,origin,%0d,dx,%0d,dy,%0d",
				             $time, attr_calc, attr_dx_q, attr_dy_q);
				default: ;
			endcase
		end
	end
`endif

endmodule
