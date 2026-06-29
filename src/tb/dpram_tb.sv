// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2024 RVLab Contributors

module dpram_tb;
  localparam int DATA_WIDTH = 32;
  localparam int DEPTH = 16;
  localparam int ADDR_WIDTH = $clog2(DEPTH);

  logic clk;
  logic [ADDR_WIDTH-1:0] rw_addr;
  logic rw_en;
  logic rw_we;
  logic signed [DATA_WIDTH-1:0] rw_data_in;
  logic signed [DATA_WIDTH-1:0] rw_data_out;

  logic [ADDR_WIDTH-1:0] r_addr;
  logic r_en;
  logic signed [DATA_WIDTH-1:0] r_data_out;

  int unsigned errcnt;

  always begin
    clk = 1'b1;
    #10000;
    clk = 1'b0;
    #10000;
  end

  dpram #(
      .DATA_WIDTH(DATA_WIDTH),
      .DEPTH(DEPTH),
      .ADDR_WIDTH(ADDR_WIDTH)
  ) DUT (
      .clk(clk),
      .rw_addr(rw_addr),
      .rw_en(rw_en),
      .rw_we(rw_we),
      .rw_data_in(rw_data_in),
      .rw_data_out(rw_data_out),
      .r_addr(r_addr),
      .r_en(r_en),
      .r_data_out(r_data_out)
  );

  task automatic clear_inputs();
    rw_addr = '0;
    rw_en = 1'b0;
    rw_we = 1'b0;
    rw_data_in = '0;
    r_addr = '0;
    r_en = 1'b0;
  endtask

  task automatic check_data(
      input logic signed [DATA_WIDTH-1:0] got,
      input logic signed [DATA_WIDTH-1:0] expected,
      input string name
  );
    if (got !== expected) begin
      $error("%s: expected 0x%08x, got 0x%08x", name, expected, got);
      errcnt = errcnt + 1;
    end
  endtask

  task automatic write_word(
      input logic [ADDR_WIDTH-1:0] addr,
      input logic signed [DATA_WIDTH-1:0] data
  );
    @(negedge clk);
    rw_addr = addr;
    rw_data_in = data;
    rw_en = 1'b1;
    rw_we = 1'b1;
    r_en = 1'b0;

    @(posedge clk);
    #1;
    check_data(rw_data_out, data, "rw port write-first output");

    @(negedge clk);
    clear_inputs();
  endtask

  task automatic read_rw_port(
      input logic [ADDR_WIDTH-1:0] addr,
      input logic signed [DATA_WIDTH-1:0] expected
  );
    @(negedge clk);
    rw_addr = addr;
    rw_en = 1'b1;
    rw_we = 1'b0;
    r_en = 1'b0;

    @(posedge clk);
    #1;
    check_data(rw_data_out, expected, "rw port read");

    @(negedge clk);
    clear_inputs();
  endtask

  task automatic read_r_port(
      input logic [ADDR_WIDTH-1:0] addr,
      input logic signed [DATA_WIDTH-1:0] expected
  );
    @(negedge clk);
    rw_en = 1'b0;
    r_addr = addr;
    r_en = 1'b1;

    @(posedge clk);
    #1;
    check_data(r_data_out, expected, "read-only port read");

    @(negedge clk);
    clear_inputs();
  endtask

  task automatic concurrent_different_addr();
    @(negedge clk);
    rw_addr = 4'd2;
    rw_data_in = 32'sh2222_0002;
    rw_en = 1'b1;
    rw_we = 1'b1;
    r_addr = 4'd1;
    r_en = 1'b1;

    @(posedge clk);
    #1;
    check_data(rw_data_out, 32'sh2222_0002, "concurrent write rw output");
    check_data(r_data_out, 32'sh1111_0001, "concurrent read different address");

    @(negedge clk);
    clear_inputs();
  endtask

  task automatic same_addr_conflict();
    @(negedge clk);
    rw_addr = 4'd3;
    rw_data_in = 32'sh3333_0003;
    rw_en = 1'b1;
    rw_we = 1'b1;
    r_addr = 4'd3;
    r_en = 1'b1;

    @(posedge clk);
    #1;
    check_data(rw_data_out, 32'sh3333_0003, "conflict rw write-first output");
    check_data(r_data_out, 32'sh3333_0003, "conflict read-only port forwarding");

    @(negedge clk);
    clear_inputs();
  endtask

  initial begin
    errcnt = '0;
    clear_inputs();

    repeat (2) @(posedge clk);

    write_word(4'd1, 32'sh1111_0001);
    read_rw_port(4'd1, 32'sh1111_0001);
    read_r_port(4'd1, 32'sh1111_0001);

    concurrent_different_addr();
    read_rw_port(4'd2, 32'sh2222_0002);

    write_word(4'd3, 32'sh3333_ffff);
    same_addr_conflict();
    read_r_port(4'd3, 32'sh3333_0003);

    if (errcnt > 0) begin
      $display("### TESTS FAILED WITH %0d ERRORS ###", errcnt);
    end else begin
      $display("### TESTS PASSED ###");
    end

    $finish;
  end

endmodule
