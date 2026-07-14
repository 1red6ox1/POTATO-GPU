// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2026 RVLab Contributors

module vertex_triangle_collector_tb;
  localparam int DATA_WIDTH = 32;
  localparam int TRI_ID_WIDTH = 10;

  typedef logic signed [DATA_WIDTH-1:0] data_t;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic in_valid;
  logic in_ready;
  logic [TRI_ID_WIDTH-1:0] in_id;
  data_t in_vec [3:0];
  logic out_valid;
  logic out_ready;
  logic [TRI_ID_WIDTH-1:0] out_id;
  data_t out_x [2:0];
  data_t out_y [2:0];
  data_t out_z [2:0];
  data_t out_w [2:0];

  int unsigned errcnt;

  always #10000 clk = ~clk;

  vertex_triangle_collector #(
    .DATA_WIDTH  (DATA_WIDTH),
    .TRI_ID_WIDTH(TRI_ID_WIDTH)
  ) DUT (
    .clk_i      (clk),
    .rst_ni     (rst_n),
    .in_valid_i (in_valid),
    .in_ready_o (in_ready),
    .in_id_i    (in_id),
    .in_vec_i   (in_vec),
    .out_valid_o(out_valid),
    .out_ready_i(out_ready),
    .out_id_o   (out_id),
    .out_x_o    (out_x),
    .out_y_o    (out_y),
    .out_z_o    (out_z),
    .out_w_o    (out_w)
  );

  task automatic set_input(
      input logic [TRI_ID_WIDTH-1:0] id,
      input int signed base,
      input int unsigned vertex_idx
  );
    in_id = id;
    for (int lane = 0; lane < 4; lane++) begin
      in_vec[lane] = data_t'(base + int'(10 * vertex_idx + lane));
    end
  endtask

  task automatic check_triangle(
      input string name,
      input logic [TRI_ID_WIDTH-1:0] expected_id,
      input int signed base
  );
    if (out_valid !== 1'b1) begin
      $error("%s: out_valid not high", name);
      errcnt++;
    end
    if (in_ready !== 1'b0) begin
      $error("%s: in_ready not low while triangle is pending", name);
      errcnt++;
    end
    if (out_id !== expected_id) begin
      $error("%s: out_id mismatch, expected %0d got %0d", name, expected_id, out_id);
      errcnt++;
    end
    for (int vertex = 0; vertex < 3; vertex++) begin
      if (out_x[vertex] !== data_t'(base + int'(10 * vertex + 0))) begin
        $error("%s: x[%0d] mismatch", name, vertex);
        errcnt++;
      end
      if (out_y[vertex] !== data_t'(base + int'(10 * vertex + 1))) begin
        $error("%s: y[%0d] mismatch", name, vertex);
        errcnt++;
      end
      if (out_z[vertex] !== data_t'(base + int'(10 * vertex + 2))) begin
        $error("%s: z[%0d] mismatch", name, vertex);
        errcnt++;
      end
      if (out_w[vertex] !== data_t'(base + int'(10 * vertex + 3))) begin
        $error("%s: w[%0d] mismatch", name, vertex);
        errcnt++;
      end
    end
  endtask

  task automatic drive_processor_burst(
      input logic [TRI_ID_WIDTH-1:0] id,
      input int signed base
  );
    @(negedge clk);
    set_input(id, base, 0);
    in_valid = 1'b1;
    @(posedge clk);
    #1;
    if (in_ready !== 1'b1) begin
      $error("drive: in_ready low at first vertex");
      errcnt++;
    end

    @(negedge clk);
    set_input(id, base, 1);
    in_valid = 1'b0;
    @(posedge clk);

    @(negedge clk);
    set_input(id, base, 2);
    @(posedge clk);
    #1;
  endtask

  initial begin
    in_valid = 1'b0;
    in_id = '0;
    in_vec = '{default: '0};
    out_ready = 1'b0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;

    if (out_valid !== 1'b0 || in_ready !== 1'b1) begin
      $error("reset release: bad idle state");
      errcnt++;
    end

    drive_processor_burst(10'd7, 100);
    check_triangle("held_triangle", 10'd7, 100);

    repeat (3) begin
      @(negedge clk);
      set_input(10'd3, 900, 0);
      @(posedge clk);
      #1;
      check_triangle("hold_stability", 10'd7, 100);
    end

    @(negedge clk);
    out_ready = 1'b1;
    @(posedge clk);
    #1;
    if (out_valid !== 1'b0 || in_ready !== 1'b1) begin
      $error("post accept: collector did not return idle");
      errcnt++;
    end
    out_ready = 1'b0;

    drive_processor_burst(10'd9, -200);
    check_triangle("second_triangle", 10'd9, -200);

    if (errcnt == 0) begin
      $display("### TESTS PASSED ###");
    end else begin
      $display("### TESTS FAILED: %0d errors ###", errcnt);
      $fatal(1);
    end
    $finish;
  end

endmodule
