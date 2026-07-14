/*
Post processing of a triangle after view and projection transform: This module
calculates the NDC and makes a view port transform (NDC to pixel coordinates)

The 1 / w reciprocal is computed by a restoring shift subtract divider 

A triangle is accepted when in_valid and ready_o are both high.

TODO: Culling
*/

module vertex_post #(
  parameter int DATA_WIDTH = 32,
  parameter int FRAC_WIDTH = 16,
  parameter int SCREEN_W   = 1920,
  parameter int SCREEN_H   = 1080,
  parameter int SX_WIDTH   = 11,
  parameter int SY_WIDTH   = 11
) (
  input  logic clk,
  input  logic rst_n,

  // Should be set if the next triangle should be processed
  input  logic in_valid,

  // High while a new triangle can be accepted
  output logic ready_o,

  // Expects three vertices: One for each corner of a triangle
  input  logic signed [DATA_WIDTH-1:0] x_i [2:0],
  input  logic signed [DATA_WIDTH-1:0] y_i [2:0],
  input  logic signed [DATA_WIDTH-1:0] z_i [2:0],
  input  logic signed [DATA_WIDTH-1:0] w_i [2:0],

  // Is set if the triangle was processed
  output logic out_valid,

  output logic [SX_WIDTH-1:0]          sx_o    [2:0],
  output logic [SY_WIDTH-1:0]          sy_o    [2:0],
  output logic signed [DATA_WIDTH-1:0] z_o     [2:0],

  // 1 / w output per vertex
  output logic signed [DATA_WIDTH-1:0] inv_w_o [2:0]
);

  localparam int ONE_FP = 1 <<< FRAC_WIDTH;
  localparam int HALF_W = SCREEN_W / 2;
  localparam int HALF_H = SCREEN_H / 2;

  // The dividend 2^(2*FRAC_WIDTH) is the Q16.16 encoding of 1 / w, its MSB is
  // one quotient bit above the Q16.16 range so the quotient needs one extra bit
  localparam int DIV_STEPS = 2 * FRAC_WIDTH + 1;
  localparam int QUOT_W    = DIV_STEPS;
  localparam int CNT_W     = $clog2(DIV_STEPS);
  localparam logic [CNT_W-1:0] CNT_FIRST = CNT_W'(DIV_STEPS - 1);

  // Q16.16 fixed point multiply
  function automatic logic signed [DATA_WIDTH-1:0] mul_q(
      input logic signed [DATA_WIDTH-1:0] a,
      input logic signed [DATA_WIDTH-1:0] b);
    logic signed [2*DATA_WIDTH-1:0] p;
    begin
      p     = a * b;
      mul_q = DATA_WIDTH'(p >>> FRAC_WIDTH);
    end
  endfunction

  // Map x_ndc in [-1,1]
  function automatic logic [SX_WIDTH-1:0] vp_x(input logic signed [DATA_WIDTH-1:0] x);
    logic signed [63:0] px;
    begin
      px = ($signed(64'(x)) + ONE_FP) * HALF_W >>> FRAC_WIDTH;
      if (px < 0)               vp_x = '0;
      else if (px > SCREEN_W-1) vp_x = SX_WIDTH'(SCREEN_W-1);
      else                      vp_x = px[SX_WIDTH-1:0];
    end
  endfunction

  // Map y_ndc in [-1,1]
  function automatic logic [SY_WIDTH-1:0] vp_y(input logic signed [DATA_WIDTH-1:0] y);
    logic signed [63:0] py;
    begin
      py = (ONE_FP - $signed(64'(y))) * HALF_H >>> FRAC_WIDTH;
      if (py < 0)               vp_y = '0;
      else if (py > SCREEN_H-1) vp_y = SY_WIDTH'(SCREEN_H-1);
      else                      vp_y = py[SY_WIDTH-1:0];
    end
  endfunction

  // Sign fixup and Q16.16 of raw quotient. The remainder is
  // discarded so the result truncates toward zero like the previous
  // combinational division did
  function automatic logic signed [DATA_WIDTH-1:0] quot_to_inv_w(
      input logic [QUOT_W-1:0] quot,
      input logic              neg,
      input logic              zero);
    logic ovf;
    begin
      ovf = |quot[QUOT_W-1:DATA_WIDTH-1];
      if (zero)          quot_to_inv_w = '0;
      else if (!neg)     quot_to_inv_w = ovf ? signed'({1'b0, {(DATA_WIDTH-1){1'b1}}})
                                             : signed'(quot[DATA_WIDTH-1:0]);
      else               quot_to_inv_w = ovf ? signed'({1'b1, {(DATA_WIDTH-1){1'b0}}})
                                             : -signed'(quot[DATA_WIDTH-1:0]);
    end
  endfunction

  // A vertex is behind the camera when the signs of z and w differ z/w < 0
  // Discard the whole triangle if any vertex is behind
  logic in_front;
  always_comb begin
    in_front = 1'b1;
    for (int i = 0; i < 3; i++) begin
      if (z_i[i][DATA_WIDTH-1] ^ w_i[i][DATA_WIDTH-1]) in_front = 1'b0;
    end
  end

  typedef enum logic [1:0] {
    ST_IDLE,
    ST_DIV,
    ST_NDC,
    ST_OUT
  } state_e;

  state_e state_q;

  // Latched triangle and per vertex divider state
  logic signed [DATA_WIDTH-1:0] x_q     [2:0];
  logic signed [DATA_WIDTH-1:0] y_q     [2:0];
  logic signed [DATA_WIDTH-1:0] z_q     [2:0];
  logic                         w_neg   [2:0];
  logic                         w_zero  [2:0];
  logic        [DATA_WIDTH-1:0] denom   [2:0];
  logic        [DATA_WIDTH-1:0] rem_q   [2:0];
  logic        [QUOT_W-1:0]     quot_q  [2:0];
  logic signed [DATA_WIDTH-1:0] inv_w_q [2:0];
  logic signed [DATA_WIDTH-1:0] ndc_x_q [2:0];
  logic signed [DATA_WIDTH-1:0] ndc_y_q [2:0];
  logic signed [DATA_WIDTH-1:0] ndc_z_q [2:0];
  logic        [CNT_W-1:0]      cnt_q;

  // One restoring division step per cycle: shift the next dividend bit into
  // the remainder and subtract the divisor unless that would underflow. The
  // dividend is 2^(2*FRAC_WIDTH) so only the first step shifts in a one.
  // rem_q < denom <= 2^(DATA_WIDTH-1) holds after every step
  logic [DATA_WIDTH-1:0] rem_shifted [2:0];
  logic                  skip_sub    [2:0];
  logic [DATA_WIDTH-1:0] rem_d       [2:0];
  logic [QUOT_W-1:0]     quot_d      [2:0];
  always_comb begin
    for (int i = 0; i < 3; i++) begin
      rem_shifted[i] = {rem_q[i][DATA_WIDTH-2:0], cnt_q == CNT_FIRST};
      skip_sub[i]    = rem_shifted[i] < denom[i];
      rem_d[i]       = skip_sub[i] ? rem_shifted[i] : rem_shifted[i] - denom[i];
      quot_d[i]      = {quot_q[i][QUOT_W-2:0], ~skip_sub[i]};
    end
  end

  assign ready_o = (state_q == ST_IDLE) && rst_n;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state_q   <= ST_IDLE;
      out_valid <= 1'b0;
    end else begin
      out_valid <= 1'b0;

      case (state_q)
        ST_IDLE: begin
          // A culled triangle is dropped here
          if (in_valid && in_front) begin
            for (int i = 0; i < 3; i++) begin
              x_q[i]    <= x_i[i];
              y_q[i]    <= y_i[i];
              z_q[i]    <= z_i[i];
              w_neg[i]  <= w_i[i][DATA_WIDTH-1];
              w_zero[i] <= w_i[i] == '0;
              denom[i]  <= w_i[i][DATA_WIDTH-1] ? unsigned'(-w_i[i]) : unsigned'(w_i[i]);
              rem_q[i]  <= '0;
              quot_q[i] <= '0;
            end
            cnt_q   <= CNT_FIRST;
            state_q <= ST_DIV;
          end
        end

        ST_DIV: begin
          for (int i = 0; i < 3; i++) begin
            rem_q[i]  <= rem_d[i];
            quot_q[i] <= quot_d[i];
          end
          cnt_q <= cnt_q - 1'b1;
          if (cnt_q == '0) begin
            for (int i = 0; i < 3; i++) begin
              inv_w_q[i] <= quot_to_inv_w(quot_d[i], w_neg[i], w_zero[i]);
            end
            state_q <= ST_NDC;
          end
        end

        ST_NDC: begin
          for (int i = 0; i < 3; i++) begin
            ndc_x_q[i] <= mul_q(x_q[i], inv_w_q[i]);
            ndc_y_q[i] <= mul_q(y_q[i], inv_w_q[i]);
            ndc_z_q[i] <= mul_q(z_q[i], inv_w_q[i]);
          end
          state_q <= ST_OUT;
        end

        ST_OUT: begin
          for (int i = 0; i < 3; i++) begin
            sx_o[i]    <= vp_x(ndc_x_q[i]);
            sy_o[i]    <= vp_y(ndc_y_q[i]);
            z_o[i]     <= ndc_z_q[i];
            inv_w_o[i] <= inv_w_q[i];
          end
          out_valid <= 1'b1;
          state_q   <= ST_IDLE;
        end

        default: state_q <= ST_IDLE;
      endcase
    end
  end

endmodule
