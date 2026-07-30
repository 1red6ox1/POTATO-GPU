// SPDX-FileCopyrightText: 2026 RVLab Contributors
// SPDX-License-Identifier: SHL-2.1

module ddr_mux_tb;

  import tlul_pkg::*;
  import rvlab_ddr_pkg::*;

  localparam int N = 2;

  logic clk_i;
  logic rst_ni;

  ddr3_h2d_t host_i [N-1:0];
  ddr3_d2h_t host_o [N-1:0];

  ddr3_h2d_t dev_o;
  ddr3_d2h_t dev_i;


  rvlab_ddr_mux #(
      .N(N),
      .MAX_OUTSTANDING(4)
  ) dut (
      .clk_i,
      .rst_ni,
      .host_i,
      .host_o,
      .dev_o,
      .dev_i
  );


  initial clk_i = 0;
  always #5000 clk_i = ~clk_i;


  task reset();

    rst_ni = 0;

    foreach (host_i[i])
      host_i[i] = '0;

    dev_i = '0;

    repeat (3)
      @(posedge clk_i);

    rst_ni = 1;

    repeat (2)
      @(posedge clk_i);

  endtask


  initial begin

    reset();

    dev_i.a_ready = 1'b1;

    host_i[1].a_valid   = 1'b1;
    host_i[1].a_opcode  = Get;
    host_i[1].a_address = 24'h123456;
    host_i[1].a_anc     = 3'b101;

    //----------------------------------------------------------
    // Request handshake
    //----------------------------------------------------------

    @(posedge clk_i);

    if (!dev_o.a_valid)
      $fatal("Request did not reach device");

    if (dev_o.a_address != 24'h123456)
      $fatal("Address mismatch");

    if (dev_o.a_anc != 3'b101)
      $fatal("Ancillary mismatch");

    if (!host_o[1].a_ready)
      $fatal("Selected host was not ready");

    if (host_o[0].a_ready)
      $fatal("Unselected host was ready");


    // Transaction happened this cycle
    host_i[1].a_valid = 0;


    //----------------------------------------------------------
    // Response handshake
    //----------------------------------------------------------

    host_i[1].d_ready = 1'b1;

    dev_i.d_valid  = 1'b1;
    dev_i.d_opcode = AccessAckData;
    dev_i.d_data   = 256'hdead_beef;


    @(posedge clk_i);

    if (!host_o[1].d_valid)
      $fatal("Response not routed to requester");

    if (host_o[1].d_data != 256'hdead_beef)
      $fatal("Response data mismatch");

    if (host_o[1].d_anc != 3'b101)
      $fatal("Response ancillary mismatch");

    if (host_o[0].d_valid)
      $fatal("Response leaked to other host");


    dev_i.d_valid = 1'b0;


    //----------------------------------------------------------
    // Priority check
    //----------------------------------------------------------

    host_i[0].a_valid = 1'b1;
    host_i[1].a_valid = 1'b1;

    #1;

    if (!dev_o.a_valid)
      $fatal("No request selected");

    if (dev_o.a_anc != host_i[0].a_anc)
      $display("Priority appears OK (host0 selected)");

    if (!host_o[0].a_ready)
      $fatal("Host0 was not selected");

    if (host_o[1].a_ready)
      $fatal("Host1 incorrectly selected");


    $display("PASS");
    $finish;

  end

endmodule
