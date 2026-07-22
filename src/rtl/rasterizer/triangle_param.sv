module triangle_param (
	input logic clk_i,
	input logic rst_ni,

	input  rasterizer_pkg::triangle_t       triangle_i,
	input  logic                            in_valid_i,
	output logic                            in_ready_o,

	output rasterizer_pkg::triangle_param_t param_o,
	output logic                            out_valid_o,
	input  logic                            out_ready_i,

	output logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0] triangle_id_o,
	output logic                                         id_out_valid_o,
	input  logic                                         id_out_ready_i,

	input  logic [rasterizer_pkg::TEXTURE_ID_WIDTH-1:0] texture_id_i,
	input  logic                                        id_in_valid_i,
	output logic                                        id_in_ready_o
);

	import rasterizer_pkg::*;

	triangle_param_t param_q;
	triangle_t triangle_q;

	typedef enum logic [3:0] {
		E        = 4'd0,
		AREA     = 4'd1,
		Z_CALC   = 4'd2,
		Z_DERIV  = 4'd3,
		Z        = 4'd4,
		UQ_CALC  = 4'd5,
		UQ_DERIV = 4'd6,
		UQ       = 4'd7,
		VQ_CALC  = 4'd8,
		VQ_DERIV = 4'd9,
		VQ       = 4'd10,
		Q_CALC   = 4'd11,
		Q_DERIV  = 4'd12,
		Q        = 4'd13
	} state_e;
	state_e state_q;
	
	
	logic triangle_outside;
	logic signed [COORD_WIDTH-1:0] raw_min_x;
	logic signed [COORD_WIDTH-1:0] raw_max_x;
	logic signed [COORD_WIDTH-1:0] raw_min_y;
	logic signed [COORD_WIDTH-1:0] raw_max_y;
	logic [TILE_X_WIDTH-1:0] bbox_min_x;
	logic [TILE_X_WIDTH-1:0] bbox_max_x;
	logic [TILE_Y_WIDTH-1:0] bbox_min_y;
	logic [TILE_Y_WIDTH-1:0] bbox_max_y;

	localparam logic signed [COORD_WIDTH-1:0] SCREEN_X_LIMIT = COORD_WIDTH'(FRAME_WIDTH);
	localparam logic signed [COORD_WIDTH-1:0] SCREEN_Y_LIMIT = COORD_WIDTH'(FRAME_HEIGHT);
	localparam logic [TILE_X_WIDTH-1:0] LAST_TILE_X = TILE_X_WIDTH'(FRAME_WIDTH / TILE_WIDTH - 1);
	localparam logic [TILE_Y_WIDTH-1:0] LAST_TILE_Y = TILE_Y_WIDTH'(FRAME_HEIGHT / TILE_HEIGHT - 1);

	always_comb begin
		raw_min_x = triangle_i.ax;
		raw_max_x = triangle_i.ax;
		raw_min_y = triangle_i.ay;
		raw_max_y = triangle_i.ay;

		if ($signed(triangle_i.bx) < raw_min_x) raw_min_x = triangle_i.bx;
		if ($signed(triangle_i.cx) < raw_min_x) raw_min_x = triangle_i.cx;
		if ($signed(triangle_i.bx) > raw_max_x) raw_max_x = triangle_i.bx;
		if ($signed(triangle_i.cx) > raw_max_x) raw_max_x = triangle_i.cx;
		if ($signed(triangle_i.by) < raw_min_y) raw_min_y = triangle_i.by;
		if ($signed(triangle_i.cy) < raw_min_y) raw_min_y = triangle_i.cy;
		if ($signed(triangle_i.by) > raw_max_y) raw_max_y = triangle_i.by;
		if ($signed(triangle_i.cy) > raw_max_y) raw_max_y = triangle_i.cy;

		triangle_outside = raw_max_x < 0 || raw_min_x >= SCREEN_X_LIMIT	|| raw_max_y < 0 || raw_min_y >= SCREEN_Y_LIMIT;

		if (raw_min_x < 0) begin
			bbox_min_x = '0;
		end else if (raw_min_x >= SCREEN_X_LIMIT) begin
			bbox_min_x = LAST_TILE_X;
		end else begin
			bbox_min_x = TILE_X_WIDTH'($unsigned(raw_min_x) >> $clog2(TILE_WIDTH));
		end

		if (raw_max_x < 0) begin
			bbox_max_x = '0;
		end else if (raw_max_x >= SCREEN_X_LIMIT) begin
			bbox_max_x = LAST_TILE_X;
		end else begin
			bbox_max_x = TILE_X_WIDTH'($unsigned(raw_max_x) >> $clog2(TILE_WIDTH));
		end

		if (raw_min_y < 0) begin
			bbox_min_y = '0;
		end else if (raw_min_y >= SCREEN_Y_LIMIT) begin
			bbox_min_y = LAST_TILE_Y;
		end else begin
			bbox_min_y = TILE_Y_WIDTH'($unsigned(raw_min_y) >> $clog2(TILE_HEIGHT));
		end

		if (raw_max_y < 0) begin
			bbox_max_y = '0;
		end else if (raw_max_y >= SCREEN_Y_LIMIT) begin
			bbox_max_y = LAST_TILE_Y;
		end else begin
			bbox_max_y = TILE_Y_WIDTH'($unsigned(raw_max_y) >> $clog2(TILE_HEIGHT));
		end
	end

	logic [TEXTURE_ID_WIDTH-1:0] texture_id_q;
	logic texture_id_valid_q;
	logic triangle_busy_q;
	logic texture_complete;
	logic reciprocal_in_ready;

	always_comb begin
		param_o = param_q;
		param_o.texture_id = texture_id_q;

		triangle_id_o = triangle_i.triangle_id;
		id_out_valid_o = state_q == E && in_valid_i && !triangle_busy_q && !triangle_outside && reciprocal_in_ready;
		in_ready_o = state_q == E && !triangle_busy_q && (triangle_outside || (reciprocal_in_ready && id_out_ready_i));
		id_in_ready_o = triangle_busy_q && !texture_id_valid_q;
		texture_complete = texture_id_valid_q || (id_in_valid_i && id_in_ready_o);
	end

	logic [17:0] reciprocal_mantissa_q;
	logic [5:0] reciprocal_shift_q;
	logic reciprocal_valid;
	logic [17:0] reciprocal_mantissa;
	logic [5:0] reciprocal_shift;
	logic signed [32:0] triangle_area;

	always_comb begin
		triangle_area =
			$signed({{(33 - EDGE_WIDTH){param_q.e1[EDGE_WIDTH-1]}}, param_q.e1})
			+ $signed({{(33 - EDGE_WIDTH){param_q.e2[EDGE_WIDTH-1]}}, param_q.e2})
			+ $signed({{(33 - EDGE_WIDTH){param_q.e3[EDGE_WIDTH-1]}}, param_q.e3});
	end

	triangle_area_reciprocal triangle_area_reciprocal_i (
		.clk_i,
		.rst_ni,
		.in_valid_i (state_q == AREA && reciprocal_in_ready),
		.in_ready_o (reciprocal_in_ready),
		.area_i     (triangle_area),
		.out_valid_o(reciprocal_valid),
		.out_ready_i(state_q == AREA),
		.mantissa_o (reciprocal_mantissa),
		.shift_o    (reciprocal_shift)
	);

	logic signed [UVQ_WIDTH-1:0] attribute_a;
	logic signed [UVQ_NUM_WIDTH-1:0] attribute_num_dx;
	logic signed [UVQ_NUM_WIDTH-1:0] attribute_num_dy;
	logic signed [UVQ_WIDTH-1:0] attribute_dx;
	logic signed [UVQ_WIDTH-1:0] attribute_dy;
	logic signed [UVQ_WIDTH-1:0] attribute_value;
	logic signed [UVQ_WIDTH-1:0] attribute_a_q;
	logic signed [UVQ_NUM_WIDTH-1:0] attribute_num_dx_q;
	logic signed [UVQ_NUM_WIDTH-1:0] attribute_num_dy_q;
	logic signed [UVQ_WIDTH-1:0] attribute_dx_q;
	logic signed [UVQ_WIDTH-1:0] attribute_dy_q;

	always_comb begin
		logic signed [UVQ_WIDTH-1:0] attribute_b;
		logic signed [UVQ_WIDTH-1:0] attribute_c;
		logic signed [UVQ_WIDTH-1:0] attribute1;
		logic signed [UVQ_WIDTH-1:0] attribute2;
		logic signed [63:0] attribute_product_dx;
		logic signed [63:0] attribute_product_dy;
		logic signed [63:0] attribute_origin;

		attribute_a = '0;
		attribute_b = '0;
		attribute_c = '0;

		if (state_q == Z_CALC) begin
			attribute_a = UVQ_WIDTH'($signed({1'b0, triangle_q.az, {DEPTH_FRAC_WIDTH{1'b0}}}));
			attribute_b = UVQ_WIDTH'($signed({1'b0, triangle_q.bz, {DEPTH_FRAC_WIDTH{1'b0}}}));
			attribute_c = UVQ_WIDTH'($signed({1'b0, triangle_q.cz, {DEPTH_FRAC_WIDTH{1'b0}}}));
		end else if (state_q == UQ_CALC) begin
			attribute_a = triangle_q.auq;
			attribute_b = triangle_q.buq;
			attribute_c = triangle_q.cuq;
		end else if (state_q == VQ_CALC) begin
			attribute_a = triangle_q.avq;
			attribute_b = triangle_q.bvq;
			attribute_c = triangle_q.cvq;
		end else if (state_q == Q_CALC) begin
			attribute_a = triangle_q.aq;
			attribute_b = triangle_q.bq;
			attribute_c = triangle_q.cq;
		end

		attribute1 = attribute_b - attribute_a;
		attribute2 = attribute_c - attribute_b;

		attribute_num_dx = $signed(attribute1) * $signed(param_q.dy2) - $signed(attribute2) * $signed(param_q.dy1);
		attribute_num_dy = $signed(param_q.dx1) * $signed(attribute2) - $signed(param_q.dx2) * $signed(attribute1);

		attribute_product_dx = $signed(attribute_num_dx_q) * $signed({1'b0, reciprocal_mantissa_q});
		attribute_product_dy = $signed(attribute_num_dy_q) * $signed({1'b0, reciprocal_mantissa_q});

		attribute_dx = UVQ_WIDTH'(attribute_product_dx >>> reciprocal_shift_q);
		attribute_dy = UVQ_WIDTH'(attribute_product_dy >>> reciprocal_shift_q);

		attribute_origin = 64'($signed(attribute_a_q));
		attribute_origin = attribute_origin - $signed(attribute_dx_q) * $signed(triangle_q.ax);
		attribute_origin = attribute_origin - $signed(attribute_dy_q) * $signed(triangle_q.ay);
		attribute_value = attribute_origin[UVQ_WIDTH-1:0];
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			state_q <= E;
			param_q <= '0;
			reciprocal_mantissa_q <= '0;
			reciprocal_shift_q <= '0;
			attribute_a_q <= '0;
			attribute_num_dx_q <= '0;
			attribute_num_dy_q <= '0;
			attribute_dx_q <= '0;
			attribute_dy_q <= '0;
		end else begin
			unique case (state_q)
				E: begin
					if (in_valid_i && in_ready_o && !triangle_outside) begin
						param_q.triangle_id <= triangle_i.triangle_id;
						param_q.fbid_color <= triangle_i.fbid_color;
						param_q.fbid_depth <= triangle_i.fbid_depth;

						param_q.bbox_min_x <= bbox_min_x;
						param_q.bbox_max_x <= bbox_max_x;
						param_q.bbox_min_y <= bbox_min_y;
						param_q.bbox_max_y <= bbox_max_y;

						param_q.dx1 <= triangle_i.bx - triangle_i.ax;
						param_q.dy1 <= triangle_i.by - triangle_i.ay;
						param_q.dx2 <= triangle_i.cx - triangle_i.bx;
						param_q.dy2 <= triangle_i.cy - triangle_i.by;
						param_q.dx3 <= triangle_i.ax - triangle_i.cx;
						param_q.dy3 <= triangle_i.ay - triangle_i.cy;

						param_q.e1 <= EDGE_WIDTH'(triangle_i.ax) * EDGE_WIDTH'(triangle_i.by) - EDGE_WIDTH'(triangle_i.ay) * EDGE_WIDTH'(triangle_i.bx);
						param_q.e2 <= EDGE_WIDTH'(triangle_i.bx) * EDGE_WIDTH'(triangle_i.cy) - EDGE_WIDTH'(triangle_i.by) * EDGE_WIDTH'(triangle_i.cx);
						param_q.e3 <= EDGE_WIDTH'(triangle_i.cx) * EDGE_WIDTH'(triangle_i.ay) - EDGE_WIDTH'(triangle_i.cy) * EDGE_WIDTH'(triangle_i.ax);

						state_q <= AREA;
					end
				end
				AREA: begin
					if (reciprocal_valid) begin
						reciprocal_mantissa_q <= reciprocal_mantissa;
						reciprocal_shift_q    <= reciprocal_shift;
						state_q <= Z_CALC;
					end
				end
				Z_CALC: begin
					attribute_a_q      <= attribute_a;
					attribute_num_dx_q <= attribute_num_dx;
					attribute_num_dy_q <= attribute_num_dy;
					state_q <= Z_DERIV;
				end
				Z_DERIV: begin
					attribute_dx_q <= attribute_dx;
					attribute_dy_q <= attribute_dy;
					state_q <= Z;
				end
				Z: begin
					param_q.z     <= DEPTH_INTERP_WIDTH'(attribute_value);
					param_q.dz_dx <= DEPTH_INTERP_WIDTH'(attribute_dx_q);
					param_q.dz_dy <= DEPTH_INTERP_WIDTH'(attribute_dy_q);
					state_q <= UQ_CALC;
				end
				UQ_CALC: begin
					attribute_a_q      <= attribute_a;
					attribute_num_dx_q <= attribute_num_dx;
					attribute_num_dy_q <= attribute_num_dy;
					state_q <= UQ_DERIV;
				end
				UQ_DERIV: begin
					attribute_dx_q <= attribute_dx;
					attribute_dy_q <= attribute_dy;
					state_q <= UQ;
				end
				UQ: begin
					param_q.uq     <= attribute_value;
					param_q.duq_dx <= attribute_dx_q;
					param_q.duq_dy <= attribute_dy_q;
					state_q <= VQ_CALC;
				end
				VQ_CALC: begin
					attribute_a_q      <= attribute_a;
					attribute_num_dx_q <= attribute_num_dx;
					attribute_num_dy_q <= attribute_num_dy;
					state_q <= VQ_DERIV;
				end
				VQ_DERIV: begin
					attribute_dx_q <= attribute_dx;
					attribute_dy_q <= attribute_dy;
					state_q <= VQ;
				end
				VQ: begin
					param_q.vq     <= attribute_value;
					param_q.dvq_dx <= attribute_dx_q;
					param_q.dvq_dy <= attribute_dy_q;
					state_q <= Q_CALC;
				end
				Q_CALC: begin
					attribute_a_q      <= attribute_a;
					attribute_num_dx_q <= attribute_num_dx;
					attribute_num_dy_q <= attribute_num_dy;
					state_q <= Q_DERIV;
				end
				Q_DERIV: begin
					attribute_dx_q <= attribute_dx;
					attribute_dy_q <= attribute_dy;
					state_q <= Q;
				end
				Q: begin
					param_q.q     <= attribute_value;
					param_q.dq_dx <= attribute_dx_q;
					param_q.dq_dy <= attribute_dy_q;
					if (texture_complete) begin
						state_q <= E;
					end
				end
			endcase
		end
	end

	always_ff @(posedge clk_i) begin
		if (~rst_ni) begin
			texture_id_q <= '0;
			texture_id_valid_q <= 1'b0;
		end else begin
			if (state_q == E && in_valid_i && in_ready_o && !triangle_outside) begin
				texture_id_valid_q <= 1'b0;
			end
			if (id_in_valid_i && id_in_ready_o) begin
				texture_id_q <= texture_id_i;
				texture_id_valid_q <= 1'b1;
			end
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			triangle_q  <= '0;
			out_valid_o <= 1'b0;
			triangle_busy_q <= 1'b0;
		end else if (state_q == E && in_valid_i && in_ready_o && !triangle_outside) begin
			triangle_q <= triangle_i;
			triangle_busy_q <= 1'b1;
		end else if (state_q == Q && texture_complete) begin
			out_valid_o <= 1'b1;
		end else if (state_q == E && out_ready_i && out_valid_o) begin
			out_valid_o <= 1'b0;
			triangle_busy_q <= 1'b0;
		end
	end

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			$display("triangle_param,%0t,input,triangle,%h", $time, triangle_i);
		end

		if (out_valid_o && out_ready_i) begin
			$display("triangle_param,%0t,output,param,%h", $time, param_o);
		end
	end
`endif

endmodule

