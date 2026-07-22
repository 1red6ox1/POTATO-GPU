module gamepad_ctrl_tb;

  logic clk;
  logic rst_n;

  tlul_pkg::tl_h2d_t tl_h2d;
  tlul_pkg::tl_d2h_t tl_d2h;

  logic sclk0, mosi0, miso0, cs0;
  logic sclk1, mosi1, miso1, cs1;

  int unsigned errcnt;

  // 50 MHz
  always begin
    clk = '1;
    #10000;
    clk = '0;
    #10000;
  end

  // one poll is ~25k cycles, two polls plus the 8ms gap fit below this
  initial begin
    repeat (1_500_000) @(posedge clk);
    $display("### TESTS FAILED: GLOBAL WATCHDOG TIMEOUT ###");
    $fatal(1);
  end

  tlul_test_host bus (
    .clk_i (clk),
    .rst_no(rst_n),
    .tl_i  (tl_d2h),
    .tl_o  (tl_h2d)
  );

  gamepad_ctrl DUT (
    .clk_i  (clk),
    .rst_ni (rst_n),
    .tl_i   (tl_h2d),
    .tl_o   (tl_d2h),
    .sclk0_o(sclk0),
    .mosi0_o(mosi0),
    .miso0_i(miso0),
    .cs0_o  (cs0),
    .sclk1_o(sclk1),
    .mosi1_o(mosi1),
    .miso1_i(miso1),
    .cs1_o  (cs1)
  );

  // behavioral gamepad on port 0: answers the poll frame with id 0x41,
  // header 0x5A and the programmed button bytes (LSB first, active low)
  logic [7:0] pad_buttons_hi;   // active high, what the pad reports
  logic [7:0] pad_buttons_lo;
  logic [7:0] pad_tx_byte;
  int         pad_bit;
  int         pad_byte;
  logic [7:0] pad_rx_shift;

  function automatic logic [7:0] pad_response(input int byte_idx);
    case (byte_idx)
      0: return 8'hFF;
      1: return 8'h41;            // digital pad id
      2: return 8'h5A;            // header
      3: return ~pad_buttons_hi;  // active low on the wire
      4: return ~pad_buttons_lo;
      default: return 8'hFF;
    endcase
  endfunction

  initial miso0 = 1'b1;

  always @(negedge cs0) begin
    pad_bit  = 0;
    pad_byte = 0;
    pad_tx_byte = pad_response(0);
  end

  always @(negedge sclk0) begin
    if (!cs0) begin
      miso0 <= pad_tx_byte[pad_bit];  // LSB first
    end
  end

  always @(posedge sclk0) begin
    if (!cs0) begin
      pad_rx_shift = {mosi0, pad_rx_shift[7:1]};
      if (pad_bit == 7) begin
        // check the completed command byte
        if (pad_byte == 0 && pad_rx_shift !== 8'h01) begin
          $error("pad: first command byte was %02h, expected 01", pad_rx_shift);
          errcnt = errcnt + 1;
        end
        if (pad_byte == 1 && pad_rx_shift !== 8'h42) begin
          $error("pad: second command byte was %02h, expected 42", pad_rx_shift);
          errcnt = errcnt + 1;
        end
        pad_bit  = 0;
        pad_byte = pad_byte + 1;
        pad_tx_byte = pad_response(pad_byte);
      end else begin
        pad_bit = pad_bit + 1;
      end
    end
  end

  // no pad on port 1, the open drain line idles high through the pull-up
  assign miso1 = 1'b1;

  localparam logic [31:0] ADDR_BUTTONS0 = 32'h0;
  localparam logic [31:0] ADDR_BUTTONS1 = 32'h4;
  localparam logic [31:0] ADDR_STATUS   = 32'h8;

  logic [31:0] rdata;
  logic [31:0] status_before;

  initial begin
    errcnt = '0;
    miso0  = 1'b1;
    pad_buttons_hi = 8'h12;   // expected BUTTONS0 = 0x1234
    pad_buttons_lo = 8'h34;

    bus.reset();

    // before any poll completes the registers must read zero
    bus.get_word(ADDR_BUTTONS0, rdata);
    if (rdata !== 32'h0) begin
      $error("BUTTONS0 not zero after reset: %08h", rdata);
      errcnt = errcnt + 1;
    end
    bus.get_word(ADDR_STATUS, status_before);

    // first poll: setup + 5 bytes + gaps is ~25k cycles
    bus.wait_cycles(40_000);

    bus.get_word(ADDR_BUTTONS0, rdata);
    if (rdata !== 32'h0000_1234) begin
      $error("BUTTONS0 expected 00001234 got %08h", rdata);
      errcnt = errcnt + 1;
    end
    bus.get_word(ADDR_STATUS, rdata);
    if (rdata[7:0] !== 8'd1) begin
      $error("STATUS.polls0 expected 1 got %0d", rdata[7:0]);
      errcnt = errcnt + 1;
    end
    if (rdata[15:8] !== 8'd0) begin
      $error("STATUS.polls1 expected 0 (no pad) got %0d", rdata[15:8]);
      errcnt = errcnt + 1;
    end

    // change the buttons, the next poll starts after the 8ms wait
    pad_buttons_hi = 8'hAB;
    pad_buttons_lo = 8'hCD;
    bus.wait_cycles(440_000);

    bus.get_word(ADDR_BUTTONS0, rdata);
    if (rdata !== 32'h0000_ABCD) begin
      $error("BUTTONS0 expected 0000ABCD got %08h", rdata);
      errcnt = errcnt + 1;
    end
    bus.get_word(ADDR_STATUS, rdata);
    if (rdata[7:0] !== 8'd2) begin
      $error("STATUS.polls0 expected 2 got %0d", rdata[7:0]);
      errcnt = errcnt + 1;
    end

    // the disconnected pad must never produce data
    bus.get_word(ADDR_BUTTONS1, rdata);
    if (rdata !== 32'h0) begin
      $error("BUTTONS1 expected 0 (no pad) got %08h", rdata);
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
