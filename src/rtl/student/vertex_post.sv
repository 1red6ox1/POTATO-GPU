/*
Post processing of a triangle after view and projection transform: This module
calculates the NDC and makes a view port transform (NDC to pixel coordinates)

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

  // Q16.16 reciprocal of w: 1 / w
  function automatic logic signed [DATA_WIDTH-1:0] recip(input logic signed [DATA_WIDTH-1:0] w);
    logic signed [63:0] num;
    begin
      num = 64'sd1 <<< (2*FRAC_WIDTH);
      if (w == 0) recip = '0;
      else        recip = num / w;
    end
  endfunction

  // Q16.16 fixed point multiply
  function automatic logic signed [DATA_WIDTH-1:0] mul_q(
      input logic signed [DATA_WIDTH-1:0] a,
      input logic signed [DATA_WIDTH-1:0] b);
    logic signed [2*DATA_WIDTH-1:0] p;
    begin
      p     = a * b;
      mul_q = p >>> FRAC_WIDTH;
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

  // Calculate 1 / w for each vertex
  logic signed [DATA_WIDTH-1:0] inv_w [2:0];
  always_comb begin
    for (int i = 0; i < 3; i++) begin
      inv_w[i] = recip(w_i[i]);
    end
  end

  // A vertex is behind the camera when the signs of z and w differ z/w < 0
  // Discard the whole triangle if any vertex is behind
  logic in_front;
  always_comb begin
    in_front = 1'b1;
    for (int i = 0; i < 3; i++) begin
      if (z_i[i][DATA_WIDTH-1] ^ w_i[i][DATA_WIDTH-1]) in_front = 1'b0;
    end
  end

  // Process only on a valid input. out_valid set to true when complete triangle is processed
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      out_valid <= 1'b0;
    end else begin
      out_valid <= in_valid && in_front;
      if (in_valid) begin
        for (int i = 0; i < 3; i++) begin
          sx_o[i]    <= vp_x(mul_q(x_i[i], inv_w[i]));
          sy_o[i]    <= vp_y(mul_q(y_i[i], inv_w[i]));
          z_o[i]     <= mul_q(z_i[i], inv_w[i]);
          inv_w_o[i] <= inv_w[i];
        end
      end
    end
  end

endmodule