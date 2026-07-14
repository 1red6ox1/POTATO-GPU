// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2026 RVLab Contributors

module vertex_triangle_collector #(
  parameter int DATA_WIDTH = 32,
  parameter int TRI_ID_WIDTH = 10
) (
  input  logic                           clk_i,
  input  logic                           rst_ni,
   
  input  logic                           in_valid_i,
  output logic                           in_ready_o,
  input  logic        [TRI_ID_WIDTH-1:0] in_id_i,
  input  logic signed [DATA_WIDTH-1:0]   in_vec_i [3:0],

  output logic                           out_valid_o,
  input  logic                           out_ready_i,
  output logic        [TRI_ID_WIDTH-1:0] out_id_o,
  output logic signed [DATA_WIDTH-1:0]   out_x_o [2:0],
  output logic signed [DATA_WIDTH-1:0]   out_y_o [2:0],
  output logic signed [DATA_WIDTH-1:0]   out_z_o [2:0],
  output logic signed [DATA_WIDTH-1:0]   out_w_o [2:0]
);

  logic [1:0] vertex_idx_q;
  logic       collecting_q;
  logic       full_q;

  assign out_valid_o = full_q;
  assign in_ready_o = !full_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vertex_idx_q <= '0;
      collecting_q <= 1'b0;
      full_q <= 1'b0;
      out_id_o <= '0;
      for (int i = 0; i < 3; i++) begin
        out_x_o[i] <= '0;
        out_y_o[i] <= '0;
        out_z_o[i] <= '0;
        out_w_o[i] <= '0;
      end
    end else begin
      if (full_q && out_ready_i) begin
        full_q <= 1'b0;
      end

      if (in_ready_o && (in_valid_i || collecting_q)) begin
        out_x_o[vertex_idx_q] <= in_vec_i[0];
        out_y_o[vertex_idx_q] <= in_vec_i[1];
        out_z_o[vertex_idx_q] <= in_vec_i[2];
        out_w_o[vertex_idx_q] <= in_vec_i[3];

        if (!collecting_q) begin
          out_id_o <= in_id_i;
        end

        if (vertex_idx_q == 2'd2) begin
          vertex_idx_q <= '0;
          collecting_q <= 1'b0;
          full_q <= 1'b1;
        end else begin
          vertex_idx_q <= vertex_idx_q + 1'b1;
          collecting_q <= 1'b1;
        end
      end
    end
  end

endmodule
