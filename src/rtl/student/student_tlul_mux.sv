// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2024 RVLab Contributors

module student_tlul_mux #(
    parameter int N = 2,
    parameter int PORT_SEL_LSB = 20
) (
    input logic clk_i,
    input logic rst_ni,

    output tlul_pkg::tl_d2h_t tl_host_o,
    input  tlul_pkg::tl_h2d_t tl_host_i,

    input  tlul_pkg::tl_d2h_t tl_device_i [N-1:0],
    output tlul_pkg::tl_h2d_t tl_device_o [N-1:0]
);

  logic [3:0] a_sel;
  logic       a_match;

  logic [3:0] d_sel;
  logic       d_match;

  assign a_sel   = tl_host_i.a_address[PORT_SEL_LSB +: 4];
  assign a_match = int'(a_sel) < N;

  always_comb begin
    d_sel   = '0;
    d_match = 1'b0;

    for (int i = 0; i < N; i++) begin
      if (tl_device_i[i].d_valid && !d_match) begin
        d_sel   = 4'(i);
        d_match = 1'b1;
      end
    end
  end

  always_comb begin
    tl_host_o = '{d_opcode: tlul_pkg::AccessAck, default: '0};

    for (int i = 0; i < N; i++) begin
      tl_device_o[i]         = tl_host_i;
      tl_device_o[i].a_valid = 1'b0;
      tl_device_o[i].d_ready = 1'b0;
    end

    if (a_match) begin
      tl_device_o[a_sel].a_valid = tl_host_i.a_valid;
      tl_host_o.a_ready          = tl_device_i[a_sel].a_ready;
    end

    if (d_match) begin
      tl_host_o                   = tl_device_i[d_sel];
      tl_device_o[d_sel].d_ready  = tl_host_i.d_ready;

      tl_host_o.a_ready = a_match ? tl_device_i[a_sel].a_ready : 1'b0;
    end
  end

endmodule
