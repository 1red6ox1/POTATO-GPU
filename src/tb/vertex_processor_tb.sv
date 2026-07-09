// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2026 RVLab Contributors

module vertex_processor_tb;
  localparam int DATA_WIDTH = 32;
  localparam int OUT_WIDTH = DATA_WIDTH;
  localparam int TRI_ID_WIDTH = 10;
  localparam int VTX_ID_WIDTH = 2;

  typedef logic signed [DATA_WIDTH-1:0] data_t;
  typedef logic signed [OUT_WIDTH-1:0] out_t;
  localparam int MAT_DIM = 4;
  localparam int NUM_CAMERAS = 5;
  localparam int NUM_TRIS = 2;
  localparam int NUM_VERTS = 3;

  typedef data_t matrix_t[MAT_DIM][MAT_DIM];
  typedef data_t vector_t[MAT_DIM];
  typedef vector_t triangle_vectors_t[NUM_TRIS][NUM_VERTS];
  typedef out_t out_vector_t[MAT_DIM];
  typedef out_vector_t expected_vectors_t[NUM_TRIS][NUM_VERTS];

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  tlul_pkg::tl_h2d_t tl_cfg_h2d;
  tlul_pkg::tl_d2h_t tl_cfg_d2h;
  tlul_pkg::tl_h2d_t tl_vec_h2d;
  tlul_pkg::tl_d2h_t tl_vec_d2h;

  logic out_valid;
  logic out_ready;
  logic [TRI_ID_WIDTH-1:0] out_id;
  out_t out_vec[3:0];

  int unsigned errcnt;

  localparam tlul_pkg::tl_h2d_t TlIdle = '{a_opcode: tlul_pkg::PutFullData, default: '0};

  // 50 MHz
  always #10000 clk = ~clk;

  vertex_processor #(
      .DATA_WIDTH(DATA_WIDTH),
      .OUT_WIDTH (OUT_WIDTH)
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
    @(negedge clk);
    tl_cfg_h2d.a_address = addr;
    tl_cfg_h2d.a_opcode  = tlul_pkg::PutFullData;
    tl_cfg_h2d.a_size    = 2'h2;
    tl_cfg_h2d.a_data    = wdata;
    tl_cfg_h2d.a_mask    = 4'hF;
    tl_cfg_h2d.a_valid   = 1'b1;

    timeout = 0;
    while (!tl_cfg_d2h.a_ready && timeout < 20) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    if (!tl_cfg_d2h.a_ready) begin
      $error("cfg_tl_put: timeout waiting for a_ready at 0x%08x", addr);
      errcnt = errcnt + 1;
    end
    @(posedge clk);

    @(negedge clk);
    tl_cfg_h2d.a_valid = 1'b0;
    tl_cfg_h2d.d_ready = 1'b1;
    timeout = 0;
    while (!tl_cfg_d2h.d_valid && timeout < 20) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    if (!tl_cfg_d2h.d_valid) begin
      $error("cfg_tl_put: timeout waiting for d_valid at 0x%08x", addr);
      errcnt = errcnt + 1;
    end
    @(posedge clk);
    @(negedge clk);
    tl_cfg_h2d.d_ready = 1'b0;
  endtask

  task automatic cfg_tl_get(
      input logic [31:0] addr,
      output logic [31:0] rdata
  );
    int unsigned timeout;
    @(negedge clk);
    tl_cfg_h2d.a_address = addr;
    tl_cfg_h2d.a_opcode  = tlul_pkg::Get;
    tl_cfg_h2d.a_size    = 2'h2;
    tl_cfg_h2d.a_mask    = 4'hF;
    tl_cfg_h2d.a_valid   = 1'b1;

    timeout = 0;
    while (!tl_cfg_d2h.a_ready && timeout < 20) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    if (!tl_cfg_d2h.a_ready) begin
      $error("cfg_tl_get: timeout waiting for a_ready at 0x%08x", addr);
      errcnt = errcnt + 1;
    end
    @(posedge clk);

    @(negedge clk);
    tl_cfg_h2d.a_valid = 1'b0;
    tl_cfg_h2d.d_ready = 1'b1;
    timeout = 0;
    while (!tl_cfg_d2h.d_valid && timeout < 20) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    if (!tl_cfg_d2h.d_valid) begin
      $error("cfg_tl_get: timeout waiting for d_valid at 0x%08x", addr);
      errcnt = errcnt + 1;
    end
    rdata = tl_cfg_d2h.d_data;
    @(posedge clk);
    @(negedge clk);
    tl_cfg_h2d.d_ready = 1'b0;
  endtask

  task automatic vec_tl_put(
      input logic [31:0] addr,
      input logic [31:0] wdata
  );
    int unsigned timeout;
    @(negedge clk);
    tl_vec_h2d.a_address = addr;
    tl_vec_h2d.a_opcode  = tlul_pkg::PutFullData;
    tl_vec_h2d.a_size    = 2'h2;
    tl_vec_h2d.a_data    = wdata;
    tl_vec_h2d.a_mask    = 4'hF;
    tl_vec_h2d.a_valid   = 1'b1;

    timeout = 0;
    while (!tl_vec_d2h.a_ready && timeout < 20) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    if (!tl_vec_d2h.a_ready) begin
      $error("vec_tl_put: timeout waiting for a_ready at 0x%08x", addr);
      errcnt = errcnt + 1;
    end
    @(posedge clk);

    @(negedge clk);
    tl_vec_h2d.a_valid = 1'b0;
    tl_vec_h2d.d_ready = 1'b1;
    timeout = 0;
    while (!tl_vec_d2h.d_valid && timeout < 20) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    if (!tl_vec_d2h.d_valid) begin
      $error("vec_tl_put: timeout waiting for d_valid at 0x%08x", addr);
      errcnt = errcnt + 1;
    end
    @(posedge clk);
    @(negedge clk);
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
      input vector_t vec
  );
    vec_write_lane(triangle_id, endpoint, 2'd0, vec[0]);
    vec_write_lane(triangle_id, endpoint, 2'd1, vec[1]);
    vec_write_lane(triangle_id, endpoint, 2'd2, vec[2]);
    // Lane 3 write enqueues this address in the DUT.
    vec_write_lane(triangle_id, endpoint, 2'd3, vec[3]);
  endtask

  task automatic reset_dut();
    rst_n = 1'b0;
    clear_inputs();
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);
  endtask

  task automatic wait_and_check_output(
      input logic [TRI_ID_WIDTH-1:0] expected_id,
      input out_vector_t expected_vec,
      input string name,
      input logic expected_valid
  );
    int unsigned timeout;
    out_ready = 1'b1;
    #1;
    if (expected_valid) begin
      timeout = 0;
      while (!out_valid && timeout < 200) begin
        @(posedge clk);
        #1;
        timeout = timeout + 1;
      end

      if (!out_valid) begin
        $error("%s: timeout waiting for out_valid", name);
        errcnt = errcnt + 1;
        return;
      end
    end

    if (out_valid !== expected_valid) begin
      $error("%s: out_valid mismatch, expected %0b got %0b", name, expected_valid, out_valid);
      errcnt = errcnt + 1;
    end

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

  task automatic clear_cfg_matrix();
    for (int r = 0; r < MAT_DIM; r = r + 1) begin
      for (int c = 0; c < MAT_DIM; c = c + 1) begin
        cfg_write_word(r[1:0], c[1:0], 32'sh0000_0000);
      end
    end
  endtask

  task automatic write_cfg_matrix(input matrix_t matrix);
    for (int r = 0; r < MAT_DIM; r = r + 1) begin
      for (int c = 0; c < MAT_DIM; c = c + 1) begin
        cfg_write_word(r[1:0], c[1:0], matrix[r][c]);
      end
    end
  endtask

  task automatic check_cfg_matrix(input matrix_t matrix, input string name);
    for (int r = 0; r < MAT_DIM; r = r + 1) begin
      for (int c = 0; c < MAT_DIM; c = c + 1) begin
        check_cfg_word(r[1:0], c[1:0], matrix[r][c]);
      end
    end
    $display("%s: matrix configured", name);
  endtask

  task automatic set_world_vectors(output triangle_vectors_t world);
    world = '{
        '{
            '{32'sh00000000, 32'sh00000000, 32'sh00000000, 32'sh00010000},
            '{32'sh00010000, 32'sh00000000, 32'sh00000000, 32'sh00010000},
            '{32'sh00010000, 32'sh00010000, 32'sh00000000, 32'sh00010000}
        },
        '{
            '{32'shfffe0000, 32'shffff0000, 32'sh00010000, 32'sh00010000},
            '{32'sh00010000, 32'sh00020000, 32'sh00000000, 32'sh00010000},
            '{32'shffff0000, 32'sh00000000, 32'sh00000000, 32'sh00010000}
        }
    };
  endtask

  task automatic set_camera_case(
      input int unsigned camera_id,
      output matrix_t matrix,
      output expected_vectors_t expected
  );
    for (int r = 0; r < MAT_DIM; r = r + 1) begin
      for (int c = 0; c < MAT_DIM; c = c + 1) begin
        matrix[r][c] = '0;
      end
    end
    for (int triangle_idx = 0; triangle_idx < NUM_TRIS; triangle_idx = triangle_idx + 1) begin
      for (int vtx = 0; vtx < NUM_VERTS; vtx = vtx + 1) begin
        for (int lane = 0; lane < MAT_DIM; lane = lane + 1) begin
          expected[triangle_idx][vtx][lane] = '0;
        end
      end
    end

    case (camera_id)
      0: begin
        matrix = '{
            '{32'sh00000000, 32'sh00000000, 32'shffff0697, 32'sh00000000},
            '{32'sh00000000, 32'sh0001bb67, 32'sh00000000, 32'sh00000000},
            '{32'shfffefeb8, 32'sh00000000, 32'sh00000000, 32'sh00048616},
            '{32'shffff0000, 32'sh00000000, 32'sh00000000, 32'sh00050000}
        };
        expected = '{
            '{
                '{32'sh00000000, 32'sh00000000, 32'sh00048616, 32'sh00050000},
                '{32'sh00000000, 32'sh00000000, 32'sh000384ce, 32'sh00040000},
                '{32'sh00000000, 32'sh0001bb67, 32'sh000384ce, 32'sh00040000}
            },
            '{
                '{32'shffff0697, 32'shfffe4499, 32'sh000688a6, 32'sh00070000},
                '{32'sh00000000, 32'sh000376ce, 32'sh000384ce, 32'sh00040000},
                '{32'sh00000000, 32'sh00000000, 32'sh0005875e, 32'sh00060000}
            }
        };
      end
      1: begin
        matrix = '{
            '{32'sh00006f8a, 32'sh00000000, 32'sh0000df15, 32'sh00000000},
            '{32'sh00013dfc, 32'sh000108fd, 32'shffff6101, 32'sh00000000},
            '{32'sh00008985, 32'shffff31b8, 32'shffffbb3d, 32'sh00034253},
            '{32'sh000088d6, 32'shffff32bf, 32'shffffbb95, 32'sh0003bdda}
        };
        expected = '{
            '{
                '{32'sh00000000, 32'sh00000000, 32'sh00034253, 32'sh0003bdda},
                '{32'sh00006f8a, 32'sh00013dfc, 32'sh0003cbd8, 32'sh000446b0},
                '{32'sh00006f8a, 32'sh000246f9, 32'sh0002fd90, 32'sh0003796f}
            },
            '{
                '{32'sh00000001, 32'shfffbdc0c, 32'sh0002b8ce, 32'sh00033504},
                '{32'sh00006f8a, 32'sh00034ff6, 32'sh00022f48, 32'sh0002ac2e},
                '{32'shffff9076, 32'shfffec204, 32'sh0002b8ce, 32'sh00033504}
            }
        };
      end
      2: begin
        matrix = '{
            '{32'sh00000000, 32'sh00000000, 32'shffff0691, 32'sh00000000},
            '{32'shfffe4a99, 32'sh000048e5, 32'sh00000000, 32'sh00000008},
            '{32'shffffd5b4, 32'shffff0238, 32'sh00000000, 32'sh00059ca7},
            '{32'shffffd5ea, 32'shffff037c, 32'sh00000000, 32'sh0006152e}
        };
        expected = '{
            '{
                '{32'sh00000000, 32'sh00000008, 32'sh00059ca7, 32'sh0006152e},
                '{32'sh00000000, 32'shfffe4aa1, 32'sh0005725b, 32'sh0005eb18},
                '{32'sh00000000, 32'shfffe9386, 32'sh00047493, 32'sh0004ee94}
            },
            '{
                '{32'shffff0691, 32'sh000321f1, 32'sh0006ef07, 32'sh000765de},
                '{32'sh00000000, 32'shfffedc6b, 32'sh000376cb, 32'sh0003f210},
                '{32'sh00000000, 32'sh0001b56f, 32'sh0005c6f3, 32'sh00063f44}
            }
        };
      end
      3: begin
        matrix = '{
            '{32'sh0000b05c, 32'sh00000000, 32'shffff4fa3, 32'sh00000000},
            '{32'shffff4afc, 32'sh00016a07, 32'shffff4afb, 32'sh00000000},
            '{32'shffff6b75, 32'shffff6b75, 32'shffff6b75, 32'sh0004b88b},
            '{32'shffff6c33, 32'shffff6c33, 32'shffff6c33, 32'sh00053235}
        };
        expected = '{
            '{
                '{32'sh00000000, 32'sh00000000, 32'sh0004b88b, 32'sh00053235},
                '{32'sh0000b05c, 32'shffff4afc, 32'sh00042400, 32'sh00049e68},
                '{32'sh0000b05c, 32'sh0000b503, 32'sh00038f75, 32'sh00040a9b}
            },
            '{
                '{32'shfffdeeeb, 32'shffff4afc, 32'sh0005e1a1, 32'sh000659cf},
                '{32'sh0000b05c, 32'sh00021f0a, 32'sh0002faea, 32'sh000376ce},
                '{32'shffff4fa4, 32'sh0000b504, 32'sh00054d16, 32'sh0005c602}
            }
        };
      end
      4: begin
        matrix = '{
            '{32'sh0000f969, 32'sh00000000, 32'sh00000000, 32'sh00000000},
            '{32'sh00000000, 32'sh0001bb67, 32'sh00000000, 32'sh00000000},
            '{32'sh00000000, 32'sh00000000, 32'shfffefeb8, 32'sh000080f6},
            '{32'sh00000000, 32'sh00000000, 32'shffff0000, 32'sh00010000}
        };
        expected = '{
            '{
                '{32'sh00000000, 32'sh00000000, 32'sh000080f6, 32'sh00010000},
                '{32'sh0000f969, 32'sh00000000, 32'sh000080f6, 32'sh00010000},
                '{32'sh0000f969, 32'sh0001bb67, 32'sh000080f6, 32'sh00010000}
            },
            '{
                '{32'shfffe0d2e, 32'shfffe4499, 32'shffff7fae, 32'sh00000000},
                '{32'sh0000f969, 32'sh000376ce, 32'sh000080f6, 32'sh00010000},
                '{32'shffff0697, 32'sh00000000, 32'sh000080f6, 32'sh00010000}
            }
        };
      end
      default: begin
        $fatal(1, "Unknown camera_id %0d", camera_id);
      end
    endcase
  endtask

  task automatic run_camera_case(input int unsigned camera_id);
    matrix_t matrix;
    triangle_vectors_t world;
    expected_vectors_t expected;
    string name;

    set_world_vectors(world);
    set_camera_case(camera_id, matrix, expected);

    out_ready = 1'b1;
    clear_cfg_matrix();
    write_cfg_matrix(matrix);
    check_cfg_matrix(matrix, $sformatf("camera%0d", camera_id));

    out_ready = 1'b0;
    for (int triangle_idx = 0; triangle_idx < NUM_TRIS; triangle_idx = triangle_idx + 1) begin
      for (int vtx = 0; vtx < NUM_VERTS; vtx = vtx + 1) begin
        write_vector(TRI_ID_WIDTH'(triangle_idx), VTX_ID_WIDTH'(vtx),
            world[triangle_idx][vtx]);
      end
    end

    for (int triangle_idx = 0; triangle_idx < NUM_TRIS; triangle_idx = triangle_idx + 1) begin
      for (int vtx = 0; vtx < NUM_VERTS; vtx = vtx + 1) begin
        name = $sformatf("camera%0d_tri%0d_p%0d", camera_id, triangle_idx, vtx);
        wait_and_check_output(
            TRI_ID_WIDTH'(triangle_idx), expected[triangle_idx][vtx], name, vtx == 0);
      end
    end
  endtask

  initial begin

    errcnt = 0;
    clear_inputs();

    reset_dut();

    for (int camera_id = 0; camera_id < NUM_CAMERAS; camera_id = camera_id + 1) begin
      run_camera_case(camera_id);
    end

    if (errcnt > 0) begin
      $display("### TESTS FAILED WITH %0d ERRORS ###", errcnt);
    end else begin
      $display("### TESTS PASSED ###");
    end

    $finish;
  end

endmodule
