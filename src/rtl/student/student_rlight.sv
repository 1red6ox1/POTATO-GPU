// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2024 RVLab Contributors

module student_rlight (
  input logic clk_i,
  input logic rst_ni,

  output tlul_pkg::tl_d2h_t tl_o,  //slave output (this module's response)
  input  tlul_pkg::tl_h2d_t tl_i,  //master input (incoming request)

  output logic [7:0] led_o,
  output logic       irq_left_o,
  output logic       irq_right_o
);

  student_rlight_reg_pkg::student_rlight_reg2hw_t reg2hw;
  student_rlight_reg_pkg::student_rlight_hw2reg_t hw2reg;

  student_rlight_reg_top reg_top_i (
    .clk_i,
    .rst_ni,

    .tl_i,
    .tl_o,

    .reg2hw,
    .hw2reg,
    .devmode_i('1)
  );

  logic [31:0] regN; // 00 - left; 01 - right; 10 - pingpong; 11 - stop
  logic [1:0] regMODE;
  logic [7:0] regPATTERN;

  logic [1:0] new_value_regMODE;
  logic [7:0] new_value_regPATTERN;

  logic new_regMODE;
  logic new_regPATTERN;

  // Bus writes
  // ----------

  logic [21:0] led; //0000000100000010000000
  logic [31:0] cnt;
  logic [4:0]  pos;
  logic        pingpong;

  assign hw2reg.reg_status.d  = led[14:7];
  assign hw2reg.reg_status.de = 1'b1;

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) begin
      regN       <= 32'd1;
      regMODE    <= 2'b10;
      regPATTERN <= 8'b10000001;
      led        <= 22'b0000000100000010000000;
      cnt        <= 8'd0;
      pos        <= 5'd14;
      pingpong   <= 1'b1;
      new_value_regPATTERN <= '0;
      new_regPATTERN <= 1'b0;
      new_value_regMODE <= '0;
      new_regMODE <= 1'b0;
    end else begin
      if (reg2hw.reg_n.qe) begin
        regN <= reg2hw.reg_n.q;
      end
      if (reg2hw.reg_mode.qe) begin
        new_value_regMODE <= reg2hw.reg_mode.q;
        new_regMODE <= 1'b1;
      end
      if (reg2hw.reg_pattern.qe) begin 
        new_value_regPATTERN <= reg2hw.reg_pattern.q;
        new_regPATTERN <= 1'b1;
      end
      if (cnt == 0) begin
        if (new_regMODE == 1) begin 
          if (((new_value_regMODE == 2) & (regMODE != 2)) | ((new_value_regMODE != 2) & (regMODE == 2))) begin //bei pin pong make reset
            regMODE <= new_value_regMODE;
            led[21:15] <= '0;
            led[14:7]  <= regPATTERN;
            led[6:0]   <= '0;
            cnt        <= regN - 1;
            pos        <= 5'd14;
            pingpong   <= 0;
            new_regMODE <= 1'b0;
          end else begin
            regMODE <= new_value_regMODE;
            cnt        <= regN - 1;
            new_regMODE <= 1'b0;
            case (new_value_regMODE)
              2'b00: begin
                led[7]    <= led[14];
                led[14:8] <= led[13:7];
              end
              2'b01: begin
                led[13:7] <= led[14:8];
                led[14]   <= led[7];
              end
              2'b10: begin
                if (((pingpong == 1) && (pos == 5'd20)) || ((pingpong == 0) && (pos == 5'd8))) begin
                  pingpong <= !pingpong;
                end
                if (pingpong) begin
                  led <= led << 1;
                  pos <= pos + 1;
                  end else begin
                  led <= led >> 1;
                  pos <= pos - 1;
                end
              end
              2'b11: begin
                led    <= led;
              end
            endcase;
          end
        end else if (reg2hw.reg_mode.qe) begin 
          if (((reg2hw.reg_mode.q == 2) & (regMODE != 2)) | ((reg2hw.reg_mode.q != 2) & (regMODE == 2))) begin //bei pin pong make reset
            regMODE    <= reg2hw.reg_mode.q;
            led[21:15] <= '0;
            led[14:7]  <= regPATTERN;
            led[6:0]   <= '0;
            cnt        <= regN - 1;
            pos        <= 5'd14;
            pingpong   <= 0;
            new_regMODE <= 1'b0;
          end else begin
            regMODE <= reg2hw.reg_mode.q;
            cnt        <= regN - 1;
            new_regMODE <= 1'b0;
            case (reg2hw.reg_mode.q)
              2'b00: begin
                led[7]    <= led[14];
                led[14:8] <= led[13:7];
              end
              2'b01: begin
                led[13:7] <= led[14:8];
                led[14]   <= led[7];
              end
              2'b10: begin
                if (((pingpong == 1) && (pos == 5'd20)) || ((pingpong == 0) && (pos == 5'd8))) begin
                  pingpong <= !pingpong;
                end
                if (pingpong) begin
                  led <= led << 1;
                  pos <= pos + 1;
                  end else begin
                  led <= led >> 1;
                  pos <= pos - 1;
                end
              end
              2'b11: begin
                led    <= led;
              end
            endcase;
          end
        end else if (new_regPATTERN == 1) begin
          regPATTERN <= new_value_regPATTERN;
          led[21:15] <= '0;
          led[14:7]  <= new_value_regPATTERN;
          led[6:0]   <= '0;
          cnt        <= regN - 1;
          pos        <= 5'd14;
          pingpong   <= 1'b1;
          new_regPATTERN <= 1'b0;
        end else if (reg2hw.reg_pattern.qe) begin 
          regPATTERN <= reg2hw.reg_pattern.q;
          led[21:15] <= '0;
          led[14:7]  <= reg2hw.reg_pattern.q;
          led[6:0]   <= '0;
          cnt        <= regN - 1;
          pos        <= 5'd14;
          pingpong   <= 1'b1;
          new_regPATTERN <= 1'b0;
        end else begin
          case (regMODE)
          2'b00: begin
            led[7]    <= led[14];
            led[14:8] <= led[13:7];
            cnt       <= regN - 1;
          end
          2'b01: begin
            led[13:7] <= led[14:8];
            led[14]   <= led[7];
            cnt       <= regN - 1;
          end
          2'b10: begin
            if (((pingpong == 1) && (pos == 5'd20)) || ((pingpong == 0) && (pos == 5'd8))) begin
              pingpong <= !pingpong;
            end
            if (pingpong) begin
              led <= led << 1;
              pos <= pos + 1;
            end else begin
              led <= led >> 1;
              pos <= pos - 1;
            end
            cnt <= regN - 1;
          end
          2'b11: begin
            led    <= led;
            cnt    <= regN - 1;
          end
        endcase;
        end
      end else begin
        cnt <= cnt - 1;
      end
    end 
  end

  assign led_o = led[14:7];
  assign irq_left_o = |led_o[7:6];
  assign irq_right_o = |led_o[1:0];

endmodule
