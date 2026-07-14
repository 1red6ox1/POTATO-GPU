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
  import rasterizer_pkg::*;

  logic [7:0] led;
  logic       tmds_clk;
  logic [2:0] tmds;

  localparam int N = 5;

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

  triangle2d_t triangle2d;
  logic triangle2d_ready, triangle2d_valid;
  rasterization_param_t raster_param;
  logic raster_param_ready, raster_param_valid;
  rasterization_param_t raster_core_param;
  logic [$clog2(FRAME_WIDTH / TILE_WIDTH)-1:0] raster_core_tile_x;
  logic [$clog2(FRAME_HEIGHT)-1:0] raster_core_y;
  logic raster_core_valid;
  logic raster_core_ready;

  rasterization_param_t raster_worker_param;
  logic [$clog2(FRAME_WIDTH / TILE_WIDTH)-1:0] raster_worker_tile_x;
  logic [$clog2(FRAME_HEIGHT)-1:0] raster_worker_y;
  logic raster_worker_valid;
  logic raster_worker_ready;
  rvlab_ddr_pkg::ddr3_h2d_t worker_ddr_reqs [2:0];
  rvlab_ddr_pkg::ddr3_d2h_t worker_ddr_rsps [2:0];

  assign xbar_reqs[3] = worker_ddr_reqs[0];
  assign xbar_reqs[4] = worker_ddr_reqs[1];
  assign xbar_reqs[5] = worker_ddr_reqs[2];
  assign worker_ddr_rsps[0] = xbar_rsps[3];
  assign worker_ddr_rsps[1] = xbar_rsps[4];
  assign worker_ddr_rsps[2] = xbar_rsps[5];

  triangle2d_input triangle2d_input_i (
    .clk_i,
    .rst_ni,
    .tl_i       (tl_devices_h2d[4]),
    .tl_o       (tl_devices_d2h[4]),
    .triangle2d_o(triangle2d),
    .out_ready_i(triangle2d_ready),
    .out_valid_o(triangle2d_valid)
  );

  rasterizer_param rasterizer_param_i (
    .clk_i,
    .rst_ni,
    .triangle2d_i(triangle2d),
    .in_valid_i  (triangle2d_valid),
    .in_ready_o  (triangle2d_ready),
    .param_o     (raster_param),
    .out_valid_o (raster_param_valid),
    .out_ready_i (raster_param_ready)
  );

  rasterizer_core rasterizer_core_i (
    .clk_i,
    .rst_ni,
    .param_i    (raster_param),
    .in_valid_i (raster_param_valid),
    .in_ready_o (raster_param_ready),
    .param_o    (raster_core_param),
    .tile_x_o   (raster_core_tile_x),
    .y_o        (raster_core_y),
    .out_valid_o(raster_core_valid),
    .out_ready_i(raster_core_ready)
  );

  core_fifo core_fifo_i (
    .clk_i,
    .rst_ni,
    .clear_i    (1'b0),
    .param_i    (raster_core_param),
    .tile_x_i   (raster_core_tile_x),
    .y_i        (raster_core_y),
    .in_valid_i (raster_core_valid),
    .in_ready_o (raster_core_ready),
    .param_o    (raster_worker_param),
    .tile_x_o   (raster_worker_tile_x),
    .y_o        (raster_worker_y),
    .out_valid_o(raster_worker_valid),
    .out_ready_i(raster_worker_ready),
    .depth_o    ()
  );

  worker worker_i (
    .clk_i,
    .rst_ni,
    .param_i    (raster_worker_param),
    .tile_x_i   (raster_worker_tile_x),
    .y_i        (raster_worker_y),
    .in_valid_i (raster_worker_valid),
    .in_ready_o (raster_worker_ready),
    .ddr_o      (worker_ddr_reqs),
    .ddr_i      (worker_ddr_rsps)
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

  /* Fixed-function rasterization pipeline */

  logic                         vertex_out_valid;
  logic                         vertex_out_ready;
  logic [9:0]                   vertex_out_id;
  logic signed [31:0]           vertex_out_vec [3:0];
  logic                         vertex_post_in_valid;
  logic                         vertex_post_ready;
  logic [9:0]                   vertex_post_in_id;
  logic signed [31:0]           vertex_post_x [2:0];
  logic signed [31:0]           vertex_post_y [2:0];
  logic signed [31:0]           vertex_post_z [2:0];
  logic signed [31:0]           vertex_post_w [2:0];
  logic                         vertex_post_out_valid;
  logic [10:0]                  vertex_post_sx [2:0];
  logic [10:0]                  vertex_post_sy [2:0];
  logic signed [31:0]           vertex_post_ndc_z [2:0];
  logic signed [31:0]           vertex_post_inv_w [2:0];
  (* mark_debug = "true" *)
  logic [138:0]                 vertex_debug;

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

    .tl_cfg_i(tl_devices_h2d[4]),
    .tl_cfg_o(tl_devices_d2h[4]),
    .tl_vec_i(tl_devices_h2d[5]),
    .tl_vec_o(tl_devices_d2h[5]),

    .out_valid_o(vertex_out_valid),
    .out_ready_i(vertex_out_ready),
    .out_id_o   (vertex_out_id),
    .out_vec_o  (vertex_out_vec)
  );

  vertex_triangle_collector vertex_triangle_collector_i (
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
    .clk      (clk_i),
    .rst_n    (rst_ni),
    .in_valid (vertex_post_in_valid),
    .ready_o  (vertex_post_ready),
    .x_i      (vertex_post_x),
    .y_i      (vertex_post_y),
    .z_i      (vertex_post_z),
    .w_i      (vertex_post_w),
    .out_valid(vertex_post_out_valid),
    .sx_o     (vertex_post_sx),
    .sy_o     (vertex_post_sy),
    .z_o      (vertex_post_ndc_z),
    .inv_w_o  (vertex_post_inv_w)
  );
  
`ifndef SYNTHESIS
  int framebuffer_log_fd;

  initial begin
    framebuffer_log_fd = $fopen("log.csv", "w");
  end

  always @(posedge clk_i) begin
    for (int host = 0; host < DDR_XBAR_N; host++) begin
      if (framebuffer_log_fd != 0
          && xbar_reqs[host].a_valid
          && xbar_rsps[host].a_ready
          && xbar_reqs[host].a_opcode inside {PutFullData, PutPartialData}
          && xbar_reqs[host].a_address[23:21] == 3'b000) begin
        $fdisplay(framebuffer_log_fd, "color,%0t,%0d,%h,%h,%h",
                  $time,
                  host,
                  xbar_reqs[host].a_address,
                  xbar_reqs[host].a_mask,
                  xbar_reqs[host].a_data);
      end
    end
  end

  final begin
    if (framebuffer_log_fd != 0) begin
      $fclose(framebuffer_log_fd);
    end
  end
`endif

endmodule
