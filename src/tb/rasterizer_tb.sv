// Copyright David Schröder 2026

module rasterizer_tb;

    logic clk;
    logic rstn;

    always begin
        clk <= '1;
        #10000;
        clk <= '0;
        #10000;
    end

    logic rasterizer_start;
    logic rasterizer_idle;

    logic [31:0] pixblk_mask;
    logic [10:0] pixblk_cy;
    logic [ 5:0] pixblk_cx;
    logic        pixblk_valid;
    logic        pixblk_ready;

    rvlab_ddr_pkg::ddr3_h2d_t ddr_h2d;
    rvlab_ddr_pkg::ddr3_d2h_t ddr_d2h;

    rasterizer_core DUT (
        .clk_i (clk),
        .rst_ni(rstn),

        .ab_topleft_i(64'h0000000000032f20),
        .bc_topleft_i(64'hfffffffffffd4c00),
        .ca_topleft_i(64'h0000000000068d40),
        .un_topleft_i(64'hffffffffaf28e000),
        .vn_topleft_i(64'h00000000be691400),
        .iw_topleft_i(64'h00000000d2aa2c00),

        .ab_dx_i(32'hfffffc0a),
        .ab_dy_i(32'h00000230),
        .bc_dx_i(32'h00000354),
        .bc_dy_i(32'hfffffff0),
        .ca_dx_i(32'h000000a2),
        .ca_dy_i(32'hfffffde0),
        .un_dx_i(32'h00638820),
        .un_dy_i(32'hfffe2180),
        .vn_dx_i(32'h00126420),
        .vn_dy_i(32'hffc23e00),
        .iw_dx_i(32'hfff829c0),
        .iw_dy_i(32'h0005d380),

        .min_x_i(16'd7119),
        .min_y_i(16'd3303),
        .max_x_i(16'd7687),
        .max_y_i(16'd4327),

        .start_i(rasterizer_start),
        .idle_o (rasterizer_idle),

        .pixblk_mask_o (pixblk_mask),
        .pixblk_cy_o   (pixblk_cy),
        .pixblk_cx_o   (pixblk_cx),
        .pixblk_valid_o(pixblk_valid),
        .pixblk_ready_i(pixblk_ready)
    );

    pixblk_writer writer_i (
        .clk_i (clk),
        .rst_ni(rstn),

        .pixblk_mask_i (pixblk_mask),
        .pixblk_cy_i   (pixblk_cy),
        .pixblk_cx_i   (pixblk_cx),
        .pixblk_valid_i(pixblk_valid),
        .pixblk_ready_o(pixblk_ready),

        .fbid_i('0),
        .ddr_o (ddr_h2d),
        .ddr_i (ddr_d2h)
    );

    assign ddr_d2h = '{d_opcode: tlul_pkg::AccessAck, a_ready: '1, default: '0};

    initial begin
        rstn <= '0;
        rasterizer_start <= '0;
        @(posedge clk);
        @(posedge clk);
        rstn <= '1;
        @(posedge clk);
        @(posedge clk);
        rasterizer_start <= '1;
        @(posedge clk);
        rasterizer_start <= '0;
        @(posedge clk);

        while (!rasterizer_idle) @(posedge clk);
        $finish();
    end

endmodule
