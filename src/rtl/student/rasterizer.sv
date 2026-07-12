// Copyright David Schröder 2026

module rasterizer
    import rvlab_ddr_pkg::*;
    import tlul_pkg::*;
    import rasterizer_ctrl_reg_pkg::*;
(
    input  logic clk_i,
    input  logic rst_ni,

    input  tl_h2d_t tl_cfg_i,
    output tl_d2h_t tl_cfg_o,

    output ddr3_h2d_t ddr_o,
    input  ddr3_d2h_t ddr_i
);

    rasterizer_ctrl_reg2hw_t reg2hw;
    rasterizer_ctrl_hw2reg_t hw2reg;

    logic [31:0] pixblk_mask;
    logic [10:0] pixblk_cy;
    logic [ 5:0] pixblk_cx;
    logic        pixblk_valid;
    logic        pixblk_ready;

    rasterizer_ctrl_reg_top reg_top_i (
        .clk_i,
        .rst_ni,
        .tl_i(tl_cfg_i),
        .tl_o(tl_cfg_o),
        .reg2hw,
        .hw2reg,
        .devmode_i('1)
    );

    assign hw2reg.status.d = '0;

    rasterizer_core core_i (
        .clk_i,
        .rst_ni,

        .ab_topleft_i({reg2hw.ab_topleft_hi.q, reg2hw.ab_topleft_lo.q}),
        .bc_topleft_i({reg2hw.bc_topleft_hi.q, reg2hw.bc_topleft_lo.q}),
        .ca_topleft_i({reg2hw.ca_topleft_hi.q, reg2hw.ca_topleft_lo.q}),
        .un_topleft_i({reg2hw.un_topleft_hi.q, reg2hw.un_topleft_lo.q}),
        .vn_topleft_i({reg2hw.vn_topleft_hi.q, reg2hw.vn_topleft_lo.q}),
        .iw_topleft_i({reg2hw.iw_topleft_hi.q, reg2hw.iw_topleft_lo.q}),

        .ab_dx_i(reg2hw.ab_dx.q),
        .ab_dy_i(reg2hw.ab_dy.q),
        .bc_dx_i(reg2hw.bc_dx.q),
        .bc_dy_i(reg2hw.bc_dy.q),
        .ca_dx_i(reg2hw.ca_dx.q),
        .ca_dy_i(reg2hw.ca_dy.q),
        .un_dx_i(reg2hw.un_dx.q),
        .un_dy_i(reg2hw.un_dy.q),
        .vn_dx_i(reg2hw.vn_dx.q),
        .vn_dy_i(reg2hw.vn_dy.q),
        .iw_dx_i(reg2hw.iw_dx.q),
        .iw_dy_i(reg2hw.iw_dy.q),

        .min_x_i(reg2hw.min_x.q),
        .min_y_i(reg2hw.min_y.q),
        .max_x_i(reg2hw.max_x.q),
        .max_y_i(reg2hw.max_y.q),

        .start_i(reg2hw.status.qe),
        .idle_o (hw2reg.status.de),

        .pixblk_mask_o (pixblk_mask),
        .pixblk_cy_o   (pixblk_cy),
        .pixblk_cx_o   (pixblk_cx),
        .pixblk_valid_o(pixblk_valid),
        .pixblk_ready_i(pixblk_ready)
    );

    pixblk_writer writer_i (
        .clk_i,
        .rst_ni,

        .pixblk_mask_i (pixblk_mask),
        .pixblk_cy_i   (pixblk_cy),
        .pixblk_cx_i   (pixblk_cx),
        .pixblk_valid_i(pixblk_valid),
        .pixblk_ready_o(pixblk_ready),

        .fbid_i(reg2hw.fbid.q),
        .ddr_o,
        .ddr_i
    );

endmodule
