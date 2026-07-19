// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2026 RVLab Contributors

module vertex_pipeline_integration_tb;
  import rasterizer_pkg::*;

  localparam int DATA_WIDTH = 32;
  localparam int TRI_ID_WIDTH = 10;
  localparam int VTX_ID_WIDTH = 2;
  localparam int NUM_TRIS = 12;
  localparam int NUM_VERTS = 3;
  localparam int MAT_DIM = 4;
  localparam int ONE_Q16 = 32'sh0001_0000;
  localparam int HALF_SCREEN_W = FRAME_WIDTH / 2;
  localparam int HALF_SCREEN_H = FRAME_HEIGHT / 2;

  localparam logic [31:0] VERTEX_TRIANGLE_COUNT_ADDR = 32'h0000_0040;
  localparam logic [31:0] VERTEX_START_RENDER_ADDR   = 32'h0000_0044;

  typedef logic signed [DATA_WIDTH-1:0] data_t;
  typedef data_t vec4_t [MAT_DIM];

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  tlul_pkg::tl_h2d_t tl_cfg_h2d;
  tlul_pkg::tl_d2h_t tl_cfg_d2h;
  tlul_pkg::tl_h2d_t tl_vec_h2d;
  tlul_pkg::tl_d2h_t tl_vec_d2h;

  logic                         vertex_out_valid;
  logic                         vertex_out_ready;
  logic [TRI_ID_WIDTH-1:0]      vertex_out_id;
  data_t                        vertex_out_vec [3:0];

  logic                         post_in_valid;
  logic                         post_in_ready;
  logic [TRI_ID_WIDTH-1:0]      post_in_id;
  data_t                        post_x [2:0];
  data_t                        post_y [2:0];
  data_t                        post_z [2:0];
  data_t                        post_w [2:0];

  logic                         post_out_valid;
  logic [10:0]                  post_sx [2:0];
  logic [10:0]                  post_sy [2:0];
  data_t                        post_ndc_z [2:0];
  data_t                        post_inv_w [2:0];

  logic                         adapter_ready;
  triangle2d_t                  triangle2d;
  logic                         triangle2d_valid;
  logic                         triangle2d_ready;

  rasterization_param_t         raster_param;
  logic                         raster_param_valid;
  logic                         raster_param_ready;
  logic                         raster_param_in_ready;

  int unsigned errcnt;
  int unsigned triangle2d_count;
  int unsigned raster_param_count;
  int unsigned cycle_count;

  localparam tlul_pkg::tl_h2d_t TlIdle = '{a_opcode: tlul_pkg::PutFullData, default: '0};

  always #10000 clk = ~clk;

  initial begin
    repeat (20000) @(posedge clk);
    $display("### TESTS FAILED: GLOBAL WATCHDOG TIMEOUT ###");
    $fatal(1);
  end

  vertex_processor #(
    .DATA_WIDTH(DATA_WIDTH),
    .OUT_WIDTH (DATA_WIDTH)
  ) vertex_processor_i (
    .clk_i(clk),
    .rst_ni      (rst_n),
    .tl_cfg_i    (tl_cfg_h2d),
    .tl_cfg_o    (tl_cfg_d2h),
    .tl_vec_i    (tl_vec_h2d),
    .tl_vec_o    (tl_vec_d2h),
    .out_valid_o (vertex_out_valid),
    .out_ready_i (vertex_out_ready),
    .out_id_o    (vertex_out_id),
    .out_vec_o   (vertex_out_vec)
  );

  vertex_triangle_collector #(
    .DATA_WIDTH  (DATA_WIDTH),
    .TRI_ID_WIDTH(TRI_ID_WIDTH)
  ) vertex_triangle_collector_i (
    .clk_i(clk),
    .rst_ni      (rst_n),
    .in_valid_i  (vertex_out_valid),
    .in_ready_o  (vertex_out_ready),
    .in_id_i     (vertex_out_id),
    .in_vec_i    (vertex_out_vec),
    .out_valid_o (post_in_valid),
    .out_ready_i (post_in_ready),
    .out_id_o    (post_in_id),
    .out_x_o     (post_x),
    .out_y_o     (post_y),
    .out_z_o     (post_z),
    .out_w_o     (post_w)
  );

  vertex_post #(
    .DATA_WIDTH(DATA_WIDTH),
    .FRAC_WIDTH(16),
    .SCREEN_W  (FRAME_WIDTH),
    .SCREEN_H  (FRAME_HEIGHT),
    .SX_WIDTH  (11),
    .SY_WIDTH  (11)
  ) vertex_post_i (
    .clk       (clk),
    .rst_n     (rst_n),
    .in_valid  (post_in_valid),
    .ready_o   (post_in_ready),
    .x_i       (post_x),
    .y_i       (post_y),
    .z_i       (post_z),
    .w_i       (post_w),
    .tri_id_i    ({1'b0, post_in_id}),
    .out_valid   (post_out_valid),
    .out_ready_i (adapter_ready),
    .sx_o        (post_sx),
    .sy_o      (post_sy),
    .z_o       (post_ndc_z),
    .inv_w_o   (post_inv_w),
    .tri_id_o  ()
  );

  vertex_post_to_triangle2d #(
    .FIFO_DEPTH(4)
  ) vertex_post_to_triangle2d_i (
    .clk_i(clk),
    .rst_ni       (rst_n),
    .in_ready_o   (adapter_ready),
    .in_valid_i   (post_out_valid),
    .sx_i         (post_sx),
    .sy_i         (post_sy),
    .z_i          (post_ndc_z),
    .inv_w_i      (post_inv_w),
    .triangle2d_o (triangle2d),
    .out_valid_o  (triangle2d_valid),
    .out_ready_i  (triangle2d_ready)
  );

  rasterizer_param rasterizer_param_i (
    .clk_i(clk),
    .rst_ni       (rst_n),
    .triangle2d_i (triangle2d),
    .in_valid_i   (triangle2d_valid),
    .in_ready_o   (raster_param_in_ready),
    .param_o      (raster_param),
    .out_valid_o  (raster_param_valid),
    .out_ready_i  (raster_param_ready)
  );

  assign triangle2d_ready = raster_param_in_ready;

  function automatic data_t q16_coord(input int signed value_q16);
    return data_t'(value_q16);
  endfunction

  function automatic logic signed [COORD_WIDTH-1:0] viewport_x(input data_t x_q16);
    logic signed [63:0] px;
    begin
      px = ($signed(64'(x_q16)) + ONE_Q16) * HALF_SCREEN_W >>> 16;
      if (px < 0) viewport_x = '0;
      else if (px > FRAME_WIDTH - 1) viewport_x = COORD_WIDTH'(FRAME_WIDTH - 1);
      else viewport_x = COORD_WIDTH'(px);
    end
  endfunction

  function automatic logic signed [COORD_WIDTH-1:0] viewport_y(input data_t y_q16);
    logic signed [63:0] py;
    begin
      py = (ONE_Q16 - $signed(64'(y_q16))) * HALF_SCREEN_H >>> 16;
      if (py < 0) viewport_y = '0;
      else if (py > FRAME_HEIGHT - 1) viewport_y = COORD_WIDTH'(FRAME_HEIGHT - 1);
      else viewport_y = COORD_WIDTH'(py);
    end
  endfunction

  function automatic vec4_t test_vertex(input int unsigned triangle, input int unsigned vertex);
    int signed base_x;
    int signed base_y;
    begin
      base_x = -32'sh0000_7000 + int'(triangle % 4) * 32'sh0000_3000;
      base_y = -32'sh0000_5000 + int'(triangle / 4) * 32'sh0000_3000;

      unique case (vertex)
        0: test_vertex = '{q16_coord(base_x), q16_coord(base_y),
                           32'sh0000_8000, 32'sh0001_0000};
        1: test_vertex = '{q16_coord(base_x + 32'sh0000_1800), q16_coord(base_y),
                           32'sh0000_8000, 32'sh0001_0000};
        default: test_vertex = '{q16_coord(base_x), q16_coord(base_y + 32'sh0000_1800),
                                32'sh0000_8000, 32'sh0001_0000};
      endcase
    end
  endfunction

  task automatic clear_inputs();
    tl_cfg_h2d = TlIdle;
    tl_vec_h2d = TlIdle;
    raster_param_ready = 1'b0;
  endtask

  task automatic cfg_tl_put(input logic [31:0] addr, input logic [31:0] wdata);
    int unsigned timeout;
    @(negedge clk);
    tl_cfg_h2d.a_address = addr;
    tl_cfg_h2d.a_opcode  = tlul_pkg::PutFullData;
    tl_cfg_h2d.a_size    = 2'h2;
    tl_cfg_h2d.a_data    = wdata;
    tl_cfg_h2d.a_mask    = 4'hF;
    tl_cfg_h2d.a_valid   = 1'b1;

    timeout = 0;
    while (!tl_cfg_d2h.a_ready && timeout < 40) begin
      @(negedge clk);
      timeout++;
    end
    if (!tl_cfg_d2h.a_ready) begin
      $error("cfg_tl_put: timeout waiting for a_ready at 0x%08x", addr);
      errcnt++;
    end
    @(posedge clk);

    @(negedge clk);
    tl_cfg_h2d.a_valid = 1'b0;
    tl_cfg_h2d.d_ready = 1'b1;
    timeout = 0;
    while (!tl_cfg_d2h.d_valid && timeout < 40) begin
      @(negedge clk);
      timeout++;
    end
    if (!tl_cfg_d2h.d_valid) begin
      $error("cfg_tl_put: timeout waiting for d_valid at 0x%08x", addr);
      errcnt++;
    end
    @(posedge clk);
    @(negedge clk);
    tl_cfg_h2d.d_ready = 1'b0;
  endtask

  task automatic vec_tl_put(input logic [31:0] addr, input logic [31:0] wdata);
    int unsigned timeout;
    @(negedge clk);
    tl_vec_h2d.a_address = addr;
    tl_vec_h2d.a_opcode  = tlul_pkg::PutFullData;
    tl_vec_h2d.a_size    = 2'h2;
    tl_vec_h2d.a_data    = wdata;
    tl_vec_h2d.a_mask    = 4'hF;
    tl_vec_h2d.a_valid   = 1'b1;

    timeout = 0;
    while (!tl_vec_d2h.a_ready && timeout < 40) begin
      @(negedge clk);
      timeout++;
    end
    if (!tl_vec_d2h.a_ready) begin
      $error("vec_tl_put: timeout waiting for a_ready at 0x%08x", addr);
      errcnt++;
    end
    @(posedge clk);

    @(negedge clk);
    tl_vec_h2d.a_valid = 1'b0;
    tl_vec_h2d.d_ready = 1'b1;
    timeout = 0;
    while (!tl_vec_d2h.d_valid && timeout < 40) begin
      @(negedge clk);
      timeout++;
    end
    if (!tl_vec_d2h.d_valid) begin
      $error("vec_tl_put: timeout waiting for d_valid at 0x%08x", addr);
      errcnt++;
    end
    @(posedge clk);
    @(negedge clk);
    tl_vec_h2d.d_ready = 1'b0;
  endtask

  task automatic cfg_write_word(input logic [1:0] row, input logic [1:0] col,
                                input data_t value);
    cfg_tl_put({26'b0, row, col, 2'b00}, value);
  endtask

  task automatic vec_write_lane(input logic [TRI_ID_WIDTH-1:0] triangle_id,
                                input logic [VTX_ID_WIDTH-1:0] vertex_id,
                                input logic [1:0] lane,
                                input data_t value);
    vec_tl_put({16'b0, triangle_id, vertex_id, lane, 2'b00}, value);
  endtask

  task automatic write_identity_matrix();
    for (int row = 0; row < MAT_DIM; row++) begin
      for (int col = 0; col < MAT_DIM; col++) begin
        cfg_write_word(row[1:0], col[1:0], row == col ? 32'sh0001_0000 : 32'sh0000_0000);
      end
    end
  endtask

  task automatic write_test_scene();
    vec4_t vertex;
    for (int triangle = 0; triangle < NUM_TRIS; triangle++) begin
      for (int v = 0; v < NUM_VERTS; v++) begin
        vertex = test_vertex(triangle, v);
        for (int lane = 0; lane < MAT_DIM; lane++) begin
          vec_write_lane(TRI_ID_WIDTH'(triangle), VTX_ID_WIDTH'(v), lane[1:0], vertex[lane]);
        end
      end
    end
  endtask

  task automatic start_render();
    cfg_tl_put(VERTEX_TRIANGLE_COUNT_ADDR, NUM_TRIS - 1);
    cfg_tl_put(VERTEX_START_RENDER_ADDR, 32'h0000_0001);
  endtask

  task automatic check_triangle2d(input triangle2d_t actual, input int unsigned index);
    vec4_t v0;
    vec4_t v1;
    vec4_t v2;
    logic signed [COORD_WIDTH-1:0] ax;
    logic signed [COORD_WIDTH-1:0] ay;
    logic signed [COORD_WIDTH-1:0] bx;
    logic signed [COORD_WIDTH-1:0] by;
    logic signed [COORD_WIDTH-1:0] cx;
    logic signed [COORD_WIDTH-1:0] cy;
    logic signed [2*COORD_WIDTH+2:0] area;
    begin
      v0 = test_vertex(index, 0);
      v1 = test_vertex(index, 1);
      v2 = test_vertex(index, 2);

      ax = viewport_x(v0[0]);
      ay = viewport_y(v0[1]);
      bx = viewport_x(v1[0]);
      by = viewport_y(v1[1]);
      cx = viewport_x(v2[0]);
      cy = viewport_y(v2[1]);

      area = ($signed({bx[COORD_WIDTH-1], bx}) - $signed({ax[COORD_WIDTH-1], ax}))
           * ($signed({cy[COORD_WIDTH-1], cy}) - $signed({ay[COORD_WIDTH-1], ay}))
           - ($signed({by[COORD_WIDTH-1], by}) - $signed({ay[COORD_WIDTH-1], ay}))
           * ($signed({cx[COORD_WIDTH-1], cx}) - $signed({ax[COORD_WIDTH-1], ax}));

      if (area < 0) begin
        logic signed [COORD_WIDTH-1:0] tx;
        logic signed [COORD_WIDTH-1:0] ty;
        tx = bx;
        ty = by;
        bx = cx;
        by = cy;
        cx = tx;
        cy = ty;
      end

      if (actual.ax !== ax || actual.ay !== ay ||
          actual.bx !== bx || actual.by !== by ||
          actual.cx !== cx || actual.cy !== cy) begin
        $error("triangle2d[%0d] coordinate mismatch: got A(%0d,%0d) B(%0d,%0d) C(%0d,%0d), expected A(%0d,%0d) B(%0d,%0d) C(%0d,%0d)",
               index,
               actual.ax, actual.ay, actual.bx, actual.by, actual.cx, actual.cy,
               ax, ay, bx, by, cx, cy);
        errcnt++;
      end

      if (actual.fbid_color !== 2'd0 || actual.fbid_depth !== 2'd0) begin
        $error("triangle2d[%0d] framebuffer ID mismatch", index);
        errcnt++;
      end

      if (actual.az !== 16'h8000 || actual.bz !== 16'h8000 || actual.cz !== 16'h8000) begin
        $error("triangle2d[%0d] depth mismatch: got %h %h %h", index,
               actual.az, actual.bz, actual.cz);
        errcnt++;
      end
    end
  endtask

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      triangle2d_count <= 0;
      raster_param_count <= 0;
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;

      if (triangle2d_valid && triangle2d_ready) begin
        if (triangle2d_count >= NUM_TRIS) begin
          $error("unexpected extra triangle2d output");
          errcnt++;
        end else begin
          check_triangle2d(triangle2d, triangle2d_count);
        end
        triangle2d_count <= triangle2d_count + 1;
      end

      if (raster_param_valid && raster_param_ready) begin
        if (raster_param.fbid_color !== 2'd0 || raster_param.fbid_depth !== 2'd0) begin
          $error("raster_param[%0d] framebuffer ID mismatch", raster_param_count);
          errcnt++;
        end
        raster_param_count <= raster_param_count + 1;
      end
    end
  end

  initial begin
    errcnt = 0;
    clear_inputs();

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);

    write_identity_matrix();
    write_test_scene();

    // Hold the rasterizer-param output for long enough to exercise adapter
    // FIFO backpressure, then let the pipeline drain.
    raster_param_ready = 1'b0;
    start_render();
    repeat (300) @(posedge clk);
    raster_param_ready = 1'b1;

    while (raster_param_count < NUM_TRIS && cycle_count < 5000) begin
      @(posedge clk);
    end

    repeat (20) @(posedge clk);

    if (triangle2d_count !== NUM_TRIS) begin
      $error("triangle2d output count mismatch: expected %0d got %0d",
             NUM_TRIS, triangle2d_count);
      errcnt++;
    end

    if (raster_param_count !== NUM_TRIS) begin
      $error("raster_param output count mismatch: expected %0d got %0d",
             NUM_TRIS, raster_param_count);
      errcnt++;
    end

    if (errcnt == 0) begin
      $display("### TESTS PASSED ###");
    end else begin
      $display("### TESTS FAILED: %0d errors ###", errcnt);
      $fatal(1);
    end
    $finish;
  end

endmodule
