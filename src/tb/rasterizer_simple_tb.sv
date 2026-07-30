module rasterizer_simple_tb;

	import rasterizer_pkg::*;

	logic clk = 1'b0;
	logic rst_n = 1'b0;
	int unsigned errcnt;

	triangle_param_t param;

	logic one_q_in_valid;
	logic one_q_in_ready;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] one_q;
	logic one_q_out_valid;
	logic one_q_out_ready;

	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] uv_one_q;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] uv_uq;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] uv_vq;
	logic uv_one_q_valid;
	logic uv_one_q_ready;
	logic uv_uq_vq_valid;
	logic uv_uq_vq_ready;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] uv_u;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] uv_v;
	logic [TRIANGLE_ID_WIDTH-1:0] uv_triangle_id;
	logic [TEXTURE_ID_WIDTH-1:0] uv_texture_id;
	logic uv_out_valid;
	logic uv_out_ready;

	logic depth_in_valid;
	logic depth_in_ready;
	logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] depth;
	logic depth_out_valid;
	logic depth_out_ready;

	logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] mask_z;
	logic [255:0] mask_depth1;
	logic [255:0] mask_depth2;
	logic mask_z_valid;
	logic mask_z_ready;
	logic mask_depth1_valid;
	logic mask_depth1_ready;
	logic mask_depth2_valid;
	logic mask_depth2_ready;
	logic [TILE_WIDTH-1:0][DEPTH_WIDTH-1:0] mask_z_out;
	logic [TILE_WIDTH-1:0] depth_mask_out;
	logic mask_out_valid;
	logic mask_out_ready;

	logic line_in_valid;
	logic line_in_ready;
	logic [TILE_X_WIDTH-1:0] line_tile_x;
	logic [FRAME_Y_WIDTH-1:0] line_y;
	triangle_param_t line_param;
	logic [TILE_WIDTH-1:0] line_mask;
	logic line_out_valid;
	logic line_out_ready;

	logic tile_fifo_in_valid;
	logic tile_fifo_in_ready;
	logic [TILE_X_WIDTH-1:0] tile_fifo_in_x;
	logic [TILE_Y_WIDTH-1:0] tile_fifo_in_y;
	logic signed [EDGE_WIDTH-1:0] tile_fifo_in_e1;
	logic signed [EDGE_WIDTH-1:0] tile_fifo_in_e2;
	logic signed [EDGE_WIDTH-1:0] tile_fifo_in_e3;
	logic tile_fifo_in_reject;
	logic [TILE_X_WIDTH-1:0] tile_fifo_out_x;
	logic [TILE_Y_WIDTH-1:0] tile_fifo_out_y;
	logic signed [EDGE_WIDTH-1:0] tile_fifo_out_e1;
	logic signed [EDGE_WIDTH-1:0] tile_fifo_out_e2;
	logic signed [EDGE_WIDTH-1:0] tile_fifo_out_e3;
	logic tile_fifo_out_reject;
	logic tile_fifo_out_valid;
	logic tile_fifo_out_ready;

	logic tile_reject_out;
	logic signed [EDGE_WIDTH-1:0] tile_e1;
	logic signed [EDGE_WIDTH-1:0] tile_e2;
	logic signed [EDGE_WIDTH-1:0] tile_e3;

	logic core_in_valid;
	logic core_in_ready;
	logic [TILE_X_WIDTH-1:0] core_tile_x;
	logic [TILE_Y_WIDTH-1:0] core_tile_y;
	triangle_param_t core_param;
	logic core_out_valid;
	logic core_out_ready;

	triangle_t triangle;
	logic triangle_in_valid;
	logic triangle_in_ready;
	triangle_param_t triangle_param_out;
	logic triangle_param_valid;
	logic triangle_param_ready;
	logic [TRIANGLE_ID_WIDTH-1:0] triangle_id_request;
	logic triangle_id_request_valid;
	logic triangle_id_request_ready;
	logic [TEXTURE_ID_WIDTH-1:0] texture_id_response;
	logic texture_id_response_valid;
	logic texture_id_response_ready;

	logic uq_vq_in_valid;
	logic uq_vq_in_ready;
	logic [TILE_X_WIDTH-1:0] uq_vq_tile_x;
	logic [FRAME_Y_WIDTH-1:0] uq_vq_y;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] uq_out;
	logic [TILE_WIDTH-1:0][UVQ_WIDTH-1:0] vq_out;
	logic [TRIANGLE_ID_WIDTH-1:0] uq_vq_triangle_id;
	logic [TEXTURE_ID_WIDTH-1:0] uq_vq_texture_id;
	logic uq_vq_out_valid;
	logic uq_vq_out_ready;

	always #10000 clk = ~clk;

	calculate_1q calculate_1q_i (
		.clk_i        (clk),
		.rst_ni       (rst_n),
		.param_i      (param),
		.tile_x_i     ('0),
		.y_i          ('0),
		.in_valid_i   (one_q_in_valid),
		.in_ready_o   (one_q_in_ready),
		.one_q_o      (one_q),
		.out_valid_o  (one_q_out_valid),
		.out_ready_i  (one_q_out_ready)
	);

	calculate_uv calculate_uv_i (
		.clk_i          (clk),
		.rst_ni         (rst_n),
		.one_q_i        (uv_one_q),
		.one_q_valid_i  (uv_one_q_valid),
		.one_q_ready_o  (uv_one_q_ready),
		.uq_i           (uv_uq),
		.vq_i           (uv_vq),
		.triangle_id_i  (11'd7),
		.texture_id_i   (8'd3),
		.uq_vq_valid_i  (uv_uq_vq_valid),
		.uq_vq_ready_o  (uv_uq_vq_ready),
		.u_o            (uv_u),
		.v_o            (uv_v),
		.triangle_id_o  (uv_triangle_id),
		.texture_id_o   (uv_texture_id),
		.out_valid_o    (uv_out_valid),
		.out_ready_i    (uv_out_ready)
	);

	depth_calculation depth_calculation_i (
		.clk_i         (clk),
		.rst_ni       (rst_n),
		.param_i      (param),
		.tile_x_i     ('0),
		.y_i          ('0),
		.in_valid_i   (depth_in_valid),
		.in_ready_o   (depth_in_ready),
		.depth_o      (depth),
		.out_valid_o  (depth_out_valid),
		.out_ready_i  (depth_out_ready)
	);

	depth_mask depth_mask_i (
		.clk_i           (clk),
		.rst_ni         (rst_n),
		.z_i            (mask_z),
		.z_valid_i      (mask_z_valid),
		.z_ready_o      (mask_z_ready),
		.depth1_i       (mask_depth1),
		.depth1_valid_i (mask_depth1_valid),
		.depth1_ready_o (mask_depth1_ready),
		.depth2_i       (mask_depth2),
		.depth2_valid_i (mask_depth2_valid),
		.depth2_ready_o (mask_depth2_ready),
		.z_o            (mask_z_out),
		.mask_o         (depth_mask_out),
		.out_valid_o    (mask_out_valid),
		.out_ready_i    (mask_out_ready)
	);

	line_fifo line_fifo_i (
		.clk_i        (clk),
		.rst_ni       (rst_n),
		.tile_x_i     (6'd2),
		.tile_y_i     (8'd3),
		.param_i      (param),
		.e1_i         (28'sd1),
		.e2_i         (28'sd1),
		.e3_i         (28'sd1),
		.in_valid_i   (line_in_valid),
		.in_ready_o   (line_in_ready),
		.tile_x_o     (line_tile_x),
		.y_o          (line_y),
		.param_o      (line_param),
		.mask_o       (line_mask),
		.out_valid_o  (line_out_valid),
		.out_ready_i  (line_out_ready)
	);

	tile_fifo #(
		.Depth (2)
	) tile_fifo_i (
		.clk_i        (clk),
		.rst_ni       (rst_n),
		.tile_x_i    (tile_fifo_in_x),
		.tile_y_i    (tile_fifo_in_y),
		.param_i     (param),
		.e1_i        (tile_fifo_in_e1),
		.e2_i        (tile_fifo_in_e2),
		.e3_i        (tile_fifo_in_e3),
		.reject_i    (tile_fifo_in_reject),
		.in_valid_i  (tile_fifo_in_valid),
		.in_ready_o  (tile_fifo_in_ready),
		.tile_x_o    (tile_fifo_out_x),
		.tile_y_o    (tile_fifo_out_y),
		.param_o     (),
		.e1_o        (tile_fifo_out_e1),
		.e2_o        (tile_fifo_out_e2),
		.e3_o        (tile_fifo_out_e3),
		.reject_o    (tile_fifo_out_reject),
		.out_valid_o (tile_fifo_out_valid),
		.out_ready_i (tile_fifo_out_ready)
	);

	tile_reject tile_reject_i (
		.param_i  (param),
		.tile_x_i ('0),
		.tile_y_i ('0),
		.reject_o (tile_reject_out),
		.e1_o     (tile_e1),
		.e2_o     (tile_e2),
		.e3_o     (tile_e3)
	);

	triangle_core triangle_core_i (
		.clk_i        (clk),
		.rst_ni       (rst_n),
		.param_i      (param),
		.in_valid_i   (core_in_valid),
		.in_ready_o   (core_in_ready),
		.tile_x_o     (core_tile_x),
		.tile_y_o     (core_tile_y),
		.param_o      (core_param),
		.out_valid_o  (core_out_valid),
		.out_ready_i  (core_out_ready)
	);

	triangle_param triangle_param_i (
		.clk_i             (clk),
		.rst_ni          (rst_n),
		.triangle_i      (triangle),
		.in_valid_i      (triangle_in_valid),
		.in_ready_o      (triangle_in_ready),
		.param_o         (triangle_param_out),
		.out_valid_o     (triangle_param_valid),
		.out_ready_i     (triangle_param_ready),
		.triangle_id_o   (triangle_id_request),
		.id_out_valid_o  (triangle_id_request_valid),
		.id_out_ready_i  (triangle_id_request_ready),
		.texture_id_i    (texture_id_response),
		.id_in_valid_i   (texture_id_response_valid),
		.id_in_ready_o   (texture_id_response_ready)
	);

	uq_vq_calculation uq_vq_calculation_i (
		.clk_i          (clk),
		.rst_ni         (rst_n),
		.param_i        (param),
		.tile_x_i       (uq_vq_tile_x),
		.y_i            (uq_vq_y),
		.in_valid_i     (uq_vq_in_valid),
		.in_ready_o     (uq_vq_in_ready),
		.uq_o           (uq_out),
		.vq_o           (vq_out),
		.triangle_id_o  (uq_vq_triangle_id),
		.texture_id_o   (uq_vq_texture_id),
		.out_valid_o    (uq_vq_out_valid),
		.out_ready_i    (uq_vq_out_ready)
	);

	task automatic check(input logic condition, input string name);
		if (condition !== 1'b1) begin
			$error("%s", name);
			errcnt++;
		end
	endtask

	task automatic wait_for_one_q;
		int unsigned timeout;
		timeout = 0;
		while (!one_q_out_valid && timeout < 200) begin
			@(posedge clk);
			timeout++;
		end
		check(one_q_out_valid, "calculate_1q: output timeout");
	endtask

	task automatic wait_for_triangle_param;
		int unsigned timeout;
		timeout = 0;
		while (!triangle_param_valid && timeout < 100) begin
			@(posedge clk);
			timeout++;
		end
		check(triangle_param_valid, "triangle_param: output timeout");
	endtask

	initial begin
		errcnt = 0;
		param = '0;
		triangle = '0;

		one_q_in_valid = 1'b0;
		one_q_out_ready = 1'b0;
		uv_one_q = '0;
		uv_uq = '0;
		uv_vq = '0;
		uv_one_q_valid = 1'b0;
		uv_uq_vq_valid = 1'b0;
		uv_out_ready = 1'b0;
		depth_in_valid = 1'b0;
		depth_out_ready = 1'b0;
		mask_z = '0;
		mask_depth1 = '0;
		mask_depth2 = '0;
		mask_z_valid = 1'b0;
		mask_depth1_valid = 1'b0;
		mask_depth2_valid = 1'b0;
		mask_out_ready = 1'b0;
		line_in_valid = 1'b0;
		line_out_ready = 1'b0;
		tile_fifo_in_valid = 1'b0;
		tile_fifo_in_x = '0;
		tile_fifo_in_y = '0;
		tile_fifo_in_e1 = '0;
		tile_fifo_in_e2 = '0;
		tile_fifo_in_e3 = '0;
		tile_fifo_in_reject = 1'b0;
		tile_fifo_out_ready = 1'b0;
		core_in_valid = 1'b0;
		core_out_ready = 1'b0;
		triangle_in_valid = 1'b0;
		triangle_param_ready = 1'b0;
		triangle_id_request_ready = 1'b1;
		texture_id_response = 8'd5;
		texture_id_response_valid = 1'b0;
		uq_vq_in_valid = 1'b0;
		uq_vq_tile_x = '0;
		uq_vq_y = '0;
		uq_vq_out_ready = 1'b0;

		repeat (4) @(posedge clk);
		@(negedge clk);
		rst_n = 1'b1;

		// calculate_1q: three simple reciprocals, checking only pixel zero.
		param = '0;
		param.q = UVQ_WIDTH'(1) << UVQ_FRAC_WIDTH;
		@(negedge clk);
		one_q_in_valid = 1'b1;
		@(negedge clk);
		one_q_in_valid = 1'b0;
		wait_for_one_q();
		#1;
		check(one_q[0] == UVQ_WIDTH'(1) << UVQ_FRAC_WIDTH,
			"calculate_1q: first pixel is not 1.0");
		one_q_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		one_q_out_ready = 1'b0;

		param.q = UVQ_WIDTH'(2) << UVQ_FRAC_WIDTH;
		@(negedge clk);
		one_q_in_valid = 1'b1;
		@(negedge clk);
		one_q_in_valid = 1'b0;
		wait_for_one_q();
		#1;
		check(one_q[0] == UVQ_WIDTH'(1) << (UVQ_FRAC_WIDTH - 1),
			"calculate_1q: reciprocal of 2.0 is not 0.5");
		one_q_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		one_q_out_ready = 1'b0;

		param.q = UVQ_WIDTH'(1) << (UVQ_FRAC_WIDTH - 1);
		@(negedge clk);
		one_q_in_valid = 1'b1;
		@(negedge clk);
		one_q_in_valid = 1'b0;
		wait_for_one_q();
		#1;
		check(one_q[0] == UVQ_WIDTH'(2) << UVQ_FRAC_WIDTH,
			"calculate_1q: reciprocal of 0.5 is not 2.0");
		one_q_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		one_q_out_ready = 1'b0;

		// calculate_uv: multiplying by one leaves uq and vq unchanged.
		for (int pixel = 0; pixel < TILE_WIDTH; pixel++) begin
			uv_one_q[pixel] = UVQ_WIDTH'(1) << UVQ_FRAC_WIDTH;
			uv_uq[pixel] = 32'h0040_0000;
			uv_vq[pixel] = 32'h0080_0000;
		end
		@(negedge clk);
		uv_one_q_valid = 1'b1;
		uv_uq_vq_valid = 1'b1;
		@(negedge clk);
		uv_one_q_valid = 1'b0;
		uv_uq_vq_valid = 1'b0;
		while (!uv_out_valid) @(posedge clk);
		#1;
		check(uv_u[0] == 32'h0040_0000 && uv_v[0] == 32'h0080_0000,
			"calculate_uv: fixed-point multiplication mismatch");
		check(uv_triangle_id == 11'd7 && uv_texture_id == 8'd3,
			"calculate_uv: IDs were not preserved");
		uv_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		uv_out_ready = 1'b0;

		// calculate_uv: one_q=0.5 halves both texture coordinates.
		for (int pixel = 0; pixel < TILE_WIDTH; pixel++) begin
			uv_one_q[pixel] = UVQ_WIDTH'(1) << (UVQ_FRAC_WIDTH - 1);
			uv_uq[pixel] = 32'h0040_0000;
			uv_vq[pixel] = 32'h0080_0000;
		end
		@(negedge clk);
		uv_one_q_valid = 1'b1;
		uv_uq_vq_valid = 1'b1;
		@(negedge clk);
		uv_one_q_valid = 1'b0;
		uv_uq_vq_valid = 1'b0;
		while (!uv_out_valid) @(posedge clk);
		#1;
		check(uv_u[0] == 32'h0020_0000 && uv_v[0] == 32'h0040_0000,
			"calculate_uv: half reciprocal mismatch");
		uv_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		uv_out_ready = 1'b0;

		// calculate_uv: signed multiplication keeps the sign of uq and vq.
		for (int pixel = 0; pixel < TILE_WIDTH; pixel++) begin
			uv_one_q[pixel] = UVQ_WIDTH'(1) << (UVQ_FRAC_WIDTH - 1);
			uv_uq[pixel] = -32'sh0040_0000;
			uv_vq[pixel] = -32'sh0080_0000;
		end
		@(negedge clk);
		uv_one_q_valid = 1'b1;
		uv_uq_vq_valid = 1'b1;
		@(negedge clk);
		uv_one_q_valid = 1'b0;
		uv_uq_vq_valid = 1'b0;
		while (!uv_out_valid) @(posedge clk);
		#1;
		check(uv_u[0] == -32'sh0020_0000 && uv_v[0] == -32'sh0040_0000,
			"calculate_uv: signed multiply mismatch");
		uv_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		uv_out_ready = 1'b0;

		// depth_calculation: zero slopes produce one constant depth row.
		param = '0;
		param.z = DEPTH_INTERP_WIDTH'(29'h0123_4000);
		@(negedge clk);
		depth_in_valid = 1'b1;
		@(negedge clk);
		depth_in_valid = 1'b0;
		while (!depth_out_valid) @(posedge clk);
		#1;
		check(depth[0] == 16'h1234 && depth[TILE_WIDTH-1] == 16'h1234,
			"depth_calculation: constant depth mismatch");
		depth_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		depth_out_ready = 1'b0;

		// depth_calculation: a positive x slope increments each pixel depth.
		param = '0;
		param.z = 29'sh010_0000;
		param.dz_dx = 29'sh000_1000;
		@(negedge clk);
		depth_in_valid = 1'b1;
		@(negedge clk);
		depth_in_valid = 1'b0;
		while (!depth_out_valid) @(posedge clk);
		#1;
		check(depth[0] == 16'h0100 && depth[1] == 16'h0101,
			"depth_calculation: positive slope start mismatch");
		check(depth[TILE_WIDTH-1] == 16'h011f,
			"depth_calculation: positive slope end mismatch");
		depth_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		depth_out_ready = 1'b0;

		// depth_calculation: a negative x slope decrements each pixel depth.
		param = '0;
		param.z = 29'sh012_0000;
		param.dz_dx = -29'sh000_1000;
		@(negedge clk);
		depth_in_valid = 1'b1;
		@(negedge clk);
		depth_in_valid = 1'b0;
		while (!depth_out_valid) @(posedge clk);
		#1;
		check(depth[0] == 16'h0120 && depth[1] == 16'h011f,
			"depth_calculation: negative slope start mismatch");
		check(depth[TILE_WIDTH-1] == 16'h0101,
			"depth_calculation: negative slope end mismatch");
		depth_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		depth_out_ready = 1'b0;

		// depth_mask: every new value is greater than the stored value.
		for (int pixel = 0; pixel < TILE_WIDTH; pixel++) begin
			mask_z[pixel] = 16'h0020;
		end
		for (int pixel = 0; pixel < TILE_WIDTH / 2; pixel++) begin
			mask_depth1[DEPTH_WIDTH * pixel +: DEPTH_WIDTH] = 16'h0010;
			mask_depth2[DEPTH_WIDTH * pixel +: DEPTH_WIDTH] = 16'h0010;
		end
		@(negedge clk);
		mask_z_valid = 1'b1;
		mask_depth1_valid = 1'b1;
		mask_depth2_valid = 1'b1;
		@(negedge clk);
		mask_z_valid = 1'b0;
		mask_depth1_valid = 1'b0;
		mask_depth2_valid = 1'b0;
		while (!mask_out_valid) @(posedge clk);
		#1;
		check(depth_mask_out == '1, "depth_mask: expected all pixels to pass");
		check(mask_z_out[0] == 16'h0020, "depth_mask: depth data was not preserved");
		mask_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		mask_out_ready = 1'b0;

		// depth_mask: equal depth fails; only strictly greater pixels pass.
		for (int pixel = 0; pixel < TILE_WIDTH; pixel++) begin
			mask_z[pixel] = pixel[0] ? 16'h0021 : 16'h0020;
		end
		for (int pixel = 0; pixel < TILE_WIDTH / 2; pixel++) begin
			mask_depth1[DEPTH_WIDTH * pixel +: DEPTH_WIDTH] = 16'h0020;
			mask_depth2[DEPTH_WIDTH * pixel +: DEPTH_WIDTH] = 16'h0020;
		end
		@(negedge clk);
		mask_z_valid = 1'b1;
		mask_depth1_valid = 1'b1;
		mask_depth2_valid = 1'b1;
		@(negedge clk);
		mask_z_valid = 1'b0;
		mask_depth1_valid = 1'b0;
		mask_depth2_valid = 1'b0;
		while (!mask_out_valid) @(posedge clk);
		#1;
		for (int pixel = 0; pixel < TILE_WIDTH; pixel++) begin
			check(depth_mask_out[pixel] == pixel[0],
				"depth_mask: strict compare mask mismatch");
		end
		mask_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		mask_out_ready = 1'b0;

		// line_fifo: positive constant edges cover the first complete line.
		param = '0;
		@(negedge clk);
		line_in_valid = 1'b1;
		@(negedge clk);
		line_in_valid = 1'b0;
		while (!line_out_valid) @(posedge clk);
		#1;
		check(line_tile_x == 6'd2 && line_y == 11'd24,
			"line_fifo: first line coordinates mismatch");
		check(line_mask == '1, "line_fifo: expected a fully covered line");
		line_out_ready = 1'b1;
		repeat (10) @(posedge clk);
		line_out_ready = 1'b0;

		// tile_reject: three positive constant edges accept the tile.
		param = '0;
		param.e1 = 28'sd1;
		param.e2 = 28'sd1;
		param.e3 = 28'sd1;
		#1;
		check(!tile_reject_out, "tile_reject: positive tile was rejected");
		check(tile_e1 == 28'sd1 && tile_e2 == 28'sd1 && tile_e3 == 28'sd1,
			"tile_reject: edge values mismatch");

		// tile_reject: one negative constant edge rejects the complete tile.
		param.e1 = -28'sd1;
		#1;
		check(tile_reject_out, "tile_reject: negative tile was accepted");

		// tile_reject: a positive vertical edge slope can make a tile intersect
		// even when the edge value at its upper-left corner is negative.
		param = '0;
		param.e1 = -28'sd1;
		param.dx1 = COORD_WIDTH'(1);
		#1;
		check(!tile_reject_out,
			"tile_reject: tile with a positive maximum was rejected");

		// tile_fifo: retain the complete tile payload while the consumer stalls.
		param = '0;
		param.triangle_id = 11'd21;
		tile_fifo_in_x = 6'd7;
		tile_fifo_in_y = 8'd9;
		tile_fifo_in_e1 = -28'sd11;
		tile_fifo_in_e2 = 28'sd22;
		tile_fifo_in_e3 = 28'sd33;
		tile_fifo_in_reject = 1'b1;
		@(negedge clk);
		tile_fifo_in_valid = 1'b1;
		@(negedge clk);
		tile_fifo_in_valid = 1'b0;
		while (!tile_fifo_out_valid) @(posedge clk);
		#1;
		check(tile_fifo_out_x == 6'd7 && tile_fifo_out_y == 8'd9,
			"tile_fifo: tile coordinates were not preserved");
		check(tile_fifo_out_e1 == -28'sd11 && tile_fifo_out_e2 == 28'sd22
			&& tile_fifo_out_e3 == 28'sd33 && tile_fifo_out_reject,
			"tile_fifo: tile payload was not preserved");
		repeat (2) begin
			@(posedge clk);
			check(tile_fifo_out_valid,
				"tile_fifo: valid payload was not held under backpressure");
		end
		tile_fifo_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		tile_fifo_out_ready = 1'b0;

		// triangle_core: a one-tile bounding box produces exactly that tile.
		param = '0;
		param.triangle_id = 11'd9;
		param.bbox_min_x = 6'd4;
		param.bbox_max_x = 6'd4;
		param.bbox_min_y = 8'd5;
		param.bbox_max_y = 8'd5;
		@(negedge clk);
		core_in_valid = 1'b1;
		@(negedge clk);
		core_in_valid = 1'b0;
		while (!core_out_valid) @(posedge clk);
		#1;
		check(core_tile_x == 6'd4 && core_tile_y == 8'd5,
			"triangle_core: tile coordinates mismatch");
		check(core_param.triangle_id == 11'd9,
			"triangle_core: parameter data was not preserved");
		core_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		core_out_ready = 1'b0;

		// triangle_core: a two-tile box walks left to right.
		param = '0;
		param.bbox_min_x = 6'd2;
		param.bbox_max_x = 6'd3;
		param.bbox_min_y = 8'd4;
		param.bbox_max_y = 8'd4;
		@(negedge clk);
		core_in_valid = 1'b1;
		@(negedge clk);
		core_in_valid = 1'b0;
		while (!core_out_valid) @(posedge clk);
		#1;
		check(core_tile_x == 6'd2 && core_tile_y == 8'd4,
			"triangle_core: first tile of row mismatch");
		core_out_ready = 1'b1;
		@(posedge clk);
		#1;
		check(core_out_valid && core_tile_x == 6'd3 && core_tile_y == 8'd4,
			"triangle_core: second tile of row mismatch");
		@(posedge clk);
		@(negedge clk);
		core_out_ready = 1'b0;

		// triangle_core: a two-by-two bounding box advances across a row before
		// moving to the next row.
		param = '0;
		param.bbox_min_x = 6'd6;
		param.bbox_max_x = 6'd7;
		param.bbox_min_y = 8'd10;
		param.bbox_max_y = 8'd11;
		@(negedge clk);
		core_in_valid = 1'b1;
		@(negedge clk);
		core_in_valid = 1'b0;
		while (!core_out_valid) @(posedge clk);
		#1;
		check(core_tile_x == 6'd6 && core_tile_y == 8'd10,
			"triangle_core: two-by-two first tile mismatch");
		core_out_ready = 1'b1;
		@(posedge clk);
		#1;
		check(core_out_valid && core_tile_x == 6'd7 && core_tile_y == 8'd10,
			"triangle_core: two-by-two second tile mismatch");
		@(posedge clk);
		#1;
		check(core_out_valid && core_tile_x == 6'd6 && core_tile_y == 8'd11,
			"triangle_core: two-by-two third tile mismatch");
		@(posedge clk);
		#1;
		check(core_out_valid && core_tile_x == 6'd7 && core_tile_y == 8'd11,
			"triangle_core: two-by-two fourth tile mismatch");
		@(posedge clk);
		@(negedge clk);
		core_out_ready = 1'b0;

		// triangle_param: one visible right triangle with constant attributes.
		triangle = '0;
		triangle.triangle_id = 11'd12;
		triangle.fbid_color = 2'd1;
		triangle.fbid_depth = 2'd2;
		triangle.ax = 14'sd0;
		triangle.ay = 14'sd0;
		triangle.bx = 14'sd32;
		triangle.by = 14'sd0;
		triangle.cx = 14'sd0;
		triangle.cy = 14'sd8;
		triangle.az = 16'h1000;
		triangle.bz = 16'h1000;
		triangle.cz = 16'h1000;
		triangle.aq = UVQ_WIDTH'(1) << UVQ_FRAC_WIDTH;
		triangle.bq = UVQ_WIDTH'(1) << UVQ_FRAC_WIDTH;
		triangle.cq = UVQ_WIDTH'(1) << UVQ_FRAC_WIDTH;
		@(negedge clk);
		triangle_in_valid = 1'b1;
		@(negedge clk);
		triangle_in_valid = 1'b0;
		while (!texture_id_response_ready) @(posedge clk);
		@(negedge clk);
		texture_id_response_valid = 1'b1;
		@(negedge clk);
		texture_id_response_valid = 1'b0;
		wait_for_triangle_param();
		#1;
		check(triangle_param_out.triangle_id == 11'd12,
			"triangle_param: triangle ID mismatch");
		check(triangle_param_out.texture_id == 8'd5,
			"triangle_param: texture ID mismatch");
		check(triangle_param_out.bbox_min_x == 0
			&& triangle_param_out.bbox_max_x == 1
			&& triangle_param_out.bbox_min_y == 0
			&& triangle_param_out.bbox_max_y == 1,
			"triangle_param: bounding box mismatch");
		triangle_param_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		triangle_param_ready = 1'b0;

		// triangle_param: a triangle crossing the left edge clamps its tile box.
		triangle = '0;
		triangle.triangle_id = 11'd13;
		triangle.ax = -14'sd8;
		triangle.ay = 14'sd0;
		triangle.bx = 14'sd16;
		triangle.by = 14'sd0;
		triangle.cx = -14'sd8;
		triangle.cy = 14'sd16;
		triangle.az = 16'h2000;
		triangle.bz = 16'h2400;
		triangle.cz = 16'h2200;
		triangle.aq = UVQ_WIDTH'(1) << UVQ_FRAC_WIDTH;
		triangle.bq = UVQ_WIDTH'(1) << UVQ_FRAC_WIDTH;
		triangle.cq = UVQ_WIDTH'(1) << UVQ_FRAC_WIDTH;
		@(negedge clk);
		triangle_in_valid = 1'b1;
		@(negedge clk);
		triangle_in_valid = 1'b0;
		while (!texture_id_response_ready) @(posedge clk);
		@(negedge clk);
		texture_id_response = 8'd6;
		texture_id_response_valid = 1'b1;
		@(negedge clk);
		texture_id_response_valid = 1'b0;
		wait_for_triangle_param();
		#1;
		check(triangle_param_out.triangle_id == 11'd13,
			"triangle_param: clipped triangle ID mismatch");
		check(triangle_param_out.texture_id == 8'd6,
			"triangle_param: clipped texture ID mismatch");
		check(triangle_param_out.bbox_min_x == 0
			&& triangle_param_out.bbox_max_x == 0
			&& triangle_param_out.bbox_min_y == 0
			&& triangle_param_out.bbox_max_y == 2,
			"triangle_param: clipped bounding box mismatch");
		triangle_param_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		triangle_param_ready = 1'b0;

		// uq_vq_calculation: zero derivatives produce constant rows.
		param = '0;
		param.triangle_id = 11'd15;
		param.texture_id = 8'd6;
		param.uq = 32'h0010_0000;
		param.vq = 32'h0020_0000;
		@(negedge clk);
		uq_vq_in_valid = 1'b1;
		@(negedge clk);
		uq_vq_in_valid = 1'b0;
		while (!uq_vq_out_valid) @(posedge clk);
		#1;
		check(uq_out[0] == 32'h0010_0000 && uq_out[TILE_WIDTH-1] == 32'h0010_0000,
			"uq_vq_calculation: uq row mismatch");
		check(vq_out[0] == 32'h0020_0000 && vq_out[TILE_WIDTH-1] == 32'h0020_0000,
			"uq_vq_calculation: vq row mismatch");
		check(uq_vq_triangle_id == 11'd15 && uq_vq_texture_id == 8'd6,
			"uq_vq_calculation: IDs were not preserved");
		uq_vq_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		uq_vq_out_ready = 1'b0;

		// uq_vq_calculation: x derivatives change values across a line.
		param = '0;
		param.uq = 32'h0010_0000;
		param.duq_dx = 32'sh0000_1000;
		param.vq = 32'h0020_0000;
		param.dvq_dx = -32'sh0000_2000;
		@(negedge clk);
		uq_vq_in_valid = 1'b1;
		@(negedge clk);
		uq_vq_in_valid = 1'b0;
		while (!uq_vq_out_valid) @(posedge clk);
		#1;
		check(uq_out[0] == 32'h0010_0000 && uq_out[1] == 32'h0010_1000,
			"uq_vq_calculation: uq x slope mismatch");
		check(vq_out[0] == 32'h0020_0000 && vq_out[1] == 32'h001f_e000,
			"uq_vq_calculation: vq x slope mismatch");
		check(uq_out[TILE_WIDTH-1] == 32'h0011_f000,
			"uq_vq_calculation: uq x slope end mismatch");
		uq_vq_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		uq_vq_out_ready = 1'b0;

		// uq_vq_calculation: tile X and Y offsets affect the row origin.
		param = '0;
		param.uq = '0;
		param.duq_dx = 32'sh0000_1000;
		param.duq_dy = 32'sh0000_2000;
		param.vq = 32'h0010_0000;
		param.dvq_dy = -32'sh0000_1000;
		uq_vq_tile_x = 6'd1;
		uq_vq_y = 11'd2;
		@(negedge clk);
		uq_vq_in_valid = 1'b1;
		@(negedge clk);
		uq_vq_in_valid = 1'b0;
		while (!uq_vq_out_valid) @(posedge clk);
		#1;
		check(uq_out[0] == 32'h0002_4000,
			"uq_vq_calculation: tile and row uq origin mismatch");
		check(vq_out[0] == 32'h000f_e000,
			"uq_vq_calculation: tile and row vq origin mismatch");
		check(uq_out[1] == 32'h0002_5000,
			"uq_vq_calculation: tile uq slope mismatch");
		uq_vq_out_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		uq_vq_out_ready = 1'b0;

		if (errcnt == 0) begin
			$display("### TESTS PASSED ###");
		end else begin
			$display("### TESTS FAILED: %0d errors ###", errcnt);
		end
		$finish;
	end

	initial begin
		repeat (1000) @(posedge clk);
		$fatal(1, "rasterizer_simple_tb timeout");
	end

endmodule
