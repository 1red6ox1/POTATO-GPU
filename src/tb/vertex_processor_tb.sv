// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2026 RVLab Contributors

module vertex_processor_tb;
  localparam int DATA_WIDTH = 32;
  localparam int OUT_WIDTH = DATA_WIDTH;
  localparam int TRI_ID_WIDTH = 10;
  localparam int VTX_ID_WIDTH = 2;

  typedef logic signed [DATA_WIDTH-1:0] data_t;
  typedef logic signed [OUT_WIDTH-1:0] out_t;

  logic clk;
  logic rst_n;

  tlul_pkg::tl_h2d_t tl_cfg_h2d;
  tlul_pkg::tl_d2h_t tl_cfg_d2h;
  tlul_pkg::tl_h2d_t tl_vec_h2d;
  tlul_pkg::tl_d2h_t tl_vec_d2h;

  logic out_valid;
  logic out_ready;
  logic [31:0] out_id;
  out_t out_vec[3:0];

  int unsigned errcnt;

  localparam tlul_pkg::tl_h2d_t TlIdle = '{a_opcode: tlul_pkg::PutFullData, default: '0};

  // 50 MHz
  always begin
    clk = 1'b1;
    #10000;
    clk = 1'b0;
    #10000;
  end

  vertex_processor #(
      .DATA_WIDTH(DATA_WIDTH),
      .FRAC_WIDTH(16),
      .OUT_WIDTH (OUT_WIDTH),
      .FIFO_DEPTH(16)
  ) DUT (
      .clk(clk),
      .rst_n(rst_n),
      .tl_cfg_i(tl_cfg_h2d),
      .tl_cfg_o(tl_cfg_d2h),
      .tl_vec_i(tl_vec_h2d),
      .tl_vec_o(tl_vec_d2h),
      .out_valid_o(out_valid),
      .out_ready_i(out_ready),
      .out_id_o(out_id),
      .out_vec_o(out_vec)
  );

  task automatic clear_inputs();
    out_ready = 1'b1;
    tl_cfg_h2d = TlIdle;
    tl_vec_h2d = TlIdle;
  endtask

  task automatic cfg_tl_put(
      input logic [31:0] addr,
      input logic [31:0] wdata
  );
    int unsigned timeout;
    @(posedge clk);
    tl_cfg_h2d.a_address = addr;
    tl_cfg_h2d.a_opcode  = tlul_pkg::PutFullData;
    tl_cfg_h2d.a_size    = 2'h2;
    tl_cfg_h2d.a_data    = wdata;
    tl_cfg_h2d.a_mask    = 4'hF;
    tl_cfg_h2d.a_valid   = 1'b1;

    timeout = 0;
    while (!tl_cfg_d2h.a_ready && timeout < 20) begin
      @(posedge clk);
      timeout = timeout + 1;
    end
    if (!tl_cfg_d2h.a_ready) begin
      $error("cfg_tl_put: timeout waiting for a_ready at 0x%08x", addr);
      errcnt = errcnt + 1;
    end
    @(posedge clk);

    tl_cfg_h2d.a_valid = 1'b0;
    tl_cfg_h2d.d_ready = 1'b1;
    timeout = 0;
    while (!tl_cfg_d2h.d_valid && timeout < 20) begin
      @(posedge clk);
      timeout = timeout + 1;
    end
    if (!tl_cfg_d2h.d_valid) begin
      $error("cfg_tl_put: timeout waiting for d_valid at 0x%08x", addr);
      errcnt = errcnt + 1;
    end
    @(posedge clk);
    tl_cfg_h2d.d_ready = 1'b0;
  endtask

  task automatic cfg_tl_get(
      input logic [31:0] addr,
      output logic [31:0] rdata
  );
    int unsigned timeout;
    @(posedge clk);
    tl_cfg_h2d.a_address = addr;
    tl_cfg_h2d.a_opcode  = tlul_pkg::Get;
    tl_cfg_h2d.a_size    = 2'h2;
    tl_cfg_h2d.a_mask    = 4'hF;
    tl_cfg_h2d.a_valid   = 1'b1;

    timeout = 0;
    while (!tl_cfg_d2h.a_ready && timeout < 20) begin
      @(posedge clk);
      timeout = timeout + 1;
    end
    if (!tl_cfg_d2h.a_ready) begin
      $error("cfg_tl_get: timeout waiting for a_ready at 0x%08x", addr);
      errcnt = errcnt + 1;
    end
    @(posedge clk);

    tl_cfg_h2d.a_valid = 1'b0;
    tl_cfg_h2d.d_ready = 1'b1;
    timeout = 0;
    while (!tl_cfg_d2h.d_valid && timeout < 20) begin
      @(posedge clk);
      timeout = timeout + 1;
    end
    if (!tl_cfg_d2h.d_valid) begin
      $error("cfg_tl_get: timeout waiting for d_valid at 0x%08x", addr);
      errcnt = errcnt + 1;
    end
    rdata = tl_cfg_d2h.d_data;
    @(posedge clk);
    tl_cfg_h2d.d_ready = 1'b0;
  endtask

  task automatic vec_tl_put(
      input logic [31:0] addr,
      input logic [31:0] wdata
  );
    int unsigned timeout;
    @(posedge clk);
    tl_vec_h2d.a_address = addr;
    tl_vec_h2d.a_opcode  = tlul_pkg::PutFullData;
    tl_vec_h2d.a_size    = 2'h2;
    tl_vec_h2d.a_data    = wdata;
    tl_vec_h2d.a_mask    = 4'hF;
    tl_vec_h2d.a_valid   = 1'b1;

    timeout = 0;
    while (!tl_vec_d2h.a_ready && timeout < 20) begin
      @(posedge clk);
      timeout = timeout + 1;
    end
    if (!tl_vec_d2h.a_ready) begin
      $error("vec_tl_put: timeout waiting for a_ready at 0x%08x", addr);
      errcnt = errcnt + 1;
    end
    @(posedge clk);

    tl_vec_h2d.a_valid = 1'b0;
    tl_vec_h2d.d_ready = 1'b1;
    timeout = 0;
    while (!tl_vec_d2h.d_valid && timeout < 20) begin
      @(posedge clk);
      timeout = timeout + 1;
    end
    if (!tl_vec_d2h.d_valid) begin
      $error("vec_tl_put: timeout waiting for d_valid at 0x%08x", addr);
      errcnt = errcnt + 1;
    end
    @(posedge clk);
    tl_vec_h2d.d_ready = 1'b0;
  endtask

  task automatic cfg_write_word(
      input logic [1:0] row,
      input logic [1:0] col,
      input data_t value
  );
    logic [31:0] addr;
    addr = {26'b0, row, col, 2'b00};
    cfg_tl_put(addr, value);
  endtask

  task automatic cfg_read_word(
      input logic [1:0] row,
      input logic [1:0] col,
      output logic [31:0] value
  );
    logic [31:0] addr;
    addr = {26'b0, row, col, 2'b00};
    cfg_tl_get(addr, value);
  endtask

  task automatic check_cfg_word(
      input logic [1:0] row,
      input logic [1:0] col,
      input logic [31:0] expected
  );
    logic [31:0] actual;
    cfg_read_word(row, col, actual);
    #1;
    if (actual !== expected) begin
      $error("cfg_matrix[%0d][%0d] mismatch, expected 0x%08x got 0x%08x",
          row, col, expected, actual);
      errcnt = errcnt + 1;
    end
  endtask

  task automatic vec_write_lane(
      input logic [TRI_ID_WIDTH-1:0] triangle_id,
      input logic [VTX_ID_WIDTH-1:0] endpoint,
      input logic [1:0] lane,
      input data_t value
  );
    logic [31:0] addr;
    addr = {16'b0, triangle_id, endpoint, lane, 2'b00};
    vec_tl_put(addr, value);
  endtask

  task automatic write_vector(
      input logic [TRI_ID_WIDTH-1:0] triangle_id,
      input logic [VTX_ID_WIDTH-1:0] endpoint,
      input data_t vec[3:0]
  );
    vec_write_lane(triangle_id, endpoint, 2'd0, vec[0]);
    vec_write_lane(triangle_id, endpoint, 2'd1, vec[1]);
    vec_write_lane(triangle_id, endpoint, 2'd2, vec[2]);
    // Lane 3 write enqueues this address in the DUT.
    vec_write_lane(triangle_id, endpoint, 2'd3, vec[3]);
  endtask

  task automatic reset_dut();
    rst_n = 1'b1;
    clear_inputs();
    @(negedge clk);
    rst_n = 1'b0;
    clear_inputs();
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);
  endtask

  task automatic configure_identity_matrix();
    for (int r = 0; r < 4; r = r + 1) begin
      for (int c = 0; c < 4; c = c + 1) begin
        if (r == c) begin
          cfg_write_word(r[1:0], c[1:0], 32'sh0001_0000);
        end else begin
          cfg_write_word(r[1:0], c[1:0], 32'sh0000_0000);
        end
      end
    end
  endtask

  task automatic wait_and_check_output(
      input logic [31:0] expected_id,
      input out_t expected_vec[3:0],
      input string name
  );
    int unsigned timeout;
    out_ready = 1'b1;
    timeout = 0;
    while (!out_valid && timeout < 200) begin
      @(posedge clk);
      timeout = timeout + 1;
    end

    if (!out_valid) begin
      $error("%s: timeout waiting for out_valid", name);
      errcnt = errcnt + 1;
      return;
    end

    #1;
    if (out_id !== expected_id) begin
      $error("%s: out_id mismatch, expected 0x%08x got 0x%08x", name, expected_id, out_id);
      errcnt = errcnt + 1;
    end

    for (int i = 0; i < 4; i = i + 1) begin
      if (out_vec[i] !== expected_vec[i]) begin
        $error("%s: out_vec[%0d] mismatch, expected 0x%08x got 0x%08x",
            name, i, expected_vec[i], out_vec[i]);
        errcnt = errcnt + 1;
      end
    end

    @(posedge clk);
  endtask

  initial begin
    data_t vin0[3:0];
    data_t vin1[3:0];
    data_t vin2[3:0];
    data_t vin3[3:0];
    out_t exp0[3:0];
    out_t exp1[3:0];
    out_t exp2[3:0];
    out_t exp3[3:0];

    errcnt = 0;
    clear_inputs();

    reset_dut();

    configure_identity_matrix();
    check_cfg_word(2'd0, 2'd0, 32'h0001_0000);
    check_cfg_word(2'd0, 2'd1, 32'h0000_0000);
    check_cfg_word(2'd1, 2'd1, 32'h0001_0000);
    check_cfg_word(2'd3, 2'd3, 32'h0001_0000);

    vin0 = '{32'sh0001_0000, 32'sh0002_0000, 32'sh0003_0000, 32'sh0001_0000};
    vin1 = '{32'sh0004_0000, 32'sh0005_0000, 32'sh0006_0000, 32'sh0001_0000};
    vin2 = '{32'shffff_0000, 32'sh0001_0000, 32'sh0000_8000, 32'sh0001_0000};
    vin3 = '{32'sh0007_0000, 32'sh0008_0000, 32'sh0009_0000, 32'sh0001_0000};

    exp0 = vin0;
    exp1 = vin1;
    exp2 = vin2;
    exp3 = vin3;

    out_ready = 1'b0;
    write_vector(TRI_ID_WIDTH'(0), VTX_ID_WIDTH'(0), vin0);
    write_vector(TRI_ID_WIDTH'(0), VTX_ID_WIDTH'(1), vin1);
    write_vector(TRI_ID_WIDTH'(0), VTX_ID_WIDTH'(2), vin2);
    write_vector(TRI_ID_WIDTH'(1), VTX_ID_WIDTH'(0), vin3);

    wait_and_check_output(32'h0000_0000, exp0, "vec0_triangle0");
    wait_and_check_output(32'h0000_0000, exp1, "vec1_triangle0");
    wait_and_check_output(32'h0000_0000, exp2, "vec2_triangle0");
    wait_and_check_output(32'h0000_0001, exp3, "vec3_triangle1");

    if (errcnt > 0) begin
      $display("### TESTS FAILED WITH %0d ERRORS ###", errcnt);
    end else begin
      $display("### TESTS PASSED ###");
    end

    $finish;
  end

endmodule
