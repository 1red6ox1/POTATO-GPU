// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2026 David Schröder
//
// Self-checking, module-level testbench for pixel_fetcher.
//
// Instead of a full DDR3 model, this testbench replaces the memory
// with a tiny combinational "fake DDR" responder: it decodes the
// block address requested by the DUT, synthesizes the 32-pixel chunk
// on the fly with a deterministic function, and returns it through a
// fixed-latency shift register (with optional random request-side
// backpressure). This is enough to exercise the pixel_fetcher's
// request/response handshake and internal buffering without paying
// for DDR3 timing/initialization.
//
// Frame dimensions are intentionally tiny (and not simple powers of
// two) so that:
//  - a full frame spans more 32-pixel blocks than DEPTH holds, forcing
//    the block buffer to wrap around multiple times per frame, and
//  - the whole test finishes in a handful of microseconds.

module pixel_fetcher_tb;

  import rvlab_ddr_pkg::*;
  import tlul_pkg::*;

  // ------------------------------------------------------------------
  // DUT parameters
  // ------------------------------------------------------------------
  localparam int DEPTH  = 4;  // 4 blocks * 32 px = 128 px buffered
  localparam int FRAMEW = 64; // 2 chunks per row
  localparam int FRAMEH = 3;  // 3 rows -> 6 blocks/frame (> DEPTH)

  localparam int DDR_LATENCY = 3; // fixed request->response latency of the fake memory

  localparam logic [1:0] TARGET_FRAME_ID = 2'd3; // frame id to switch to after frame 0

  // ------------------------------------------------------------------
  // Clock / reset
  // ------------------------------------------------------------------
  logic clk = 1'b0;
  logic rst_n;

  always #5000 clk = ~clk; // 100 MHz

  // ------------------------------------------------------------------
  // DUT signals
  // ------------------------------------------------------------------
  ddr3_h2d_t req;
  ddr3_d2h_t rsp;

  logic [ 7:0] r, g, b;
  logic        enable;
  logic [ 1:0] next_frame_id;
  logic [10:0] cx, cy;
  logic        valid;
  logic        consume;

  int unsigned errcnt = 0;

  pixel_fetcher #(
      .DEPTH (DEPTH),
      .FRAMEW(FRAMEW),
      .FRAMEH(FRAMEH)
  ) dut (
      .clk_i          (clk),
      .rst_ni         (rst_n),
      .req_o          (req),
      .rsp_i          (rsp),
      .r_o            (r),
      .g_o            (g),
      .b_o            (b),
      .enable_i       (enable),
      .next_frame_id_i(next_frame_id),
      .cx_o           (cx),
      .cy_o           (cy),
      .valid_o        (valid),
      .consume_i      (consume)
  );

  // ------------------------------------------------------------------
  // Golden pixel-value function.
  // Shared between the fake memory (to generate content) and the
  // checker (to predict expected content), so both sides always agree
  // on what a given (channel, frame_id, cx, cy) pixel must look like.
  // ------------------------------------------------------------------
  function automatic logic [7:0] pixel_value(
      input logic [ 1:0] channel,
      input logic [ 1:0] frame_id,
      input logic [10:0] px_cx,
      input logic [10:0] px_cy
  );
    pixel_value = (8'(px_cx) ^ 8'(px_cy) ^ {frame_id, channel, 4'b0})
                + 8'(px_cx[10:3]) + 8'(px_cy[10:3]);
  endfunction

  function automatic logic [255:0] gen_chunk_data(
      input logic [ 1:0] channel,
      input logic [ 1:0] frame_id,
      input logic [10:0] chunk_cy,
      input logic [ 5:0] chunk_cx
  );
    logic [255:0] word;
    for (int i = 0; i < 32; i++) begin
      word[i*8+:8] = pixel_value(channel, frame_id, 11'(chunk_cx) * 32 + 11'(i), chunk_cy);
    end
    gen_chunk_data = word;
  endfunction

  // ------------------------------------------------------------------
  // Fake DDR responder
  //   - Decodes the block address per pixel_fetcher.sv's own comment:
  //     {3'h0, frame, cy, cx(chunk), channel}
  //   - Presents a_ready with optional pseudo-random stalls.
  //   - Delivers d_valid/d_data/d_anc DDR_LATENCY cycles after a
  //     request is accepted, preserving request order (a plain shift
  //     register), matching the "guaranteed in-order responses"
  //     contract documented in rvlab_ddr_pkg.
  // ------------------------------------------------------------------
  logic mem_stall_en = 1'b0;
  logic mem_ready_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) mem_ready_q <= 1'b1;
    else mem_ready_q <= !mem_stall_en || ($urandom_range(0, 3) != 0); // ~75% ready when stalling
  end

  assign rsp.a_ready = mem_ready_q;

  logic                        pipe_valid_q[DDR_LATENCY];
  logic [rvlab_ddr_pkg::DDR_ANCW-1:0] pipe_anc_q [DDR_LATENCY];
  logic [                255:0] pipe_data_q [DDR_LATENCY];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < DDR_LATENCY; i++) pipe_valid_q[i] <= 1'b0;
    end else begin
      for (int i = DDR_LATENCY - 1; i > 0; i--) begin
        pipe_valid_q[i] <= pipe_valid_q[i-1];
        pipe_anc_q[i]   <= pipe_anc_q[i-1];
        pipe_data_q[i]  <= pipe_data_q[i-1];
      end
      if (req.a_valid && rsp.a_ready) begin
        pipe_valid_q[0] <= 1'b1;
        pipe_anc_q[0]   <= req.a_anc;
        pipe_data_q[0]  <= gen_chunk_data(
            req.a_address[1:0],   // channel
            req.a_address[20:19], // frame id
            req.a_address[18:8],  // cy
            req.a_address[7:2]    // cx (chunk index)
        );
      end else begin
        pipe_valid_q[0] <= 1'b0;
      end
    end
  end

  assign rsp.d_valid  = pipe_valid_q[DDR_LATENCY-1];
  assign rsp.d_opcode = tlul_pkg::AccessAckData;
  assign rsp.d_data   = pipe_data_q[DDR_LATENCY-1];
  assign rsp.d_anc    = pipe_anc_q[DDR_LATENCY-1];

  // ------------------------------------------------------------------
  // Consumer-side readiness (drives consume_i). Set up on the negative
  // edge so it is stable before the following posedge, like a real
  // downstream (HDMI) consumer would present it.
  // ------------------------------------------------------------------
  logic consumer_stall_en = 1'b0;
  logic consumer_ready_q;

  always_ff @(negedge clk or negedge rst_n) begin
    if (!rst_n) consumer_ready_q <= 1'b1;
    else consumer_ready_q <= !consumer_stall_en || ($urandom_range(0, 4) != 0); // ~80% ready when stalling
  end

  assign consume = consumer_ready_q;

  // ------------------------------------------------------------------
  // Golden model / checker state (persists across test phases so that
  // streaming can be resumed/paused without losing track of position)
  // ------------------------------------------------------------------
  logic [10:0] exp_cx = '0;
  logic [10:0] exp_cy = '0;
  logic [ 1:0] exp_frame_id = '0;

  logic        prev_valid = 1'b0;
  logic        prev_consume = 1'b0;
  logic [ 7:0] prev_r, prev_g, prev_b;
  logic [10:0] prev_cx, prev_cy;

  // ------------------------------------------------------------------
  // Tasks
  // ------------------------------------------------------------------

  task automatic reset_dut();
    rst_n             = 1'b0;
    enable            = 1'b0;
    next_frame_id     = TARGET_FRAME_ID;
    consumer_stall_en = 1'b0;
    mem_stall_en      = 1'b0;
    exp_cx            = '0;
    exp_cy            = '0;
    exp_frame_id      = '0;
    prev_valid        = 1'b0;

    repeat (4) @(posedge clk);
    #1;

    if (valid !== 1'b0) begin
      $error("reset_dut: valid_o is not low during reset");
      errcnt++;
    end
    if (req.a_valid !== 1'b0) begin
      $error("reset_dut: req_o.a_valid is not low during reset (enable_i is low)");
      errcnt++;
    end

    @(negedge clk);
    rst_n = 1'b1;
  endtask

  // Advances one clock, checks output stability while stalled, and
  // (if a beat completes) checks pixel content/coordinates against the
  // golden model, then advances the golden model. Returns 1 if a beat
  // was consumed this cycle.
  task automatic step_and_check(output bit consumed);
    logic [7:0] exp_r, exp_g, exp_b;

    @(posedge clk);

    consumed = 1'b0;

    // Stability: while a pixel was valid and not consumed, it must not
    // change on the following cycle (per pixel_fetcher.sv: "Pixel data
    // and coordinates remain stable while valid_o is waiting.")
    if (prev_valid && !prev_consume) begin
      if (valid !== 1'b1 || r !== prev_r || g !== prev_g || b !== prev_b ||
          cx !== prev_cx || cy !== prev_cy) begin
        $error("step_and_check: output changed while consume_i was low (prev cx=%0d cy=%0d r=%0h g=%0h b=%0h valid=%0d -> now cx=%0d cy=%0d r=%0h g=%0h b=%0h valid=%0d)",
               prev_cx, prev_cy, prev_r, prev_g, prev_b, prev_valid,
               cx, cy, r, g, b, valid);
        errcnt++;
      end
    end

    if (valid && consume) begin
      consumed = 1'b1;

      exp_r = pixel_value(2'b00, exp_frame_id, exp_cx, exp_cy);
      exp_g = pixel_value(2'b01, exp_frame_id, exp_cx, exp_cy);
      exp_b = pixel_value(2'b10, exp_frame_id, exp_cx, exp_cy);

      if (cx !== exp_cx || cy !== exp_cy) begin
        $error("step_and_check: coordinate mismatch: expected (cx=%0d,cy=%0d), got (cx=%0d,cy=%0d)",
               exp_cx, exp_cy, cx, cy);
        errcnt++;
      end
      if (r !== exp_r || g !== exp_g || b !== exp_b) begin
        $error("step_and_check: pixel data mismatch at (cx=%0d,cy=%0d,frame=%0d): expected rgb=%02h/%02h/%02h, got %02h/%02h/%02h",
               exp_cx, exp_cy, exp_frame_id, exp_r, exp_g, exp_b, r, g, b);
        errcnt++;
      end

      // Advance golden raster position (mirrors the DUT's expected
      // raster order and frame-id capture at the frame boundary).
      if (exp_cx == FRAMEW - 1) begin
        exp_cx = '0;
        if (exp_cy == FRAMEH - 1) begin
          exp_cy       = '0;
          exp_frame_id = next_frame_id;
        end else begin
          exp_cy = exp_cy + 11'd1;
        end
      end else begin
        exp_cx = exp_cx + 11'd1;
      end
    end

    prev_valid   = valid;
    prev_consume = consume;
    prev_r       = r;
    prev_g       = g;
    prev_b       = b;
    prev_cx      = cx;
    prev_cy      = cy;
  endtask

  // Streams and checks exactly `n` pixels.
  task automatic run_and_check(input int n);
    bit consumed;
    int got;
    got = 0;
    while (got < n) begin
      step_and_check(consumed);
      if (consumed) got++;
    end
  endtask

  // ------------------------------------------------------------------
  // Test sequence
  // ------------------------------------------------------------------
  initial begin
    reset_dut();

    // ---- Test 1: basic single-frame streaming, no stalls ----------
    // Exercises raster ordering, per-pixel content and the block
    // buffer wrap (6 blocks/frame > DEPTH=4) with everything running
    // at full rate.
    enable = 1'b1;
    run_and_check(FRAMEW * FRAMEH);
    $display("pixel_fetcher_tb: Test 1 (full-rate single frame) done, errcnt=%0d", errcnt);

    // ---- Test 2: second frame with request/consumer backpressure --
    // next_frame_id_i has been held at TARGET_FRAME_ID since reset, so
    // this frame must be produced with that frame id. Both the fake
    // memory and the consumer randomly stall to exercise the ready/
    // valid handshake and stability of the output stage under stalls.
    consumer_stall_en = 1'b1;
    mem_stall_en      = 1'b1;
    run_and_check(FRAMEW * FRAMEH);
    consumer_stall_en = 1'b0;
    mem_stall_en      = 1'b0;
    $display("pixel_fetcher_tb: Test 2 (backpressure, frame id switch) done, errcnt=%0d", errcnt);

    // ---- Test 3: disable mid-stream, verify clean shutdown --------
    @(posedge clk);
    #1;
    enable = 1'b0;
    @(posedge clk);
    #1;
    if (valid !== 1'b0) begin
      $error("Test 3: valid_o did not deassert one cycle after enable_i went low");
      errcnt++;
    end
    if (req.a_valid !== 1'b0) begin
      $error("Test 3: req_o.a_valid is not low while enable_i is low");
      errcnt++;
    end
    // Let the fake memory's response pipeline flush harmlessly while disabled.
    repeat (DDR_LATENCY + 2) @(posedge clk);

    // ---- Test 4: re-enable, verify clean restart at (0,0), frame 0 -
    // pixel_fetcher.sv resets cur_frame_id to 0 whenever enable_i is
    // deasserted, regardless of next_frame_id_i, so the next frame
    // must restart at frame id 0.
    exp_cx       = '0;
    exp_cy       = '0;
    exp_frame_id = '0;
    prev_valid   = 1'b0;
    next_frame_id = TARGET_FRAME_ID;
    enable        = 1'b1;
    run_and_check(FRAMEW * FRAMEH);
    $display("pixel_fetcher_tb: Test 4 (disable/re-enable restart) done, errcnt=%0d", errcnt);

    // ---- Final idle check -------------------------------------------
    enable = 1'b0;
    repeat (3) @(posedge clk);
    #1;
    if (valid !== 1'b0) begin
      $error("Final check: valid_o is not low after disabling");
      errcnt++;
    end

    if (errcnt > 0) begin
      $display("### TESTS FAILED WITH %0d ERRORS ###", errcnt);
    end else begin
      $display("### TESTS PASSED ###");
    end

    $finish;
  end

  // Safety timeout in case of a stuck handshake.
  initial begin
    #1_000_000_000;
    $error("pixel_fetcher_tb: TIMEOUT - simulation did not finish");
    $finish;
  end

endmodule
