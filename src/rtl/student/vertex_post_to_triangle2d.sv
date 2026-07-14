// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2026 RVLab Contributors

module vertex_post_to_triangle2d
  import rasterizer_pkg::*;
#(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned FRAC_WIDTH = 16,
  parameter int unsigned FIFO_DEPTH = 4,
  parameter logic [1:0] FBID_COLOR = 2'd0,
  parameter logic [1:0] FBID_DEPTH = 2'd0
) (
  input  logic clk_i,
  input  logic rst_ni,

  output logic in_ready_o,
  input  logic in_valid_i,
  input  logic [10:0] sx_i [2:0],
  input  logic [10:0] sy_i [2:0],
  input  logic signed [DATA_WIDTH-1:0] z_i [2:0],
  input  logic signed [DATA_WIDTH-1:0] inv_w_i [2:0],

  output triangle2d_t triangle2d_o,
  output logic        out_valid_o,
  input  logic        out_ready_i
);

  localparam int unsigned DEPTH_W = $clog2(FIFO_DEPTH + 1);
  localparam logic signed [DATA_WIDTH-1:0] ONE_Q16 = DATA_WIDTH'(1 <<< FRAC_WIDTH);
  localparam logic signed [2*COORD_WIDTH+2:0] AREA_ZERO = '0;

  triangle2d_t fifo_q [FIFO_DEPTH-1:0];
  logic [$clog2(FIFO_DEPTH)-1:0] rptr_q;
  logic [$clog2(FIFO_DEPTH)-1:0] wptr_q;
  logic [DEPTH_W-1:0] depth_q;

  logic signed [COORD_WIDTH-1:0] x [2:0];
  logic signed [COORD_WIDTH-1:0] y [2:0];
  logic [DEPTH_WIDTH-1:0] z_depth [2:0];
  logic signed [UVQ_WIDTH-1:0] q [2:0];
  logic signed [COORD_WIDTH:0] dx10;
  logic signed [COORD_WIDTH:0] dy20;
  logic signed [COORD_WIDTH:0] dy10;
  logic signed [COORD_WIDTH:0] dx20;
  logic signed [2*COORD_WIDTH+2:0] area;
  triangle2d_t triangle_i;
  logic push;
  logic pop;
  logic drop_degenerate;

  assign triangle2d_o = fifo_q[rptr_q];
  assign out_valid_o = depth_q != '0;
  assign in_ready_o = depth_q < DEPTH_W'(FIFO_DEPTH);
  assign pop = out_valid_o && out_ready_i;
  assign drop_degenerate = in_valid_i && area == '0;
  assign push = in_valid_i && in_ready_o && !drop_degenerate;

  function automatic logic [DEPTH_WIDTH-1:0] q16_to_depth(
      input logic signed [DATA_WIDTH-1:0] value);
    begin
      if (value <= '0) begin
        q16_to_depth = '0;
      end else if (value >= ONE_Q16) begin
        q16_to_depth = '1;
      end else begin
        q16_to_depth = value[FRAC_WIDTH-1 -: DEPTH_WIDTH];
      end
    end
  endfunction

  function automatic logic signed [UVQ_WIDTH-1:0] q16_to_q24(
      input logic signed [DATA_WIDTH-1:0] value);
    logic signed [63:0] shifted;
    begin
      shifted = $signed({{(64-DATA_WIDTH){value[DATA_WIDTH-1]}}, value})
          <<< (UVQ_FRAC_WIDTH - FRAC_WIDTH);
      if (shifted > 64'sd2147483647) begin
        q16_to_q24 = signed'({1'b0, {(UVQ_WIDTH-1){1'b1}}});
      end else if (shifted < -64'sd2147483648) begin
        q16_to_q24 = signed'({1'b1, {(UVQ_WIDTH-1){1'b0}}});
      end else begin
        q16_to_q24 = shifted[UVQ_WIDTH-1:0];
      end
    end
  endfunction

  always_comb begin
    for (int i = 0; i < 3; i++) begin
      x[i] = COORD_WIDTH'($signed({1'b0, sx_i[i]}));
      y[i] = COORD_WIDTH'($signed({1'b0, sy_i[i]}));
      z_depth[i] = q16_to_depth(z_i[i]);
      q[i] = q16_to_q24(inv_w_i[i]);
    end

    dx10 = $signed({x[1][COORD_WIDTH-1], x[1]})
         - $signed({x[0][COORD_WIDTH-1], x[0]});
    dy20 = $signed({y[2][COORD_WIDTH-1], y[2]})
         - $signed({y[0][COORD_WIDTH-1], y[0]});
    dy10 = $signed({y[1][COORD_WIDTH-1], y[1]})
         - $signed({y[0][COORD_WIDTH-1], y[0]});
    dx20 = $signed({x[2][COORD_WIDTH-1], x[2]})
         - $signed({x[0][COORD_WIDTH-1], x[0]});
    area = $signed(dx10) * $signed(dy20) - $signed(dy10) * $signed(dx20);

    triangle_i = '{
      fbid_color: FBID_COLOR,
      fbid_depth: FBID_DEPTH,

      ax: x[0],
      ay: y[0],
      az: z_depth[0],
      auq: '0,
      avq: '0,
      aq: q[0],

      bx: x[1],
      by: y[1],
      bz: z_depth[1],
      buq: q[1],
      bvq: '0,
      bq: q[1],

      cx: x[2],
      cy: y[2],
      cz: z_depth[2],
      cuq: '0,
      cvq: q[2],
      cq: q[2]
    };

    if (area < AREA_ZERO) begin
      triangle_i.bx = x[2];
      triangle_i.by = y[2];
      triangle_i.bz = z_depth[2];
      triangle_i.buq = '0;
      triangle_i.bvq = q[2];
      triangle_i.bq = q[2];

      triangle_i.cx = x[1];
      triangle_i.cy = y[1];
      triangle_i.cz = z_depth[1];
      triangle_i.cuq = q[1];
      triangle_i.cvq = '0;
      triangle_i.cq = q[1];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rptr_q <= '0;
      wptr_q <= '0;
      depth_q <= '0;
      for (int i = 0; i < FIFO_DEPTH; i++) begin
        fifo_q[i] <= '0;
      end
    end else begin
      if (push) begin
        fifo_q[wptr_q] <= triangle_i;
        if (wptr_q == $clog2(FIFO_DEPTH)'(FIFO_DEPTH - 1)) begin
          wptr_q <= '0;
        end else begin
          wptr_q <= wptr_q + 1'b1;
        end
      end

      if (pop) begin
        if (rptr_q == $clog2(FIFO_DEPTH)'(FIFO_DEPTH - 1)) begin
          rptr_q <= '0;
        end else begin
          rptr_q <= rptr_q + 1'b1;
        end
      end

      unique case ({push, pop})
        2'b10: depth_q <= depth_q + 1'b1;
        2'b01: depth_q <= depth_q - 1'b1;
        default: ;
      endcase
    end
  end

`ifndef SYNTHESIS
  logic stalled_q;
  logic [10:0] stalled_sx_q [2:0];
  logic [10:0] stalled_sy_q [2:0];
  logic signed [DATA_WIDTH-1:0] stalled_z_q [2:0];
  logic signed [DATA_WIDTH-1:0] stalled_inv_w_q [2:0];

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      stalled_q <= 1'b0;
    end else begin
      if (stalled_q && !in_ready_o) begin
        if (!in_valid_i) begin
          $error("vertex_post_to_triangle2d input valid dropped before ready");
        end
        for (int i = 0; i < 3; i++) begin
          if (in_valid_i
              && (sx_i[i] !== stalled_sx_q[i]
                  || sy_i[i] !== stalled_sy_q[i]
                  || z_i[i] !== stalled_z_q[i]
                  || inv_w_i[i] !== stalled_inv_w_q[i])) begin
            $error("vertex_post_to_triangle2d input changed while stalled");
          end
        end
      end

      stalled_q <= in_valid_i && !in_ready_o;
      if (in_valid_i && !in_ready_o) begin
        for (int i = 0; i < 3; i++) begin
          stalled_sx_q[i] <= sx_i[i];
          stalled_sy_q[i] <= sy_i[i];
          stalled_z_q[i] <= z_i[i];
          stalled_inv_w_q[i] <= inv_w_i[i];
        end
      end
    end
  end
`endif

endmodule
