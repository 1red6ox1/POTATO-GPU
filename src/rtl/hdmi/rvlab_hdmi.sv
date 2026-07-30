// Copyright David Schröder 2026.

module rvlab_hdmi (
	input  logic clk_100mhz_i,
	input  logic sys_clk_i,
	input  logic sys_rst_ni,

	input  logic hpd_i,

	input  tlul_pkg::tl_h2d_t tl_i,
	output tlul_pkg::tl_d2h_t tl_o,

	output logic       clk_tmds_o,
	output logic [2:0] tmds_o,

	output rvlab_ddr_pkg::ddr3_h2d_t ddr_o,
	input  rvlab_ddr_pkg::ddr3_d2h_t ddr_i
);

	import tlul_pkg::*;
	import hdmi_ctrl_reg_pkg::*;

	/* Clocking */

	logic clk_pixel, clk_fast, rst_n;

	hdmi_clkmgr clkmgr_i (
		.clk_100mhz_i,
		.sys_rst_ni,
		.rst_no      (rst_n),
		.clk_pixel_o (clk_pixel),
		.clk_fast_o  (clk_fast)
	);

	/* Registers + CDC */

	hdmi_ctrl_reg2hw_t reg2hw;
	hdmi_ctrl_hw2reg_t hw2reg;

	hdmi_ctrl_reg_top ctrl_i (
		.clk_i    (sys_clk_i),
		.rst_ni   (sys_rst_ni),
		.tl_i     (tl_i),
		.tl_o     (tl_o),
		.reg2hw   (reg2hw),
		.hw2reg   (hw2reg),
		.devmode_i('1)
	);

	logic [1:0] next_fbid;
	logic phy_enable, prefetcher_enable;
	logic hpd_sync;

	/* HDMI -> SYS */

	prim_flop_2sync #( .Width(1) ) hpd_sync_i (
		.clk_i (sys_clk_i),
		.rst_ni(sys_rst_ni),
		.q     (hpd_sync),
		.d     (hpd_i)
	);

	/* SYS -> HDMI */

	prim_flop_2sync #( .Width(1) ) prefetch_en_sync_i (
		.clk_i (clk_pixel),
		.rst_ni(rst_n),
		.d     (reg2hw.ctrl.fetch_enable.q),
		.q     (prefetcher_enable)
	);

	prim_flop_2sync #( .Width(1) ) phy_en_sync_i (
		.clk_i (clk_pixel),
		.rst_ni(rst_n),
		.d     (reg2hw.ctrl.phy_enable.q),
		.q     (phy_enable)
	);

	prim_flop_2sync #( .Width(2) ) fbid_sync_i (
		.clk_i (clk_pixel),
		.rst_ni(rst_n),
		.d     (reg2hw.fbid.q),
		.q     (next_fbid)
	);

	assign hw2reg.hpd.d = hpd_sync;
	assign hw2reg.hpd.de = '1;

	rvlab_ddr_pkg::ddr3_h2d_t fetcher_req;
	rvlab_ddr_pkg::ddr3_d2h_t fetcher_rsp;

	rvlab_ddr_cdc_fifo #(
		.ReqDepth(8),
		.RspDepth(8)
	) fetcher_cdc_i (
		.clk_h_i (clk_pixel),
		.rst_h_ni(rst_n),
		.clk_d_i (sys_clk_i),
		.rst_d_ni(sys_rst_ni),
		.wtl_h_i (fetcher_req),
		.wtl_h_o (fetcher_rsp),
		.wtl_d_o (ddr_o),
		.wtl_d_i (ddr_i)
	);

	/* Component resets */

	logic phy_rst;
	logic fetch_valid;

	always_ff @(posedge clk_pixel) begin
		phy_rst <= ~(rst_n & phy_enable & fetch_valid);
	end

	/* Pixel FIFO + PHY */

	logic [11:0] cx;
	logic [10:0] cy;

	logic [ 7:0] r, g, b;
	logic [10:0] fetch_cx, fetch_cy;

	pixel_fetcher fetch_fifo_i (
		.clk_i          (clk_pixel),
		.rst_ni         (rst_n),
		.req_o          (fetcher_req),
		.rsp_i          (fetcher_rsp),
		.r_o            (r),
		.g_o            (g),
		.b_o            (b),
		.enable_i       (prefetcher_enable),
		.next_frame_id_i(next_fbid),
		.cx_o           (fetch_cx),
		.cy_o           (fetch_cy),
		.valid_o        (fetch_valid),
		.consume_i      (fetch_cx == cx && fetch_cy == cy && ~phy_rst)
	);

	hdmi #(
		.VIDEO_ID_CODE            (16),
		.VIDEO_REFRESH_RATE       (60.0),
		.DVI_OUTPUT               (1'b1)
	) phy_i (
		.clk_pixel_x5     (clk_fast),
		.clk_pixel        (clk_pixel),
		.clk_audio        (clk_pixel),
		.reset            (phy_rst),

		.rgb              ({r, g, b}),
		.audio_sample_word({16'h0, 16'h0}),

		.tmds             (tmds_o),
		.tmds_clock       (clk_tmds_o),
		.cx               (cx),
		.cy               (cy),
		.frame_width      (),
		.frame_height     (),
		.screen_width     (),
		.screen_height    ()
	);

endmodule
