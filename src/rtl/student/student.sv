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

  localparam int DDR_XBAR_N = 3;

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
    .N(DDR_XBAR_N)
  ) ddr_xbar_i (
    .clk_i,
    .rst_ni,
    .host_i(xbar_reqs),
    .host_o(xbar_rsps),
    .dev_o (ddr_o),
    .dev_i (ddr_i)
  );

  /* Fixed-function rasterization pipeline */

  matmul matmul_i (
    .clk_i,
    .rst_ni,

    .tl_ctrl_i(tl_devices_h2d[4]),
    .tl_ctrl_o(tl_devices_d2h[4]),

    .data_i   ('{default: '0}),
    .data_o   (),

    .valid_i  (1'b0),
    .id_i     ('0),
    .ready_o  (),
    .valid_o  (),
    .id_o     (),
    .ready_i  (1'b1)
  );

endmodule
