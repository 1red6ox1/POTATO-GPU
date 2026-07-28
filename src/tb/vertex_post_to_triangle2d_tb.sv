// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2026 RVLab Contributors

module vertex_post_to_triangle2d_tb;
  import rasterizer_pkg::*;

  localparam int DATA_WIDTH = 32;
  localparam int FRAC_WIDTH = 16;
  localparam int FIFO_DEPTH = 4;
  localparam int TIMEOUT    = 64;

  localparam int Q_FRAC_SHIFT = UVQ_FRAC_WIDTH - FRAC_WIDTH;

  typedef logic signed [DATA_WIDTH-1:0] data_t;
  typedef logic signed [13:0]           coord_in_t;
  typedef logic signed [COORD_WIDTH-1:0] coord_t;
  typedef logic [DEPTH_WIDTH-1:0]       depth_t;
  typedef logic signed [UVQ_WIDTH-1:0]  uvq_t;
  typedef logic [1:0]                   fbid_t;
  typedef logic [5:0]                   uv_desc_t;

  localparam data_t ONE_Q16 = data_t'(32'sd1 <<< FRAC_WIDTH);
  localparam tlul_pkg::tl_h2d_t TlIdle = '{a_opcode: tlul_pkg::PutFullData, default: '0};

  logic clk = 1'b0;
  logic rst_n;

  logic in_ready;
  logic in_valid;
  logic [10:0] triangle_id;
  coord_in_t sx [2:0];
  coord_in_t sy [2:0];
  data_t z [2:0];
  data_t inv_w [2:0];
  logic [1:0] fbid_color;
  logic [1:0] fbid_depth;

  triangle_t triangle;
  logic out_valid;
  logic out_ready;

  tlul_pkg::tl_h2d_t tl_h2d;
  tlul_pkg::tl_d2h_t tl_d2h;

  int unsigned errcnt;

  always #10000 clk = ~clk;

  initial begin
    repeat (5000) @(posedge clk);
    $display("### TESTS FAILED: GLOBAL WATCHDOG TIMEOUT ###");
    $fatal(1);
  end

  vertex_post_to_triangle2d #(
    .DATA_WIDTH(DATA_WIDTH),
    .FRAC_WIDTH(FRAC_WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH)
  ) DUT (
    .clk_i        (clk),
    .rst_ni       (rst_n),
    .in_ready_o   (in_ready),
    .in_valid_i   (in_valid),
    .triangle_id_i(triangle_id),
    .sx_i         (sx),
    .sy_i         (sy),
    .z_i          (z),
    .inv_w_i      (inv_w),
    .fbid_color_i (fbid_color),
    .fbid_depth_i (fbid_depth),
    .triangle_o   (triangle),
    .out_valid_o  (out_valid),
    .out_ready_i  (out_ready),
    .tl_i         (tl_h2d),
    .tl_o         (tl_d2h)
  );

  function automatic coord_t model_coord(input int signed value);
    coord_in_t narrowed;
    begin
      narrowed = coord_in_t'(value);
      model_coord = COORD_WIDTH'($signed({1'b0, narrowed}));
    end
  endfunction

  function automatic depth_t model_depth(input data_t value);
    begin
      if (value <= '0) begin
        model_depth = '0;
      end else if (value >= ONE_Q16) begin
        model_depth = '1;
      end else begin
        model_depth = value[FRAC_WIDTH-1 -: DEPTH_WIDTH];
      end
    end
  endfunction

  function automatic uvq_t model_q(input data_t value);
    begin
      model_q = UVQ_WIDTH'($signed(value) <<< Q_FRAC_SHIFT);
    end
  endfunction

  task automatic build_expected(
      input  logic [10:0] id,
      input  int signed sx0,
      input  int signed sy0,
      input  int signed sx1,
      input  int signed sy1,
      input  int signed sx2,
      input  int signed sy2,
      input  data_t z0,
      input  data_t z1,
      input  data_t z2,
      input  data_t inv_w0,
      input  data_t inv_w1,
      input  data_t inv_w2,
      input  logic [1:0] color_id,
      input  logic [1:0] depth_id,
      input  logic [5:0] uv_desc,
      output triangle_t expected
  );
    coord_t x [2:0];
    coord_t y [2:0];
    depth_t zd [2:0];
    uvq_t q [2:0];
    logic signed [COORD_WIDTH:0] dx10;
    logic signed [COORD_WIDTH:0] dy20;
    logic signed [COORD_WIDTH:0] dy10;
    logic signed [COORD_WIDTH:0] dx20;
    logic signed [2*COORD_WIDTH+2:0] area;
    begin
      x[0] = model_coord(sx0);
      x[1] = model_coord(sx1);
      x[2] = model_coord(sx2);
      y[0] = model_coord(sy0);
      y[1] = model_coord(sy1);
      y[2] = model_coord(sy2);
      zd[0] = model_depth(z0);
      zd[1] = model_depth(z1);
      zd[2] = model_depth(z2);
      q[0] = model_q(inv_w0);
      q[1] = model_q(inv_w1);
      q[2] = model_q(inv_w2);

      dx10 = $signed({x[1][COORD_WIDTH-1], x[1]})
           - $signed({x[0][COORD_WIDTH-1], x[0]});
      dy20 = $signed({y[2][COORD_WIDTH-1], y[2]})
           - $signed({y[0][COORD_WIDTH-1], y[0]});
      dy10 = $signed({y[1][COORD_WIDTH-1], y[1]})
           - $signed({y[0][COORD_WIDTH-1], y[0]});
      dx20 = $signed({x[2][COORD_WIDTH-1], x[2]})
           - $signed({x[0][COORD_WIDTH-1], x[0]});
      area = $signed(dx10) * $signed(dy20) - $signed(dy10) * $signed(dx20);

      expected = '0;
      expected.triangle_id = TRIANGLE_ID_WIDTH'(id);
      expected.fbid_color = color_id;
      expected.fbid_depth = depth_id;

      expected.ax = x[0];
      expected.ay = y[0];
      expected.az = zd[0];
      expected.auq = uv_desc[5] ? q[0] : '0;
      expected.avq = uv_desc[4] ? q[0] : '0;
      expected.aq = q[0];

      expected.bx = x[1];
      expected.by = y[1];
      expected.bz = zd[1];
      expected.buq = uv_desc[3] ? q[1] : '0;
      expected.bvq = uv_desc[2] ? q[1] : '0;
      expected.bq = q[1];

      expected.cx = x[2];
      expected.cy = y[2];
      expected.cz = zd[2];
      expected.cuq = uv_desc[1] ? q[2] : '0;
      expected.cvq = uv_desc[0] ? q[2] : '0;
      expected.cq = q[2];

      if ($signed(area) < 0) begin
        expected.bx = x[2];
        expected.by = y[2];
        expected.bz = zd[2];
        expected.buq = '0;
        expected.bvq = q[2];
        expected.bq = q[2];

        expected.cx = x[1];
        expected.cy = y[1];
        expected.cz = zd[1];
        expected.cuq = q[1];
        expected.cvq = '0;
        expected.cq = q[1];
      end
    end
  endtask

  task automatic dump_triangle(input string prefix, input triangle_t value);
    begin
      $display("  %s id=%0d fbid=(%0d,%0d)", prefix,
               value.triangle_id, value.fbid_color, value.fbid_depth);
      $display("    A (%0d,%0d) z=%h uq=%h vq=%h q=%h",
               value.ax, value.ay, value.az, value.auq, value.avq, value.aq);
      $display("    B (%0d,%0d) z=%h uq=%h vq=%h q=%h",
               value.bx, value.by, value.bz, value.buq, value.bvq, value.bq);
      $display("    C (%0d,%0d) z=%h uq=%h vq=%h q=%h",
               value.cx, value.cy, value.cz, value.cuq, value.cvq, value.cq);
    end
  endtask

  task automatic check_triangle(
      input string name,
      input triangle_t actual,
      input triangle_t expected
  );
    begin
      if (actual !== expected) begin
        $error("%s: triangle mismatch", name);
        dump_triangle("actual", actual);
        dump_triangle("expected", expected);
        errcnt++;
      end
    end
  endtask

  task automatic drive_inputs(
      input logic [10:0] id,
      input int signed sx0,
      input int signed sy0,
      input int signed sx1,
      input int signed sy1,
      input int signed sx2,
      input int signed sy2,
      input data_t z0,
      input data_t z1,
      input data_t z2,
      input data_t inv_w0,
      input data_t inv_w1,
      input data_t inv_w2,
      input logic [1:0] color_id,
      input logic [1:0] depth_id
  );
    begin
      triangle_id = id;
      sx[0] = coord_in_t'(sx0);
      sx[1] = coord_in_t'(sx1);
      sx[2] = coord_in_t'(sx2);
      sy[0] = coord_in_t'(sy0);
      sy[1] = coord_in_t'(sy1);
      sy[2] = coord_in_t'(sy2);
      z[0] = z0;
      z[1] = z1;
      z[2] = z2;
      inv_w[0] = inv_w0;
      inv_w[1] = inv_w1;
      inv_w[2] = inv_w2;
      fbid_color = color_id;
      fbid_depth = depth_id;
    end
  endtask

  task automatic wait_for_input_ready(input string name);
    int cycles;
    begin
      cycles = 0;
      while (in_ready !== 1'b1 && cycles < TIMEOUT) begin
        @(negedge clk);
        cycles++;
      end
      if (in_ready !== 1'b1) begin
        $error("%s: timed out waiting for in_ready", name);
        errcnt++;
      end
    end
  endtask

  task automatic send_triangle(
      input  string name,
      input  logic [10:0] id,
      input  int signed sx0,
      input  int signed sy0,
      input  int signed sx1,
      input  int signed sy1,
      input  int signed sx2,
      input  int signed sy2,
      input  data_t z0,
      input  data_t z1,
      input  data_t z2,
      input  data_t inv_w0,
      input  data_t inv_w1,
      input  data_t inv_w2,
      input  logic [1:0] color_id,
      input  logic [1:0] depth_id,
      input  logic [5:0] uv_desc,
      output triangle_t expected
  );
    begin
      build_expected(id, sx0, sy0, sx1, sy1, sx2, sy2, z0, z1, z2,
                     inv_w0, inv_w1, inv_w2, color_id, depth_id, uv_desc, expected);
      @(negedge clk);
      wait_for_input_ready(name);
      drive_inputs(id, sx0, sy0, sx1, sy1, sx2, sy2, z0, z1, z2,
                   inv_w0, inv_w1, inv_w2, color_id, depth_id);
      in_valid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      in_valid = 1'b0;
    end
  endtask

  task automatic wait_for_output(input string name, input triangle_t expected);
    int cycles;
    begin
      cycles = 0;
      #1;
      while (out_valid !== 1'b1 && cycles < TIMEOUT) begin
        @(posedge clk);
        #1;
        cycles++;
      end
      if (out_valid !== 1'b1) begin
        $error("%s: timed out waiting for out_valid", name);
        errcnt++;
      end else begin
        check_triangle(name, triangle, expected);
      end
    end
  endtask

  task automatic consume_current_output(input string name, input triangle_t expected);
    begin
      wait_for_output(name, expected);
      @(posedge clk);
      #1;
    end
  endtask

  task automatic expect_no_output(input string name, input int unsigned cycles);
    begin
      for (int i = 0; i < cycles; i++) begin
        @(posedge clk);
        #1;
        if (out_valid !== 1'b0) begin
          $error("%s: unexpected out_valid at cycle %0d", name, i);
          dump_triangle("unexpected", triangle);
          errcnt++;
          return;
        end
      end
    end
  endtask

  task automatic tl_wait_a_ready(input string name);
    int cycles;
    begin
      cycles = 0;
      while (tl_d2h.a_ready !== 1'b1 && cycles < TIMEOUT) begin
        @(posedge clk);
        #1;
        cycles++;
      end
      if (tl_d2h.a_ready !== 1'b1) begin
        $error("%s: timed out waiting for TL a_ready", name);
        errcnt++;
      end
    end
  endtask

  task automatic tl_wait_d_valid(input string name);
    int cycles;
    begin
      cycles = 0;
      while (tl_d2h.d_valid !== 1'b1 && cycles < TIMEOUT) begin
        @(posedge clk);
        #1;
        cycles++;
      end
      if (tl_d2h.d_valid !== 1'b1) begin
        $error("%s: timed out waiting for TL d_valid", name);
        errcnt++;
      end
    end
  endtask

  task automatic tl_put_word(input string name, input logic [10:0] word_addr,
                             input logic [31:0] wdata);
    begin
      @(negedge clk);
      tl_h2d = TlIdle;
      tl_h2d.a_valid = 1'b1;
      tl_h2d.a_opcode = tlul_pkg::PutFullData;
      tl_h2d.a_size = 2;
      tl_h2d.a_source = 8'h5a;
      tl_h2d.a_address = {19'b0, word_addr, 2'b00};
      tl_h2d.a_mask = 4'hf;
      tl_h2d.a_data = wdata;

      @(posedge clk);
      #1;
      tl_wait_a_ready({name, "_a"});

      @(negedge clk);
      tl_h2d.a_valid = 1'b0;
      tl_h2d.d_ready = 1'b0;

      @(posedge clk);
      #1;
      tl_wait_d_valid({name, "_d"});
      if (tl_d2h.d_opcode !== tlul_pkg::AccessAck || tl_d2h.d_error !== 1'b0) begin
        $error("%s: bad TL write response opcode=%0d error=%0b",
               name, tl_d2h.d_opcode, tl_d2h.d_error);
        errcnt++;
      end

      @(negedge clk);
      tl_h2d.d_ready = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
      tl_h2d = TlIdle;
    end
  endtask

  task automatic tl_get_word(input string name, input logic [10:0] word_addr,
                             output logic [31:0] rdata);
    begin
      @(negedge clk);
      tl_h2d = TlIdle;
      tl_h2d.a_valid = 1'b1;
      tl_h2d.a_opcode = tlul_pkg::Get;
      tl_h2d.a_size = 2;
      tl_h2d.a_source = 8'ha5;
      tl_h2d.a_address = {19'b0, word_addr, 2'b00};
      tl_h2d.a_mask = 4'hf;

      @(posedge clk);
      #1;
      tl_wait_a_ready({name, "_a"});

      @(negedge clk);
      tl_h2d.a_valid = 1'b0;
      tl_h2d.d_ready = 1'b0;

      @(posedge clk);
      #1;
      tl_wait_d_valid({name, "_d"});
      rdata = tl_d2h.d_data;
      if (tl_d2h.d_opcode !== tlul_pkg::AccessAckData || tl_d2h.d_error !== 1'b0) begin
        $error("%s: bad TL read response opcode=%0d error=%0b",
               name, tl_d2h.d_opcode, tl_d2h.d_error);
        errcnt++;
      end

      @(negedge clk);
      tl_h2d.d_ready = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
      tl_h2d = TlIdle;
    end
  endtask

  task automatic check_uv_read(input string name, input logic [10:0] id,
                               input logic [5:0] expected);
    logic [31:0] rdata;
    begin
      tl_get_word(name, id, rdata);
      if (rdata[5:0] !== expected || rdata[31:6] !== '0) begin
        $error("%s: UV RAM read mismatch, expected 0x%02h got 0x%08h",
               name, expected, rdata);
        errcnt++;
      end
    end
  endtask

  task automatic reset_dut();
    begin
      rst_n = 1'b0;
      in_valid = 1'b0;
      triangle_id = '0;
      sx = '{default: '0};
      sy = '{default: '0};
      z = '{default: '0};
      inv_w = '{default: '0};
      fbid_color = '0;
      fbid_depth = '0;
      out_ready = 1'b1;
      tl_h2d = TlIdle;

      repeat (4) @(posedge clk);
      #1;
      if (out_valid !== 1'b0) begin
        $error("reset: out_valid is not low");
        errcnt++;
      end
      @(negedge clk);
      rst_n = 1'b1;
      @(posedge clk);
      #1;
      if (in_ready !== 1'b1 || out_valid !== 1'b0) begin
        $error("reset release: expected idle ready state");
        errcnt++;
      end
    end
  endtask

  task automatic check_idle_no_push();
    triangle_t prev_triangle;
    begin
      prev_triangle = triangle;
      out_ready = 1'b0;
      @(negedge clk);
      drive_inputs(11'd33, 15, 20, 85, 24, 40, 95,
                   32'sh0000_4000, 32'sh0000_8000, 32'sh0000_c000,
                   32'sh0001_0000, 32'sh0000_8000, 32'sh0000_4000,
                   2'd1, 2'd2);
      in_valid = 1'b0;
      repeat (2) begin
        @(posedge clk);
        #1;
        if (out_valid !== 1'b0 || in_ready !== 1'b1 || triangle !== prev_triangle) begin
          $error("idle_no_push: idle inputs changed module state");
          errcnt++;
        end
      end
      out_ready = 1'b1;
      repeat (2) begin
        @(posedge clk);
        #1;
        if (out_valid !== 1'b0 || in_ready !== 1'b1 || triangle !== prev_triangle) begin
          $error("idle_no_push_ready: idle inputs changed module state");
          errcnt++;
        end
      end
    end
  endtask

  task automatic check_single_triangle(
      input string name,
      input logic [10:0] id,
      input int signed sx0,
      input int signed sy0,
      input int signed sx1,
      input int signed sy1,
      input int signed sx2,
      input int signed sy2,
      input data_t z0,
      input data_t z1,
      input data_t z2,
      input data_t inv_w0,
      input data_t inv_w1,
      input data_t inv_w2,
      input logic [1:0] color_id,
      input logic [1:0] depth_id,
      input logic [5:0] uv_desc
  );
    triangle_t expected;
    begin
      out_ready = 1'b1;
      send_triangle(name, id, sx0, sy0, sx1, sy1, sx2, sy2,
                    z0, z1, z2, inv_w0, inv_w1, inv_w2,
                    color_id, depth_id, uv_desc, expected);
      consume_current_output(name, expected);
      if (out_valid !== 1'b0) begin
        $error("%s: FIFO not empty after consuming the single output", name);
        errcnt++;
      end
    end
  endtask

  task automatic check_all_uv_descriptors();
    logic [5:0] desc;
    begin
      for (int i = 0; i < 64; i++) begin
        desc = uv_desc_t'(i);
        tl_put_word($sformatf("write_uv_desc_%0d", i), TRIANGLE_ID_WIDTH'(300 + i),
                    {26'h0, desc});
        check_single_triangle(
          $sformatf("uv_desc_%0d", i),
          TRIANGLE_ID_WIDTH'(300 + i),
          70 + i, 80 + i,
          130 + i, 83 + i,
          90 + i, 155 + i,
          data_t'(32'sh0000_2000 + 32'sd16 * i),
          data_t'(32'sh0000_6000 + 32'sd16 * i),
          data_t'(32'sh0000_a000 + 32'sd16 * i),
          data_t'(32'sh0001_0000),
          data_t'(32'sh0000_8000),
          data_t'(32'sh0000_4000),
          2'd0,
          2'd0,
          desc
        );
      end
    end
  endtask

  task automatic check_all_fbid_pairs();
    begin
      for (int color = 0; color < 4; color++) begin
        for (int depth = 0; depth < 4; depth++) begin
          check_single_triangle(
            $sformatf("fbid_color_%0d_depth_%0d", color, depth),
            TRIANGLE_ID_WIDTH'(500 + 4 * color + depth),
            25 + color, 45 + depth,
            75 + color, 50 + depth,
            35 + color, 105 + depth,
            data_t'(32'sh0000_3000),
            data_t'(32'sh0000_7000),
            data_t'(32'sh0000_b000),
            data_t'(32'sh0001_0000),
            data_t'(32'sh0000_8000),
            data_t'(32'sh0000_4000),
            fbid_t'(color),
            fbid_t'(depth),
            6'h06
          );
        end
      end
    end
  endtask

  task automatic check_zero_uv_descriptor();
    begin
      tl_put_word("write_zero_uv", 11'd2045, 32'h0000_0000);
      check_uv_read("read_zero_uv", 11'd2045, 6'h00);
      check_single_triangle(
        "zero_uv_descriptor",
        11'd2045,
        500, 200,
        560, 205,
        510, 260,
        32'sh0000_1000,
        32'sh0000_5000,
        32'sh0000_9000,
        32'sh0001_0000,
        32'sh0000_8000,
        32'sh0000_4000,
        2'd2,
        2'd2,
        6'h00
      );
    end
  endtask

  task automatic check_extreme_data_values();
    begin
      tl_put_word("write_extreme_uv", 11'd2046, 32'h0000_003f);
      check_uv_read("read_extreme_uv", 11'd2046, 6'h3f);
      check_single_triangle(
        "signed_coords_depth_q_extremes",
        11'd2046,
        -20, -10,
        8191, -7,
        -15, 8190,
        32'sh0000_0000,
        32'sh7fff_ffff,
        32'sh0000_7fff,
        32'sh0000_0000,
        -32'sh0000_8000,
        32'sh0001_0000,
        2'd1,
        2'd0,
        6'h3f
      );
    end
  endtask

  task automatic check_max_id_and_tl_truncation();
    begin
      tl_put_word("write_max_id_truncate_uv", 11'd2047, 32'hffff_ffa5);
      check_uv_read("read_max_id_truncate_uv", 11'd2047, 6'h25);
      check_single_triangle(
        "max_triangle_id",
        11'd2047,
        600, 410,
        680, 415,
        620, 500,
        -32'sh0000_0001,
        32'sh0001_0000,
        32'sh0001_0001,
        32'sh0001_0000,
        -32'sh0000_4000,
        32'sh0000_0000,
        2'd3,
        2'd3,
        6'h25
      );
    end
  endtask

  task automatic check_reset_flushes_fifo();
    triangle_t expected;
    begin
      out_ready = 1'b0;
      send_triangle("reset_flush_queued", 11'd700,
                    10, 10, 90, 12, 30, 80,
                    32'sh0000_4000, 32'sh0000_8000, 32'sh0000_c000,
                    32'sh0001_0000, 32'sh0000_8000, 32'sh0000_4000,
                    2'd0, 2'd1, 6'h06, expected);
      #1;
      if (out_valid !== 1'b1) begin
        $error("reset_flush: queued output did not become valid");
        errcnt++;
      end
      reset_dut();
      expect_no_output("reset_flush", 4);
    end
  endtask

  task automatic check_degenerate_drop();
    triangle_t prev_triangle;
    begin
      prev_triangle = triangle;
      out_ready = 1'b1;
      @(negedge clk);
      wait_for_input_ready("degenerate");
      drive_inputs(11'd55, 10, 10, 20, 20, 30, 30,
                   32'sh0000_4000, 32'sh0000_8000, 32'sh0000_c000,
                   32'sh0001_0000, 32'sh0001_0000, 32'sh0001_0000,
                   2'd1, 2'd2);
      in_valid = 1'b1;
      @(posedge clk);
      #1;
      if (in_ready !== 1'b1) begin
        $error("degenerate: in_ready dropped for a zero-area triangle");
        errcnt++;
      end
      @(negedge clk);
      in_valid = 1'b0;
      expect_no_output("degenerate", 8);
      if (triangle !== prev_triangle) begin
        $error("degenerate: output changed even though the triangle was dropped");
        errcnt++;
      end
    end
  endtask

  task automatic check_fifo_backpressure();
    triangle_t expected [FIFO_DEPTH-1:0];
    begin
      out_ready = 1'b0;
      for (int i = 0; i < FIFO_DEPTH; i++) begin
        send_triangle($sformatf("fifo_fill_%0d", i), TRIANGLE_ID_WIDTH'(100 + i),
                      10 + 7*i, 20 + 3*i,
                      60 + 5*i, 23 + 4*i,
                      25 + 6*i, 75 + 2*i,
                      data_t'(32'sh0000_1000 + 32'sd512 * i),
                      data_t'(32'sh0000_8000 + 32'sd256 * i),
                      data_t'(32'sh0001_0000 + 32'sd128 * i),
                      data_t'(32'sh0001_0000),
                      data_t'(32'sh0000_8000),
                      data_t'(32'sh0000_4000),
                      fbid_t'(i), fbid_t'(i + 1), 6'h06, expected[i]);
      end

      #1;
      if (in_ready !== 1'b0 || out_valid !== 1'b1) begin
        $error("fifo_backpressure: FIFO did not report full with a valid head");
        errcnt++;
      end
      repeat (3) begin
        @(posedge clk);
        #1;
        if (out_valid !== 1'b1 || in_ready !== 1'b0) begin
          $error("fifo_backpressure: full FIFO state was not held");
          errcnt++;
        end
        check_triangle("fifo_backpressure_held_head", triangle, expected[0]);
      end

      out_ready = 1'b1;
      for (int i = 0; i < FIFO_DEPTH; i++) begin
        consume_current_output($sformatf("fifo_drain_%0d", i), expected[i]);
      end
      if (out_valid !== 1'b0 || in_ready !== 1'b1) begin
        $error("fifo_backpressure: FIFO did not return to idle after drain");
        errcnt++;
      end
    end
  endtask

  task automatic check_full_input_stall();
    triangle_t expected [FIFO_DEPTH:0];
    begin
      out_ready = 1'b0;
      for (int i = 0; i < FIFO_DEPTH; i++) begin
        send_triangle($sformatf("stall_fill_%0d", i), TRIANGLE_ID_WIDTH'(200 + i),
                      30 + 4*i, 40 + i,
                      80 + 5*i, 42 + 2*i,
                      38 + 6*i, 90 + 3*i,
                      data_t'(32'sh0000_2000 + 32'sd1024 * i),
                      data_t'(32'sh0000_9000 + 32'sd512 * i),
                      data_t'(32'sh0000_f000 + 32'sd256 * i),
                      data_t'(32'sh0001_0000),
                      data_t'(32'sh0000_c000),
                      data_t'(32'sh0000_6000),
                      2'd3, 2'd1, 6'h06, expected[i]);
      end

      build_expected(11'd250, 300, 320, 360, 330, 310, 390,
                     32'sh0000_4000, 32'sh0000_a000, 32'sh0001_4000,
                     32'sh0001_0000, 32'sh0000_8000, 32'sh0000_4000,
                     2'd2, 2'd3, 6'h06, expected[FIFO_DEPTH]);

      @(negedge clk);
      drive_inputs(11'd250, 300, 320, 360, 330, 310, 390,
                   32'sh0000_4000, 32'sh0000_a000, 32'sh0001_4000,
                   32'sh0001_0000, 32'sh0000_8000, 32'sh0000_4000,
                   2'd2, 2'd3);
      in_valid = 1'b1;
      repeat (2) begin
        @(posedge clk);
        #1;
        if (in_ready !== 1'b0) begin
          $error("full_input_stall: in_ready rose while FIFO was still full");
          errcnt++;
        end
        check_triangle("full_input_stall_head", triangle, expected[0]);
      end

      out_ready = 1'b1;
      @(posedge clk);
      #1;
      check_triangle("full_input_stall_after_first_pop", triangle, expected[1]);
      if (in_ready !== 1'b1) begin
        $error("full_input_stall: in_ready did not rise after a pop");
        errcnt++;
      end

      @(posedge clk);
      #1;
      @(negedge clk);
      in_valid = 1'b0;

      for (int i = 2; i <= FIFO_DEPTH; i++) begin
        consume_current_output($sformatf("full_input_stall_drain_%0d", i), expected[i]);
      end
      if (out_valid !== 1'b0 || in_ready !== 1'b1) begin
        $error("full_input_stall: FIFO did not return to idle");
        errcnt++;
      end
    end
  endtask

  initial begin
    errcnt = 0;
    reset_dut();
    check_idle_no_push();

    check_uv_read("default_uv_read_id0", 11'd0, 6'h06);

    check_single_triangle(
      "default_positive",
      11'd0,
      10, 20,
      50, 25,
      20, 70,
      32'shffff_0000,
      32'sh0000_8000,
      32'sh0001_4000,
      32'sh0001_0000,
      32'sh0000_8000,
      32'sh0000_4000,
      2'd2,
      2'd1,
      6'h06
    );

    tl_put_word("write_all_uv", 11'd7, 32'h0000_003f);
    check_uv_read("read_all_uv", 11'd7, 6'h3f);
    check_single_triangle(
      "tl_programmed_all_uv",
      11'd7,
      100, 100,
      180, 110,
      120, 190,
      32'sh0000_0001,
      32'sh0000_ffff,
      32'sh0001_0000,
      32'sh0001_0000,
      32'sh0000_8000,
      32'sh0000_2000,
      2'd3,
      2'd0,
      6'h3f
    );

    tl_put_word("write_geometry_uv_a", 11'd8, 32'h0000_0018);
    check_uv_read("read_geometry_uv_a", 11'd8, 6'h18);
    check_single_triangle(
      "software_geometry_uv_a",
      11'd8,
      210, 110,
      260, 145,
      215, 180,
      32'sh0000_4000,
      32'sh0000_9000,
      32'sh0000_c000,
      32'sh0001_0000,
      32'sh0000_c000,
      32'sh0000_6000,
      2'd1,
      2'd3,
      6'h18
    );

    tl_put_word("write_negative_uv", 11'd9, 32'h0000_0029);
    check_uv_read("read_negative_uv", 11'd9, 6'h29);
    check_single_triangle(
      "negative_winding",
      11'd9,
      400, 300,
      430, 360,
      470, 310,
      32'sh0000_2000,
      32'sh0000_7000,
      32'sh0001_2000,
      32'sh0001_0000,
      32'sh0000_8000,
      32'sh0000_4000,
      2'd0,
      2'd2,
      6'h29
    );

    check_all_uv_descriptors();
    check_all_fbid_pairs();
    check_zero_uv_descriptor();
    check_extreme_data_values();
    check_max_id_and_tl_truncation();
    check_degenerate_drop();
    check_fifo_backpressure();
    check_full_input_stall();
    check_reset_flushes_fifo();

    if (errcnt == 0) begin
      $display("### TESTS PASSED ###");
    end else begin
      $display("### TESTS FAILED: %0d errors ###", errcnt);
      $fatal(1);
    end
    $finish;
  end

endmodule
