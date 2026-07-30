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

  // Posedges from the accepting edge until out_valid is visible:
  // 2*FRAC_WIDTH+1 divider steps plus the NDC and output register stages
  localparam int LATENCY = 2 * FRAC_WIDTH + 3;
  localparam int TIMEOUT = 2 * LATENCY;

  typedef logic signed [DATA_WIDTH-1:0] data_t;
  typedef data_t vec3_t [2:0];
  typedef logic [SX_WIDTH-1:0] sx_t [2:0];
  typedef logic [SY_WIDTH-1:0] sy_t [2:0];

  logic clk;
  logic rst_n;
  logic in_valid;
  logic ready;
  logic out_valid;
  logic out_ready;
  logic [10:0] tri_id_i;
  logic [10:0] tri_id_o;

  vec3_t x_i, y_i, z_i, w_i;
  sx_t sx_o;
  sy_t sy_o;
  data_t z_o [2:0];
  data_t inv_w_o [2:0];

  int unsigned errcnt;

  // 50 MHz
  always begin
    clk = '1;
    #10000;
    clk = '0;
    #10000;
  end

  // Whole run needs well under 1000 cycles, a hung handshake must not
  // deadlock the simulation
  initial begin
    repeat (10000) @(posedge clk);
    $display("### TESTS FAILED: GLOBAL WATCHDOG TIMEOUT ###");
    $fatal(1);
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
    .ready_o  (ready),
    .x_i      (x_i),
    .y_i      (y_i),
    .z_i      (z_i),
    .w_i      (w_i),
    .tri_id_i (tri_id_i),
    .out_valid(out_valid),
    .out_ready_i(out_ready),
    .sx_o     (sx_o),
    .sy_o     (sy_o),
    .z_o      (z_o),
    .inv_w_o  (inv_w_o),
    .tri_id_o (tri_id_o)
  );

  // Real to Q16.16 truncates toward zero like the module
  function automatic data_t qreal(input real v);
    return data_t'($rtoi(v * ONE_FP));
  endfunction

  // Golden model mirrors the module math bit for bit

  // Truncating reciprocal with Q16.16 saturation like the restoring divider
  function automatic data_t f_recip(input data_t w);
    logic signed [63:0] num, q;
    begin
      if (w == 0) return '0;
      num = 64'sd1 <<< (2*FRAC_WIDTH);
      q   = num / 64'(w);
      if (q > 64'sd2147483647)       return 32'sh7FFF_FFFF;
      else if (q < -64'sd2147483648) return 32'sh8000_0000;
      else                           return data_t'(q);
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

  // Expected outputs of one triangle
  task automatic golden(input vec3_t xv, input vec3_t yv,
                        input vec3_t zv, input vec3_t wv,
                        output sx_t exp_sx, output sy_t exp_sy,
                        output vec3_t exp_z, output vec3_t exp_iw);
    data_t ndc_x, ndc_y;
    for (int i = 0; i < 3; i++) begin
      exp_iw[i] = f_recip(wv[i]);
      ndc_x     = f_mul(xv[i], exp_iw[i]);
      ndc_y     = f_mul(yv[i], exp_iw[i]);
      exp_sx[i] = f_vpx(ndc_x);
      exp_sy[i] = f_vpy(ndc_y);
      exp_z[i]  = f_mul(zv[i], exp_iw[i]);
    end
  endtask

  // Compare the DUT outputs against expected values
  task automatic check_result(input string name,
                              input sx_t exp_sx, input sy_t exp_sy,
                              input vec3_t exp_z, input vec3_t exp_iw);
    $display("%s:", name);
    for (int i = 0; i < 3; i++) begin
      $display("  v%0d  px=(%4d, %4d)  z=%.3f  1/w=0x%08x", i,
               sx_o[i], sy_o[i], real'(z_o[i]) / ONE_FP, inv_w_o[i]);
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
      if (inv_w_o[i] !== exp_iw[i]) begin
        $error("%s: inv_w_o[%0d] expected 0x%08x got 0x%08x", name, i, exp_iw[i], inv_w_o[i]);
        errcnt = errcnt + 1;
      end
    end
  endtask

  task automatic reset_dut();
    rst_n    = 1'b0;
    in_valid = 1'b0;
    out_ready = 1'b1;
    tri_id_i = '0;
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
    #1;
    if (ready !== 1'b1) begin
      $error("reset: ready_o not high after reset release");
      errcnt = errcnt + 1;
    end
  endtask

  task automatic drive_and_check_backpressure(input string name,
                                              input vec3_t xv, input vec3_t yv,
                                              input vec3_t zv, input vec3_t wv);
    sx_t exp_sx;
    sy_t exp_sy;
    vec3_t exp_z, exp_iw;
    int t;

    golden(xv, yv, zv, wv, exp_sx, exp_sy, exp_z, exp_iw);
    out_ready = 1'b0;
    drive_triangle(xv, yv, zv, wv);

    t = 0;
    while (out_valid !== 1'b1 && t < TIMEOUT) begin
      @(posedge clk);
      #1;
      t = t + 1;
    end
    if (out_valid !== 1'b1) begin
      $error("%s: timeout, no out_valid under backpressure", name);
      errcnt = errcnt + 1;
      out_ready = 1'b1;
      return;
    end
    if (t !== LATENCY) begin
      $error("%s: out_valid after %0d cycles, expected %0d", name, t, LATENCY);
      errcnt = errcnt + 1;
    end
    check_result({name, "_initial"}, exp_sx, exp_sy, exp_z, exp_iw);

    repeat (3) begin
      @(posedge clk);
      #1;
      if (out_valid !== 1'b1 || ready !== 1'b0) begin
        $error("%s: output was not held while out_ready_i was low", name);
        errcnt = errcnt + 1;
      end
      check_result({name, "_held"}, exp_sx, exp_sy, exp_z, exp_iw);
    end

    out_ready = 1'b1;
    @(posedge clk);
    #1;
    if (out_valid !== 1'b0 || ready !== 1'b1) begin
      $error("%s: output was not consumed when out_ready_i rose", name);
      errcnt = errcnt + 1;
    end
  endtask

  // Apply one triangle and complete the in_valid/ready_o handshake. Returns
  // at the negedge after the accepting posedge with in_valid deasserted
  task automatic drive_triangle(input vec3_t xv, input vec3_t yv,
                                input vec3_t zv, input vec3_t wv);
    int t;
    t = 0;
    @(negedge clk);
    while (ready !== 1'b1 && t < TIMEOUT) begin
      @(negedge clk);
      t = t + 1;
    end
    if (ready !== 1'b1) begin
      $error("drive: ready_o never returned high");
      errcnt = errcnt + 1;
      return;
    end
    x_i = xv; y_i = yv; z_i = zv; w_i = wv;
    tri_id_i = tri_id_i + 1'b1;
    in_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    in_valid = 1'b0;
  endtask

  // Drive one triangle, wait for out_valid and compare against the golden model
  task automatic drive_and_check(input string name,
                                 input vec3_t xv, input vec3_t yv,
                                 input vec3_t zv, input vec3_t wv);
    sx_t exp_sx;
    sy_t exp_sy;
    vec3_t exp_z, exp_iw;
    int t;

    golden(xv, yv, zv, wv, exp_sx, exp_sy, exp_z, exp_iw);
    drive_triangle(xv, yv, zv, wv);

    #1;
    if (ready !== 1'b0) begin
      $error("%s: ready_o still high one cycle after the accept", name);
      errcnt = errcnt + 1;
    end

    t = 0;
    while (out_valid !== 1'b1 && t < TIMEOUT) begin
      @(posedge clk);
      #1;
      t = t + 1;
    end
    if (out_valid !== 1'b1) begin
      $error("%s: timeout, no out_valid within %0d cycles", name, TIMEOUT);
      errcnt = errcnt + 1;
      return;
    end
    if (t !== LATENCY) begin
      $error("%s: out_valid after %0d cycles, expected %0d", name, t, LATENCY);
      errcnt = errcnt + 1;
    end

    check_result(name, exp_sx, exp_sy, exp_z, exp_iw);

    @(posedge clk);
    #1;
    if (out_valid !== 1'b0) begin
      $error("%s: out_valid stayed high after one cycle", name);
      errcnt = errcnt + 1;
    end
    if (ready !== 1'b1) begin
      $error("%s: ready_o not back high after completion", name);
      errcnt = errcnt + 1;
    end
  endtask

  // Two triangles with in_valid held high across both: the second data is
  // already on the inputs while the first is processed (must be ignored
  // until the first is done) and its accept must happen on the same cycle
  // out_valid pulses for the first
  task automatic drive_two_streaming(input string name,
                                     input vec3_t xa, input vec3_t ya,
                                     input vec3_t za, input vec3_t wa,
                                     input vec3_t xb, input vec3_t yb,
                                     input vec3_t zb, input vec3_t wb);
    sx_t exp_sx_a, exp_sx_b;
    sy_t exp_sy_a, exp_sy_b;
    vec3_t exp_z_a, exp_iw_a, exp_z_b, exp_iw_b;
    int t;

    golden(xa, ya, za, wa, exp_sx_a, exp_sy_a, exp_z_a, exp_iw_a);
    golden(xb, yb, zb, wb, exp_sx_b, exp_sy_b, exp_z_b, exp_iw_b);

    @(negedge clk);
    while (ready !== 1'b1) @(negedge clk);
    x_i = xa; y_i = ya; z_i = za; w_i = wa;
    in_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    // Triangle B sits on the bus with in_valid high while A is processed
    x_i = xb; y_i = yb; z_i = zb; w_i = wb;
    #1;
    if (ready !== 1'b0) begin
      $error("%s: ready_o still high one cycle after the first accept", name);
      errcnt = errcnt + 1;
    end

    t = 0;
    while (out_valid !== 1'b1 && t < TIMEOUT) begin
      @(posedge clk);
      #1;
      t = t + 1;
    end
    if (out_valid !== 1'b1) begin
      $error("%s: timeout waiting for the first result", name);
      errcnt = errcnt + 1;
      in_valid = 1'b0;
      return;
    end
    if (t !== LATENCY) begin
      $error("%s: first out_valid after %0d cycles, expected %0d", name, t, LATENCY);
      errcnt = errcnt + 1;
    end
    // Must be A's result: a mid-division re-latch of B would corrupt it
    check_result({name, "_first"}, exp_sx_a, exp_sy_a, exp_z_a, exp_iw_a);

    // B is accepted on this edge, ready_o was high during the pulse cycle
    @(posedge clk);
    #1;
    if (out_valid !== 1'b0) begin
      $error("%s: first out_valid longer than one cycle", name);
      errcnt = errcnt + 1;
    end
    if (ready !== 1'b0) begin
      $error("%s: second triangle not accepted back to back", name);
      errcnt = errcnt + 1;
    end
    @(negedge clk);
    in_valid = 1'b0;

    t = 0;
    #1;
    while (out_valid !== 1'b1 && t < TIMEOUT) begin
      @(posedge clk);
      #1;
      t = t + 1;
    end
    if (out_valid !== 1'b1) begin
      $error("%s: timeout waiting for the second result", name);
      errcnt = errcnt + 1;
      return;
    end
    if (t !== LATENCY) begin
      $error("%s: second out_valid after %0d cycles, expected %0d", name, t, LATENCY);
      errcnt = errcnt + 1;
    end
    check_result({name, "_second"}, exp_sx_b, exp_sy_b, exp_z_b, exp_iw_b);

    @(posedge clk);
    #1;
    if (out_valid !== 1'b0 || ready !== 1'b1) begin
      $error("%s: bad pulse or ready after the second result", name);
      errcnt = errcnt + 1;
    end
  endtask

  // A culled triangle is dropped on the accept cycle: ready_o stays high,
  // no out_valid pulse and the outputs do not change
  task automatic drive_and_check_drop(input string name,
                                      input vec3_t xv, input vec3_t yv,
                                      input vec3_t zv, input vec3_t wv);
    sx_t prev_sx;
    sy_t prev_sy;
    vec3_t prev_z, prev_iw;
    for (int i = 0; i < 3; i++) begin
      prev_sx[i] = sx_o[i];
      prev_sy[i] = sy_o[i];
      prev_z[i]  = z_o[i];
      prev_iw[i] = inv_w_o[i];
    end

    drive_triangle(xv, yv, zv, wv);
    #1;
    if (ready !== 1'b1) begin
      $error("%s: ready_o dropped for a discarded triangle", name);
      errcnt = errcnt + 1;
    end
    for (int t = 0; t < LATENCY; t++) begin
      @(posedge clk);
      #1;
      if (out_valid !== 1'b0) begin
        $error("%s: out_valid pulsed for a discarded triangle", name);
        errcnt = errcnt + 1;
        return;
      end
      if (ready !== 1'b1) begin
        $error("%s: ready_o dropped after a discarded triangle", name);
        errcnt = errcnt + 1;
        return;
      end
    end
    check_result({name, "_hold"}, prev_sx, prev_sy, prev_z, prev_iw);
    $display("%s: discarded as expected", name);
  endtask

  // With no accepted triangle all outputs must hold and out_valid stay low
  task automatic check_hold(input string name);
    sx_t prev_sx;
    sy_t prev_sy;
    vec3_t prev_z, prev_iw;
    for (int i = 0; i < 3; i++) begin
      prev_sx[i] = sx_o[i];
      prev_sy[i] = sy_o[i];
      prev_z[i]  = z_o[i];
      prev_iw[i] = inv_w_o[i];
    end
    in_valid = 1'b0;
    repeat (3) @(posedge clk);
    #1;
    if (out_valid !== 1'b0) begin
      $error("%s: out_valid high while idle", name);
      errcnt = errcnt + 1;
    end
    check_result(name, prev_sx, prev_sy, prev_z, prev_iw);
  endtask

  localparam int N_REF = 10;
  localparam data_t REF_X [N_REF][3] = '{
    '{32'sh00000000, 32'sh00000000, 32'sh00000000},
    '{32'shffff0697, 32'sh00000000, 32'sh00000000},
    '{32'sh00000000, 32'sh00006f8a, 32'sh00006f8a},
    '{32'sh00000001, 32'sh00006f8a, 32'shffff9076},
    '{32'sh00000000, 32'sh00000000, 32'sh00000000},
    '{32'shffff0691, 32'sh00000000, 32'sh00000000},
    '{32'sh00000000, 32'sh0000b05c, 32'sh0000b05c},
    '{32'shfffdeeeb, 32'sh0000b05c, 32'shffff4fa4},
    '{32'sh00000000, 32'sh0000f969, 32'sh0000f969},
    '{32'shfffe0d2e, 32'sh0000f969, 32'shffff0697}
  };
  localparam data_t REF_Y [N_REF][3] = '{
    '{32'sh00000000, 32'sh00000000, 32'sh0001bb67},
    '{32'shfffe4499, 32'sh000376ce, 32'sh00000000},
    '{32'sh00000000, 32'sh00013dfc, 32'sh000246f9},
    '{32'shfffbdc0c, 32'sh00034ff6, 32'shfffec204},
    '{32'sh00000008, 32'shfffe4aa1, 32'shfffe9386},
    '{32'sh000321f1, 32'shfffedc6b, 32'sh0001b56f},
    '{32'sh00000000, 32'shffff4afc, 32'sh0000b503},
    '{32'shffff4afc, 32'sh00021f0a, 32'sh0000b504},
    '{32'sh00000000, 32'sh00000000, 32'sh0001bb67},
    '{32'shfffe4499, 32'sh000376ce, 32'sh00000000}
  };
  localparam data_t REF_Z [N_REF][3] = '{
    '{32'sh00048616, 32'sh000384ce, 32'sh000384ce},
    '{32'sh000688a6, 32'sh000384ce, 32'sh0005875e},
    '{32'sh00034253, 32'sh0003cbd8, 32'sh0002fd90},
    '{32'sh0002b8ce, 32'sh00022f48, 32'sh0002b8ce},
    '{32'sh00059ca7, 32'sh0005725b, 32'sh00047493},
    '{32'sh0006ef07, 32'sh000376cb, 32'sh0005c6f3},
    '{32'sh0004b88b, 32'sh00042400, 32'sh00038f75},
    '{32'sh0005e1a1, 32'sh0002faea, 32'sh00054d16},
    '{32'sh000080f6, 32'sh000080f6, 32'sh000080f6},
    '{32'shffff7fae, 32'sh000080f6, 32'sh000080f6}
  };
  localparam data_t REF_W [N_REF][3] = '{
    '{32'sh00050000, 32'sh00040000, 32'sh00040000},
    '{32'sh00070000, 32'sh00040000, 32'sh00060000},
    '{32'sh0003bdda, 32'sh000446b0, 32'sh0003796f},
    '{32'sh00033504, 32'sh0002ac2e, 32'sh00033504},
    '{32'sh0006152e, 32'sh0005eb18, 32'sh0004ee94},
    '{32'sh000765de, 32'sh0003f210, 32'sh00063f44},
    '{32'sh00053235, 32'sh00049e68, 32'sh00040a9b},
    '{32'sh000659cf, 32'sh000376ce, 32'sh0005c602},
    '{32'sh00010000, 32'sh00010000, 32'sh00010000},
    '{32'sh00000000, 32'sh00010000, 32'sh00010000}
  };
  localparam int REF_SX [N_REF][3] = '{
    '{  960,   960,   960},
    '{  826,   960,   960},
    '{  960,  1057,  1080},
    '{  960,  1116,   829},
    '{  960,   960,   960},
    '{  833,   960,   960},
    '{  960,  1103,  1123},
    '{  647,  1150,   845},
    '{  960,  1895,  1895},
    '{  959,  1895,    24}
  };
  localparam int REF_SY [N_REF][3] = '{
    '{  540,   540,   307},
    '{  674,    73,   540},
    '{  540,   384,   187},
    '{ 1238,  -129,   750},
    '{  540,   696,   696},
    '{  312,   696,   393},
    '{  540,   623,   446},
    '{  601,   210,   474},
    '{  540,   540,  -395},
    '{  541, -1330,   540}
  };
  localparam bit REF_CULL [N_REF] = '{0, 0, 0, 0, 0, 0, 0, 0, 0, 1};

  task automatic drive_and_check_ref(input string name,
                                       input vec3_t xv, input vec3_t yv,
                                       input vec3_t zv, input vec3_t wv,
                                       input int dsx [3], input int dsy [3]);
    int cx, cy0, cy1;
    drive_and_check(name, xv, yv, zv, wv);
    for (int i = 0; i < 3; i++) begin
      cx  = dsx[i]   < 0 ? 0 : (dsx[i]   > SCREEN_W-1 ? SCREEN_W-1 : dsx[i]);
      cy0 = dsy[i]   < 0 ? 0 : (dsy[i]   > SCREEN_H-1 ? SCREEN_H-1 : dsy[i]);
      cy1 = dsy[i]-1 < 0 ? 0 : (dsy[i]-1 > SCREEN_H-1 ? SCREEN_H-1 : dsy[i]-1);
      if (int'(sx_o[i]) != cx) begin
        $error("%s: sx_o[%0d] is %0d, software reference expects %0d",
               name, i, sx_o[i], cx);
        errcnt = errcnt + 1;
      end
      if (int'(sy_o[i]) != cy0 && int'(sy_o[i]) != cy1) begin
        $error("%s: sy_o[%0d] is %0d, software reference expects %0d (or %0d)",
               name, i, sy_o[i], cy0, cy1);
        errcnt = errcnt + 1;
      end
    end
  endtask

  initial begin
    vec3_t xv, yv, zv, wv;
    vec3_t xb, yb, zb, wb;

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

    // The processed output must be held until the downstream stage is ready.
    xv = '{qreal(0.0), qreal(0.25), qreal(-0.25)};
    yv = '{qreal(0.25), qreal(-0.25), qreal(-0.25)};
    zv = '{qreal(0.1), qreal(0.2), qreal(0.3)};
    wv = '{qreal(1.0), qreal(2.0), qreal(4.0)};
    drive_and_check_backpressure("output_backpressure", xv, yv, zv, wv);

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

    // Tiny positive w must saturate 1/w to the Q16.16 maximum instead of
    // wrapping (raw w = 1 and 2 overflow, raw w = 3 is the first exact value)
    xv = '{qreal(0.5), qreal(-0.5), qreal(0.25)};
    yv = '{qreal(0.5), qreal(-0.5), qreal(0.25)};
    zv = '{qreal(0.0), qreal(0.0), qreal(0.0)};
    wv = '{data_t'(1), data_t'(2), data_t'(3)};
    drive_and_check("tiny_w_saturate", xv, yv, zv, wv);

    // Tiny negative w saturates to the Q16.16 minimum, raw w = -2 is exact
    // -2^31 and the most negative w gives raw -2
    xv = '{qreal(0.5), qreal(-0.5), qreal(0.25)};
    yv = '{qreal(0.5), qreal(-0.5), qreal(0.25)};
    zv = '{qreal(-0.5), qreal(-0.5), qreal(-0.5)};
    wv = '{data_t'(-1), data_t'(-2), data_t'(32'h8000_0000)};
    drive_and_check("tiny_w_neg_saturate", xv, yv, zv, wv);

    // Back to back streaming with in_valid held high and the second
    // triangle's data on the bus while the first is still processed
    xv = '{qreal(0.0), qreal(0.5), qreal(-0.5)};
    yv = '{qreal(0.5), qreal(-0.5), qreal(-0.5)};
    zv = '{qreal(0.3), qreal(0.2), qreal(0.1)};
    wv = '{qreal(1.0), qreal(1.0), qreal(1.0)};
    xb = '{qreal(0.25), qreal(-0.25), qreal(0.75)};
    yb = '{qreal(-0.25), qreal(0.25), qreal(-0.75)};
    zb = '{qreal(0.4), qreal(0.5), qreal(0.6)};
    wb = '{qreal(2.0), qreal(3.0), qreal(4.0)};
    drive_two_streaming("stream_pair", xv, yv, zv, wv, xb, yb, zb, wb);

    // Vertex behind the camera z/w < 0 discards the whole triangle
    xv = '{qreal(0.0), qreal(0.5), qreal(-0.5)};
    yv = '{qreal(0.5), qreal(-0.5), qreal(-0.5)};
    zv = '{qreal(0.3), qreal(0.2), qreal(0.1)};
    wv = '{qreal(1.0), qreal(-1.0), qreal(1.0)};
    drive_and_check_drop("cull_behind", xv, yv, zv, wv);

    // A triangle right after a discarded one must still work
    xv = '{qreal(0.0), qreal(0.5), qreal(-0.5)};
    yv = '{qreal(0.5), qreal(-0.5), qreal(-0.5)};
    zv = '{qreal(0.3), qreal(0.2), qreal(0.1)};
    wv = '{qreal(1.0), qreal(2.0), qreal(1.0)};
    drive_and_check("after_drop", xv, yv, zv, wv);

    // Outputs must hold while idle
    check_hold("idle_hold");

    for (int t = 0; t < N_REF; t++) begin
      for (int i = 0; i < 3; i++) begin
        xv[i] = REF_X[t][i];
        yv[i] = REF_Y[t][i];
        zv[i] = REF_Z[t][i];
        wv[i] = REF_W[t][i];
      end
      if (REF_CULL[t])
        drive_and_check_drop($sformatf("ref_%0d_cull", t), xv, yv, zv, wv);
      else
        drive_and_check_ref($sformatf("ref_%0d", t), xv, yv, zv, wv,
                              REF_SX[t], REF_SY[t]);
    end

    if (errcnt > 0) begin
      $display("### TESTS FAILED WITH %0d ERRORS ###", errcnt);
    end else begin
      $display("### TESTS PASSED ###");
    end

    $finish;
  end

endmodule
