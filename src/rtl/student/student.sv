// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2024 RVLab Contributors

module student (
  input logic clk_i,
  input logic clk_100mhz_i,
  input logic rst_ni,

  input  top_pkg::userio_board2fpga_t userio_i,
  output top_pkg::userio_fpga2board_t userio_o,

  output logic irq_o,

  input  tlul_pkg::tl_h2d_t tl_device_peri_i,
  output tlul_pkg::tl_d2h_t tl_device_peri_o,
  input  tlul_pkg::tl_h2d_t tl_device_fast_i,
  output tlul_pkg::tl_d2h_t tl_device_fast_o,

  input  tlul_pkg::tl_d2h_t tl_host_i,
  output tlul_pkg::tl_h2d_t tl_host_o,

  input  tlul_pkg::tl_h2d_t tl_ddr_i,
  output tlul_pkg::tl_d2h_t tl_ddr_o,
  output rvlab_ddr_pkg::ddr3_h2d_t ddr_o,
  input  rvlab_ddr_pkg::ddr3_d2h_t ddr_i
);
  import tlul_pkg::*;

  logic [7:0] led;
  logic       tmds_clk;
  logic [2:0] tmds;

  localparam int N = 12;

  tl_h2d_t tl_devices_h2d [N-1:0];
  tl_d2h_t tl_devices_d2h [N-1:0];

  logic [31:0] irq_signals;
  logic        irq_left, irq_right;

  assign irq_signals = {30'h0, irq_left, irq_right};

  assign userio_o = '{
    led: led,
    hdmi_tx_clk: tmds_clk,
    hdmi_tx: tmds,
    default: '0
  };

  student_tlul_mux #(.N(N)) tlul_mux_i (
    .clk_i,
    .rst_ni,
    .tl_host_o (tl_device_peri_o),
    .tl_host_i (tl_device_peri_i),
    .tl_device_o (tl_devices_h2d),
    .tl_device_i (tl_devices_d2h) 
  );

  student_rlight rlight_i (
    .clk_i,
    .rst_ni,
    .tl_o       (tl_devices_d2h[0]),
    .tl_i       (tl_devices_h2d[0]),
    .irq_left_o (irq_left),
    .irq_right_o(irq_right),
    .led_o      (led)
  );
    student_dma dma_i (
    .clk_i,
    .rst_ni,
    .tl_o (tl_device_fast_o),
    .tl_i (tl_device_fast_i),
    .tl_host_o,
    .tl_host_i
  );

  student_irq_ctrl irq_ctrl_i (
    .clk_i,
    .rst_ni,
    .tl_o  (tl_devices_d2h[1]),
    .tl_i  (tl_devices_h2d[1]),
    .irq_i (irq_signals),
    .irq_o (irq_o)
  );

  localparam int DDR_XBAR_N = 6;

  rvlab_ddr_pkg::ddr3_h2d_t xbar_reqs [DDR_XBAR_N-1:0];
  rvlab_ddr_pkg::ddr3_d2h_t xbar_rsps [DDR_XBAR_N-1:0];

  rvlab_hdmi hdmi_i (
    .clk_100mhz_i,
    .sys_clk_i   (clk_i),
    .sys_rst_ni  (rst_ni),
    .hpd_i       (userio_i.hdmi_tx_hpd),
    .tl_i        (tl_devices_h2d[2]),
    .tl_o        (tl_devices_d2h[2]),

    .clk_tmds_o  (tmds_clk),
    .tmds_o      (tmds),

    .ddr_o       (xbar_reqs[0]),
    .ddr_i       (xbar_rsps[0])
  );

  frameclear_dma frameclear_dma_i (
    .clk_i,
    .rst_ni,
    .tl_i  (tl_devices_h2d[3]),
    .tl_o  (tl_devices_d2h[3]),
    .ddr_o (xbar_reqs[2]),
    .ddr_i (xbar_rsps[2])
  );

  rasterizer_pkg::triangle_t software_triangle;
  rasterizer_pkg::triangle_t vertex_triangle;
  rasterizer_pkg::triangle_t triangle;
  rasterizer_pkg::triangle_param_t triangle_param;
  logic software_triangle_valid;
  logic software_triangle_ready;
  logic vertex_triangle_valid;
  logic vertex_triangle_ready;
  logic triangle_valid;
  logic triangle_ready;
  logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0] texture_triangle_id;
  logic texture_triangle_id_valid;
  logic texture_triangle_id_ready;
  logic [rasterizer_pkg::TEXTURE_ID_WIDTH-1:0] texture_id;
  logic texture_id_valid;
  logic texture_id_ready;
  logic [1:0] vertex_fbid_color;
  logic [1:0] vertex_fbid_depth;
  logic triangle_param_valid;
  logic triangle_param_ready;
	logic signed [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x;
	logic signed [rasterizer_pkg::TILE_Y_WIDTH-1:0] tile_y;
	rasterizer_pkg::triangle_param_t tile_param;
	logic tile_valid;
	logic tile_ready;
	logic tile_reject;
	logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] tile_e1;
	logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] tile_e2;
	logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] tile_e3;

	logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_fifo_x;
	logic [rasterizer_pkg::TILE_Y_WIDTH-1:0] tile_fifo_y;
	rasterizer_pkg::triangle_param_t tile_fifo_param;
	logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] tile_fifo_e1;
	logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] tile_fifo_e2;
	logic signed [rasterizer_pkg::EDGE_WIDTH-1:0] tile_fifo_e3;
	logic tile_fifo_reject;
	logic tile_fifo_valid;
	logic tile_fifo_ready;

	logic [rasterizer_pkg::TILE_X_WIDTH-1:0] line_tile_x;
	logic [rasterizer_pkg::FRAME_Y_WIDTH-1:0] line_y;
	rasterizer_pkg::triangle_param_t line_param;
	logic [rasterizer_pkg::TILE_WIDTH-1:0] line_mask;
	logic line_valid;
	logic line_fifo_in_ready;
	logic line_fifo_out_ready;

	logic [1:0] fbid_color;
	logic [1:0] fbid_depth;
	logic [rasterizer_pkg::TRIANGLE_ID_WIDTH-1:0] triangle_id;
	logic [rasterizer_pkg::TILE_X_WIDTH-1:0] worker_tile_x;
	logic [rasterizer_pkg::FRAME_Y_WIDTH-1:0] worker_y;
	logic [255:0] worker_red;
	logic [255:0] worker_green;
	logic [255:0] worker_blue;
	logic [255:0] worker_depth1;
	logic [255:0] worker_depth2;
	logic [rasterizer_pkg::TILE_WIDTH-1:0] worker_mask;
	logic worker_valid;
	logic worker_ready;
	logic rasterizer_writer_valid;
	logic rasterizer_writer_ready;
	logic writer_busy;

  triangle_input triangle_input_i (
    .clk_i,
    .rst_ni,
    .tl_i       (tl_devices_h2d[4]),
	    .tl_o       (tl_devices_d2h[4]),
	    .fbid_color_o(vertex_fbid_color),
	    .fbid_depth_o(vertex_fbid_depth),
	    .triangle_o (software_triangle),
	    .out_valid_o(software_triangle_valid),
	    .out_ready_i(software_triangle_ready)
  );

  assign triangle = vertex_triangle_valid ? vertex_triangle : software_triangle;
  assign triangle_valid = vertex_triangle_valid || software_triangle_valid;
  assign vertex_triangle_ready = triangle_ready;
  assign software_triangle_ready = triangle_ready && !vertex_triangle_valid;

  load_texture load_texture_i (
    .clk_i,
    .rst_ni,
    .tl_i       (tl_devices_h2d[7]),
    .tl_o       (tl_devices_d2h[7]),
    .triangle_id_i(texture_triangle_id),
    .in_valid_i (texture_triangle_id_valid),
    .in_ready_o (texture_triangle_id_ready),
    .texture_id_o(texture_id),
    .out_valid_o(texture_id_valid),
    .out_ready_i(texture_id_ready)
  );

  triangle_param triangle_param_i (
    .clk_i,
    .rst_ni,
    .triangle_i (triangle),
    .in_valid_i (triangle_valid),
    .in_ready_o (triangle_ready),
    .param_o    (triangle_param),
    .out_valid_o(triangle_param_valid),
    .out_ready_i(triangle_param_ready),
    .triangle_id_o(texture_triangle_id),
    .id_out_valid_o(texture_triangle_id_valid),
    .id_out_ready_i(texture_triangle_id_ready),
    .texture_id_i(texture_id),
    .id_in_valid_i(texture_id_valid),
    .id_in_ready_o(texture_id_ready)
  );

  triangle_core triangle_core_i (
    .clk_i,
    .rst_ni,
    .param_i     (triangle_param),
    .in_valid_i  (triangle_param_valid),
	  .in_ready_o  (triangle_param_ready),
	  .tile_x_o    (tile_x),
	  .tile_y_o    (tile_y),
		  .param_o     (tile_param),
		  .out_valid_o (tile_valid),
		  .out_ready_i (tile_ready)
	  );

	tile_reject tile_reject_i (
		.param_i  (tile_param),
		.tile_x_i (tile_x),
		.tile_y_i (tile_y),
		.reject_o (tile_reject),
		.e1_o     (tile_e1),
		.e2_o     (tile_e2),
		.e3_o     (tile_e3)
	);

	tile_fifo tile_fifo_i (
		.clk_i,
		.rst_ni,
		.tile_x_i    (tile_x),
		.tile_y_i    (tile_y),
		.param_i     (tile_param),
		.e1_i        (tile_e1),
		.e2_i        (tile_e2),
		.e3_i        (tile_e3),
		.reject_i     (tile_reject),
		.in_valid_i   (tile_valid),
		.in_ready_o   (tile_ready),
		.tile_x_o     (tile_fifo_x),
		.tile_y_o     (tile_fifo_y),
		.param_o      (tile_fifo_param),
		.e1_o         (tile_fifo_e1),
		.e2_o         (tile_fifo_e2),
		.e3_o         (tile_fifo_e3),
		.reject_o     (tile_fifo_reject),
		.out_valid_o  (tile_fifo_valid),
		.out_ready_i  (tile_fifo_ready)
	);

	assign tile_fifo_ready = tile_fifo_reject || line_fifo_in_ready;

	line_fifo line_fifo_i (
		.clk_i,
		.rst_ni,
		.tile_x_i    (tile_fifo_x),
		.tile_y_i    (tile_fifo_y),
		.param_i     (tile_fifo_param),
		.e1_i        (tile_fifo_e1),
		.e2_i        (tile_fifo_e2),
		.e3_i        (tile_fifo_e3),
		.in_valid_i  (tile_fifo_valid && !tile_fifo_reject),
		.in_ready_o  (line_fifo_in_ready),
		.tile_x_o    (line_tile_x),
		.y_o         (line_y),
		.param_o     (line_param),
		.mask_o      (line_mask),
		.out_valid_o (line_valid),
		.out_ready_i (line_fifo_out_ready)
	);

	worker worker_i (
		.clk_i,
		.rst_ni,
		.param_i         (line_param),
		.tile_x_i        (line_tile_x),
		.y_i             (line_y),
		.coverage_mask_i (line_mask),
		.in_valid_i      (line_valid),
		.in_ready_o      (line_fifo_out_ready),
		.fbid_color_o    (fbid_color),
		.fbid_depth_o    (fbid_depth),
		.triangle_id_o   (triangle_id),
		.tile_x_o        (worker_tile_x),
		.y_o             (worker_y),
		.red_o           (worker_red),
		.green_o         (worker_green),
		.blue_o          (worker_blue),
		.depth1_o        (worker_depth1),
		.depth2_o        (worker_depth2),
		.mask_o          (worker_mask),
		.out_valid_o     (worker_valid),
		.out_ready_i     (worker_ready),
    .tl_tex_i        (tl_devices_h2d[9]),
    .tl_tex_o        (tl_devices_d2h[9]),
    .tl_palette_i    (tl_devices_h2d[10]),
    .tl_palette_o    (tl_devices_d2h[10]),
		.ddr1_o          (xbar_reqs[3]),
		.ddr1_i          (xbar_rsps[3]),
		.ddr2_o          (xbar_reqs[4]),
		.ddr2_i          (xbar_rsps[4])
	);

	rasterizer_status rasterizer_status_i (
		.clk_i,
		.rst_ni,
		.tl_i          (tl_devices_h2d[8]),
		.tl_o          (tl_devices_d2h[8]),
		.triangle_id_i (triangle_id),
		.in_valid_i    (worker_valid),
		.in_ready_o    (worker_ready),
		.out_valid_o   (rasterizer_writer_valid),
		.out_ready_i   (rasterizer_writer_ready),
		.writer_busy_i (writer_busy)
	);

	writer writer_i (
		.clk_i,
		.rst_ni,
		.fbid_color_i (fbid_color),
		.fbid_depth_i (fbid_depth),
		.tile_x_i     (worker_tile_x),
		.y_i          (worker_y),
		.red_i        (worker_red),
		.green_i      (worker_green),
		.blue_i       (worker_blue),
		.depth1_i     (worker_depth1),
		.depth2_i     (worker_depth2),
		.mask_i       (worker_mask),
		.in_valid_i   (rasterizer_writer_valid),
		.in_ready_o   (rasterizer_writer_ready),
		.busy_o       (writer_busy),
		.ddr_o        (xbar_reqs[5]),
		.ddr_i        (xbar_rsps[5])
	);

  /* Fixed-function vertex processing pipeline */

  logic                         vertex_out_valid;
  logic                         vertex_out_ready;
  logic [10:0]                  vertex_out_id;
  logic signed [31:0]           vertex_out_vec [3:0];
  logic                         vertex_post_in_valid;
  logic                         vertex_post_ready;
  logic [10:0]                  vertex_post_in_id;
  logic signed [31:0]           vertex_post_x [2:0];
  logic signed [31:0]           vertex_post_y [2:0];
  logic signed [31:0]           vertex_post_z [2:0];
  logic signed [31:0]           vertex_post_w [2:0];
  logic                         vertex_post_out_valid;
  logic [10:0]                  vertex_post_sx [2:0];
  logic [10:0]                  vertex_post_sy [2:0];
  logic signed [31:0]           vertex_post_ndc_z [2:0];
  logic signed [31:0]           vertex_post_inv_w [2:0];
  logic [10:0]                  vertex_post_triangle_id;
  logic                         vertex_post_to_triangle2d_ready;
  (* mark_debug = "true" *)
  logic [139:0]                 vertex_debug;

  assign vertex_debug = {
    vertex_out_valid,
    vertex_out_id,
    vertex_out_vec[0],
    vertex_out_vec[1],
    vertex_out_vec[2],
    vertex_out_vec[3]
  };

  vertex_processor vertex_processor_i (
    .clk_i,
    .rst_ni,

    .tl_cfg_i(tl_devices_h2d[5]),
    .tl_cfg_o(tl_devices_d2h[5]),
    .tl_vec_i(tl_devices_h2d[6]),
    .tl_vec_o(tl_devices_d2h[6]),

    .out_valid_o(vertex_out_valid),
    .out_ready_i(vertex_out_ready),
    .out_id_o   (vertex_out_id),
    .out_vec_o  (vertex_out_vec)
  );

  vertex_triangle_collector #(
    .TRI_ID_WIDTH(11)
  ) vertex_triangle_collector_i (
    .clk_i,
    .rst_ni,

    .in_valid_i (vertex_out_valid),
    .in_ready_o (vertex_out_ready),
    .in_id_i    (vertex_out_id),
    .in_vec_i   (vertex_out_vec),

    .out_valid_o(vertex_post_in_valid),
    .out_ready_i(vertex_post_ready),
    .out_id_o   (vertex_post_in_id),
    .out_x_o    (vertex_post_x),
    .out_y_o    (vertex_post_y),
    .out_z_o    (vertex_post_z),
    .out_w_o    (vertex_post_w)
  );

  vertex_post vertex_post_i (
    .clk        (clk_i),
    .rst_n      (rst_ni),
    .in_valid   (vertex_post_in_valid),
    .ready_o    (vertex_post_ready),
    .x_i        (vertex_post_x),
    .y_i        (vertex_post_y),
    .z_i        (vertex_post_z),
    .w_i        (vertex_post_w),
    .tri_id_i   (vertex_post_in_id),
    .out_valid  (vertex_post_out_valid),
    .out_ready_i(vertex_post_to_triangle2d_ready),
    .sx_o       (vertex_post_sx),
    .sy_o       (vertex_post_sy),
    .z_o        (vertex_post_ndc_z),
    .inv_w_o    (vertex_post_inv_w),
    .tri_id_o   (vertex_post_triangle_id)
  );

  vertex_post_to_triangle2d #(
    .FIFO_DEPTH(16)
  ) vertex_post_to_triangle2d_i (
    .clk_i,
    .rst_ni,
    .in_ready_o  (vertex_post_to_triangle2d_ready),
    .in_valid_i  (vertex_post_out_valid),
    .triangle_id_i(vertex_post_triangle_id),
    .sx_i        (vertex_post_sx),
    .sy_i        (vertex_post_sy),
    .z_i         (vertex_post_ndc_z),
    .inv_w_i     (vertex_post_inv_w),
    .fbid_color_i(vertex_fbid_color),
    .fbid_depth_i(vertex_fbid_depth),
    .triangle_o  (vertex_triangle),
    .out_valid_o (vertex_triangle_valid),
    .out_ready_i (vertex_triangle_ready),
    .tl_i        (tl_devices_h2d[11]),
    .tl_o        (tl_devices_d2h[11])
  );

  /* Cache / DDR3 system */

  rvlab_ddr_pkg::ddr3_h2d_t prefetcher_req;
  rvlab_ddr_pkg::ddr3_d2h_t prefetcher_rsp;

  rvlab_ddr_cache #(
    .IDX_BITS(9)
  ) ddr_llc_i (
    .clk_i,
    .rst_ni,

    .tl_i(tl_ddr_i),
    .tl_o(tl_ddr_o),

    .block_req_o(prefetcher_req),
    .block_rsp_i(prefetcher_rsp)
  );

  /* Prefetcher */

  rvlab_ddr_prefetch prefetcher_i (
    .clk_i,
    .rst_ni,

    .fe_req_i(prefetcher_req),
    .fe_rsp_o(prefetcher_rsp),

    .be_req_o(xbar_reqs[1]),
    .be_rsp_i(xbar_rsps[1])
  );

  rvlab_ddr_mux #(
    .N               (DDR_XBAR_N),
    .MAX_OUTSTANDING (32)
  ) ddr_xbar_i (
    .clk_i,
    .rst_ni,
    .host_i(xbar_reqs),
    .host_o(xbar_rsps),
    .dev_o (ddr_o),
    .dev_i (ddr_i)
  );

endmodule
