// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2024 RVLab Contributors

module matmul_tb;
  localparam int DATA_WIDTH = 32;
  localparam int OUT_WIDTH = DATA_WIDTH;
  localparam int MAT_DIM = 4;

  typedef logic signed [DATA_WIDTH-1:0] data_t;
  typedef logic signed [OUT_WIDTH-1:0] out_t;
  typedef data_t matrix_t[MAT_DIM][MAT_DIM];
  typedef data_t vector_t[MAT_DIM];
  typedef out_t out_vector_t[MAT_DIM];

  logic clk;
  logic rst_n;
  logic in_valid;
  logic out_valid;
  logic [31:0] in_id;
  logic [31:0] out_id;
  matrix_t mat_A;
  vector_t vec_B;
  out_vector_t mat_C;

  int unsigned errcnt;

  // 50 MHz
  always begin
    clk = '1;
    #10000;
    clk = '0;
    #10000;
  end

  matmul #(
      .DATA_WIDTH(DATA_WIDTH),
      .FRAC_WIDTH(16),
      .OUT_WIDTH (OUT_WIDTH)
  ) DUT (
      .clk      (clk),
      .rst_n    (rst_n),
      .in_valid (in_valid),
      .in_id    (in_id),
      .mat_A    (mat_A),
      .vec_B    (vec_B),
      .out_valid(out_valid),
      .out_id   (out_id),
      .mat_C    (mat_C)
  );

  task automatic clear_inputs();
    in_valid = 1'b0;
    in_id = '0;
    for (int i = 0; i < MAT_DIM; i = i + 1) begin
      vec_B[i] = '0;
      for (int j = 0; j < MAT_DIM; j = j + 1) begin
        mat_A[i][j] = '0;
      end
    end
  endtask

  task automatic reset_dut();
    rst_n = 1'b0;
    clear_inputs();
    repeat (4) @(posedge clk);
    #1;

    if (out_valid !== 1'b0) begin
      $error("out_valid is not low during reset");
      errcnt = errcnt + 1;
    end

    if (out_id !== '0) begin
      $error("out_id is not zero during reset: got 0x%08x", out_id);
      errcnt = errcnt + 1;
    end

    for (int i = 0; i < MAT_DIM; i = i + 1) begin
      if (mat_C[i] !== '0) begin
        $error("mat_C[%0d] is not zero during reset: got %0d", i, mat_C[i]);
        errcnt = errcnt + 1;
      end
    end

    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);
  endtask

  task automatic drive_input(input matrix_t a, input vector_t b, input logic [31:0] id);
    @(negedge clk);
    mat_A = a;
    vec_B = b;
    in_id = id;
    in_valid = 1'b1;
    @(negedge clk);
    in_valid = 1'b0;
  endtask

  task automatic drive_input_hold(input matrix_t a, input vector_t b, input logic [31:0] id);
    mat_A = a;
    vec_B = b;
    in_id = id;
    in_valid = 1'b1;
  endtask

  task automatic check_output(
      input out_vector_t expected,
      input logic [31:0] expected_id,
      input string test_name
  );
    if (out_valid !== 1'b1) begin
      $error("%s: out_valid is not asserted", test_name);
      errcnt = errcnt + 1;
    end

    if (out_id !== expected_id) begin
      $error("%s: out_id mismatch: expected 0x%08x, got 0x%08x",
          test_name, expected_id, out_id);
      errcnt = errcnt + 1;
    end

    for (int i = 0; i < MAT_DIM; i = i + 1) begin
      if (mat_C[i] !== expected[i]) begin
        $error("%s: mat_C[%0d] mismatch: expected 0x%08x, got 0x%08x",
            test_name, i, expected[i], mat_C[i]);
        errcnt = errcnt + 1;
      end
    end
  endtask

  task automatic wait_and_check(
      input out_vector_t expected,
      input logic [31:0] expected_id,
      input string test_name
  );
    repeat (3) begin
      @(posedge clk);
      #1;
      if (out_valid !== 1'b0) begin
        $error("%s: out_valid asserted too early", test_name);
        errcnt = errcnt + 1;
      end
    end

    @(posedge clk);
    #1;
    check_output(expected, expected_id, test_name);

    @(posedge clk);
    #1;
    if (out_valid !== 1'b0) begin
      $error("%s: out_valid stayed high after one cycle", test_name);
      errcnt = errcnt + 1;
    end
  endtask

  task automatic set_identity_case(
      output matrix_t a,
      output vector_t b,
      output out_vector_t expected
  );
    a = '{
        '{32'sh0001_0000, 32'sh0000_0000, 32'sh0000_0000, 32'sh0000_0000},
        '{32'sh0000_0000, 32'sh0001_0000, 32'sh0000_0000, 32'sh0000_0000},
        '{32'sh0000_0000, 32'sh0000_0000, 32'sh0001_0000, 32'sh0000_0000},
        '{32'sh0000_0000, 32'sh0000_0000, 32'sh0000_0000, 32'sh0001_0000}
    };
    b = '{
        32'sh0001_0000,
        32'sh0002_0000,
        32'sh0003_0000,
        32'sh0004_0000
    };
    expected = '{
        32'sh0001_0000,
        32'sh0002_0000,
        32'sh0003_0000,
        32'sh0004_0000
    };
  endtask

  task automatic set_signed_case(
      output matrix_t a,
      output vector_t b,
      output out_vector_t expected
  );
    a = '{
        '{32'sh0000_0000, 32'shffff_0000, 32'shfffe_0000, 32'shfffd_0000},
        '{32'sh0002_0000, 32'sh0001_0000, 32'sh0000_0000, 32'shffff_0000},
        '{32'sh0004_0000, 32'sh0003_0000, 32'sh0002_0000, 32'sh0001_0000},
        '{32'sh0006_0000, 32'sh0005_0000, 32'sh0004_0000, 32'sh0003_0000}
    };
    b = '{
        32'shfffe_0000,
        32'shffff_0000,
        32'sh0000_0000,
        32'sh0001_0000
    };
    expected = '{
        32'shfffe_0000,
        32'shfffa_0000,
        32'shfff6_0000,
        32'shfff2_0000
    };
  endtask

  task automatic set_saturation_case(
      output matrix_t a,
      output vector_t b,
      output out_vector_t expected
  );
    a = '{
        '{32'sh2000_0000, 32'sh2000_0000, 32'sh2000_0000, 32'sh2000_0000},
        '{32'sh2000_0000, 32'sh2000_0000, 32'sh2000_0000, 32'sh2000_0000},
        '{32'sh2000_0000, 32'sh2000_0000, 32'sh2000_0000, 32'sh2000_0000},
        '{32'sh2000_0000, 32'sh2000_0000, 32'sh2000_0000, 32'sh2000_0000}
    };
    b = '{
        32'sh0004_0000,
        32'sh0004_0000,
        32'sh0004_0000,
        32'sh0004_0000
    };
    expected = '{
        32'sh7fff_ffff,
        32'sh7fff_ffff,
        32'sh7fff_ffff,
        32'sh7fff_ffff
    };
  endtask

  initial begin
    matrix_t a0;
    vector_t b0;
    matrix_t a1;
    vector_t b1;
    out_vector_t exp0;
    out_vector_t exp1;
    logic [31:0] id0;
    logic [31:0] id1;

    errcnt = '0;
    reset_dut();

    set_identity_case(a0, b0, exp0);
    id0 = 32'h1234_0001;
    drive_input(a0, b0, id0);
    wait_and_check(exp0, id0, "identity_times_vector");

    set_signed_case(a0, b0, exp0);
    id0 = 32'h1234_0002;
    drive_input(a0, b0, id0);
    wait_and_check(exp0, id0, "signed_pattern");

    set_saturation_case(a0, b0, exp0);
    id0 = 32'h1234_0003;
    drive_input(a0, b0, id0);
    wait_and_check(exp0, id0, "saturation_case");

    set_identity_case(a0, b0, exp0);
    set_signed_case(a1, b1, exp1);
    id0 = 32'hcafe_0001;
    id1 = 32'hcafe_0002;

    @(negedge clk);
    drive_input_hold(a0, b0, id0);
    @(negedge clk);
    drive_input_hold(a1, b1, id1);
    @(negedge clk);
    in_valid = 1'b0;

    repeat (2) begin
      @(posedge clk);
      #1;
      if (out_valid !== 1'b0) begin
        $error("back_to_back: out_valid asserted too early");
        errcnt = errcnt + 1;
      end
    end

    @(posedge clk);
    #1;
    check_output(exp0, id0, "back_to_back_first");

    @(posedge clk);
    #1;
    check_output(exp1, id1, "back_to_back_second");

    @(posedge clk);
    #1;
    if (out_valid !== 1'b0) begin
      $error("back_to_back: out_valid stayed high after expected outputs");
      errcnt = errcnt + 1;
    end

    if (errcnt > 0) begin
      $display("### TESTS FAILED WITH %0d ERRORS ###", errcnt);
    end else begin
      $display("### TESTS PASSED ###");
    end

    $finish;
  end

endmodule
