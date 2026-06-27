// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2024 RVLab Contributors

module vertex_post_tb;
  localparam int DATA_WIDTH = 32;
  localparam int FRAC_WIDTH = 16;
  localparam int SCREEN_W   = 1920;
  localparam int SCREEN_H   = 1080;
  localparam int SX_WIDTH   = 11;
  localparam int SY_WIDTH   = 11;

  localparam int ONE_FP = 1 <<< FRAC_WIDTH;
  localparam int HALF_W = SCREEN_W / 2;
  localparam int HALF_H = SCREEN_H / 2;

  typedef logic signed [DATA_WIDTH-1:0] data_t;
  typedef data_t vec3_t [2:0];

  logic clk;
  logic rst_n;
  logic in_valid;
  logic out_valid;

  vec3_t x_i, y_i, z_i, w_i;
  logic [SX_WIDTH-1:0] sx_o [2:0];
  logic [SY_WIDTH-1:0] sy_o [2:0];
  data_t z_o [2:0];

  int unsigned errcnt;

  // 50 MHz
  always begin
    clk = '1;
    #10000;
    clk = '0;
    #10000;
  end

  vertex_post #(
    .DATA_WIDTH(DATA_WIDTH),
    .FRAC_WIDTH(FRAC_WIDTH),
    .SCREEN_W  (SCREEN_W),
    .SCREEN_H  (SCREEN_H),
    .SX_WIDTH  (SX_WIDTH),
    .SY_WIDTH  (SY_WIDTH)
  ) DUT (
    .clk      (clk),
    .rst_n    (rst_n),
    .in_valid (in_valid),
    .x_i      (x_i),
    .y_i      (y_i),
    .z_i      (z_i),
    .w_i      (w_i),
    .out_valid(out_valid),
    .sx_o     (sx_o),
    .sy_o     (sy_o),
    .z_o      (z_o)
  );

  // Real to Q16.16 truncates toward zero like the module
  function automatic data_t qreal(input real v);
    return data_t'($rtoi(v * ONE_FP));
  endfunction

  // Golden model mirrors the module math bit for bit

  function automatic data_t f_recip(input data_t w);
    logic signed [63:0] num;
    begin
      num = 64'sd1 <<< (2*FRAC_WIDTH);
      if (w == 0) return '0;
      else        return data_t'(num / w);
    end
  endfunction

  function automatic data_t f_mul(input data_t a, input data_t b);
    logic signed [2*DATA_WIDTH-1:0] p;
    begin
      p = a * b;
      return data_t'(p >>> FRAC_WIDTH);
    end
  endfunction

  function automatic logic [SX_WIDTH-1:0] f_vpx(input data_t x);
    logic signed [63:0] px;
    begin
      px = ($signed(64'(x)) + ONE_FP) * HALF_W >>> FRAC_WIDTH;
      if (px < 0)               return '0;
      else if (px > SCREEN_W-1) return SX_WIDTH'(SCREEN_W-1);
      else                      return px[SX_WIDTH-1:0];
    end
  endfunction

  function automatic logic [SY_WIDTH-1:0] f_vpy(input data_t y);
    logic signed [63:0] py;
    begin
      py = (ONE_FP - $signed(64'(y))) * HALF_H >>> FRAC_WIDTH;
      if (py < 0)               return '0;
      else if (py > SCREEN_H-1) return SY_WIDTH'(SCREEN_H-1);
      else                      return py[SY_WIDTH-1:0];
    end
  endfunction

  task automatic reset_dut();
    rst_n    = 1'b0;
    in_valid = 1'b0;
    x_i = '{default: '0};
    y_i = '{default: '0};
    z_i = '{default: '0};
    w_i = '{default: '0};
    repeat (4) @(posedge clk);
    #1;
    if (out_valid !== 1'b0) begin
      $error("reset: out_valid is not low");
      errcnt = errcnt + 1;
    end
    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);
  endtask

  // Drive one triangle for a single cycle and check the result one cycle later
  task automatic drive_and_check(input string name,
                                 input vec3_t xv, input vec3_t yv,
                                 input vec3_t zv, input vec3_t wv);
    logic [SX_WIDTH-1:0] exp_sx [2:0];
    logic [SY_WIDTH-1:0] exp_sy [2:0];
    data_t exp_z [2:0];
    data_t ndc_x [2:0];
    data_t ndc_y [2:0];
    data_t iw;

    for (int i = 0; i < 3; i++) begin
      iw = f_recip(wv[i]);
      ndc_x[i]  = f_mul(xv[i], iw);
      ndc_y[i]  = f_mul(yv[i], iw);
      exp_sx[i] = f_vpx(ndc_x[i]);
      exp_sy[i] = f_vpy(ndc_y[i]);
      exp_z[i]  = f_mul(zv[i], iw);
    end

    @(negedge clk);
    x_i = xv; y_i = yv; z_i = zv; w_i = wv;
    in_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    in_valid = 1'b0;
    #1;

    if (out_valid !== 1'b1) begin
      $error("%s: out_valid not asserted", name);
      errcnt = errcnt + 1;
    end
    $display("%s:", name);
    for (int i = 0; i < 3; i++) begin
      $display("  v%0d  ndc=(%.3f, %.3f, %.3f)  px=(%4d, %4d)", i,
               real'(ndc_x[i]) / ONE_FP, real'(ndc_y[i]) / ONE_FP,
               real'(z_o[i]) / ONE_FP, sx_o[i], sy_o[i]);
    end
    for (int i = 0; i < 3; i++) begin
      if (sx_o[i] !== exp_sx[i]) begin
        $error("%s: sx_o[%0d] expected %0d got %0d", name, i, exp_sx[i], sx_o[i]);
        errcnt = errcnt + 1;
      end
      if (sy_o[i] !== exp_sy[i]) begin
        $error("%s: sy_o[%0d] expected %0d got %0d", name, i, exp_sy[i], sy_o[i]);
        errcnt = errcnt + 1;
      end
      if (z_o[i] !== exp_z[i]) begin
        $error("%s: z_o[%0d] expected 0x%08x got 0x%08x", name, i, exp_z[i], z_o[i]);
        errcnt = errcnt + 1;
      end
    end

    @(posedge clk);
    #1;
    if (out_valid !== 1'b0) begin
      $error("%s: out_valid stayed high after one cycle", name);
      errcnt = errcnt + 1;
    end
  endtask

  // With in_valid low the outputs must hold and out_valid must stay low
  task automatic check_hold(input string name);
    logic [SX_WIDTH-1:0] prev [2:0];
    for (int i = 0; i < 3; i++) prev[i] = sx_o[i];
    in_valid = 1'b0;
    repeat (3) @(posedge clk);
    #1;
    if (out_valid !== 1'b0) begin
      $error("%s: out_valid high while idle", name);
      errcnt = errcnt + 1;
    end
    for (int i = 0; i < 3; i++) begin
      if (sx_o[i] !== prev[i]) begin
        $error("%s: sx_o[%0d] changed while in_valid low", name, i);
        errcnt = errcnt + 1;
      end
    end
  endtask

  initial begin
    vec3_t xv, yv, zv, wv;

    errcnt = '0;
    reset_dut();

    // No perspective w = 1 so clip coords are already NDC
    xv = '{qreal(0.0), qreal(0.5), qreal(-0.5)};
    yv = '{qreal(0.5), qreal(-0.5), qreal(-0.5)};
    zv = '{qreal(0.3), qreal(0.2), qreal(0.1)};
    wv = '{qreal(1.0), qreal(1.0), qreal(1.0)};
    drive_and_check("ortho_w1", xv, yv, zv, wv);

    // Perspective different w per vertex shrinks toward center
    xv = '{qreal(0.0), qreal(0.5), qreal(-0.5)};
    yv = '{qreal(0.5), qreal(-0.5), qreal(-0.5)};
    zv = '{qreal(0.0), qreal(0.0), qreal(0.0)};
    wv = '{qreal(4.0), qreal(2.0), qreal(1.0)};
    drive_and_check("persp_w421", xv, yv, zv, wv);

    // Out of range NDC must clamp to the screen edges
    xv = '{qreal(2.0), qreal(-2.0), qreal(0.0)};
    yv = '{qreal(3.0), qreal(-3.0), qreal(0.0)};
    zv = '{qreal(0.0), qreal(0.0), qreal(0.0)};
    wv = '{qreal(1.0), qreal(1.0), qreal(1.0)};
    drive_and_check("clamp_edges", xv, yv, zv, wv);

    // w = 0 must not divide it returns the reciprocal guard value
    xv = '{qreal(0.5), qreal(-0.5), qreal(0.0)};
    yv = '{qreal(0.5), qreal(-0.5), qreal(0.0)};
    zv = '{qreal(0.0), qreal(0.0), qreal(0.0)};
    wv = '{qreal(0.0), qreal(1.0), qreal(1.0)};
    drive_and_check("w_zero_guard", xv, yv, zv, wv);

    // Outputs must hold while idle
    check_hold("idle_hold");

    if (errcnt > 0) begin
      $display("### TESTS FAILED WITH %0d ERRORS ###", errcnt);
    end else begin
      $display("### TESTS PASSED ###");
    end

    $finish;
  end

endmodule