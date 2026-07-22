
module spi_host (
  input  logic        clk_i,
  input  logic        rst_ni,
  
  output logic        sclk_o,
  output logic        pico_o,
  input  logic        poci_i,

  output logic        cs_o,
  
  output logic [15:0] gamepad_buttons_o, 
  output logic        data_valid_o
);

typedef enum logic [2:0] {
  IDLE          = 3'b000,
  SETUP         = 3'b001,
  SEND_WAKE     = 3'b010,
  SEND_POLL     = 3'b011,
  RECV_HEADER   = 3'b100,
  RECV_BTNS     = 3'b101,
  WAIT          = 3'b110,
  BYTE_WAIT     = 3'b111
} state_e;

state_e current_state, next_state;

logic falling_edge, rising_edge;

logic [6:0] clk_count; 
logic [3:0] bit_count;   // count which bit within a byte is currently being recieved (0-8)
logic [2:0] byte_count;  // count which byte of Transmission is currently recieved (0-5)
logic [23:0] wait_count;
logic [8:0] setup_counter;

logic [7:0] tx_shift;
logic [7:0] rx_shift;

logic [7:0] rx_byte;
logic rx_byte_valid;

logic [7:0] shift_reg;
logic [7:0] pico_data;      // byte being sent
logic [15:0] button_buffer; // Temporary hold for incoming buttons

logic sclk_tick;

// Multiplexer to send correct byte
always_comb begin
  case(byte_count)
    3'd0    : pico_data = 8'h01;
    3'd1    : pico_data = 8'h42;
    default : pico_data = 8'h00;
  endcase
end

always_ff @(posedge clk_i, negedge rst_ni) begin
  if (!rst_ni) begin
    current_state <= IDLE;
  end else begin
    current_state <= next_state;
  end
end

//state transitions
always_comb begin
  next_state = current_state;
  case (current_state)

    IDLE: begin
      // Initial state to give controller 1 tick time to wake (Maybe need to give more...)
      next_state = SETUP;
    end

    SETUP: begin
      if (setup_counter == 9'd500) begin
        next_state = SEND_WAKE;
      end
    end

    SEND_WAKE: begin
      // if received first byte ask for data
      if (rx_byte_valid) begin
        next_state = BYTE_WAIT;
      end
    end

    SEND_POLL: begin
      // if received second byte complete handshake
      if (rx_byte_valid) begin
        next_state = BYTE_WAIT;
      end
    end

    RECV_HEADER: begin
      if (rx_byte_valid) begin
        if ({poci_i, rx_shift[7:1]} == 8'h5A) begin
          next_state = BYTE_WAIT;
        end else begin
          next_state = WAIT; 
        end
      end
    end

    RECV_BTNS: begin
      // if sent 5 byte wait so controller can recover
      if (rx_byte_valid) begin
        if (byte_count == 3'd4) begin
          next_state = WAIT;
        end else begin
          next_state = BYTE_WAIT;
        end
      end
    end

    WAIT: begin
      // 8ms wait
      if (wait_count == 24'd400_000) begin
        next_state = IDLE;
      end
    end

    BYTE_WAIT: begin
      if (wait_count == 24'd1_000) begin
        case (byte_count)
          3'd1: next_state = SEND_POLL;
          3'd2: next_state = RECV_HEADER;
          3'd3, 3'd4: next_state = RECV_BTNS;
          default: next_state = IDLE;
        endcase
      end
    end

    default: next_state = IDLE;
  endcase
end

assign rx_byte_valid = (bit_count == 4'd7) && rising_edge;

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (current_state != next_state) begin
      $display("[RTL LOG] State changing from %s to %s.", 
                current_state.name(), next_state.name());
    end
  end
`endif

//shifting logic
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    pico_o         <= 1'b1;
    tx_shift       <= 8'h00;
    rx_shift       <= 8'h00;
  end else if (current_state == IDLE || current_state == WAIT) begin
    pico_o         <= 1'b1;
    tx_shift       <= 8'h00;
    rx_shift       <= 8'h00;
  end else begin 

  if (falling_edge) begin
      if (bit_count == 4'd0) begin
        pico_o   <= pico_data[0];
        tx_shift <= {1'b0, pico_data[7:1]};
      end else begin
        pico_o   <= tx_shift[0];
        tx_shift <= {1'b0, tx_shift[7:1]};
      end
    end

    if (rising_edge) begin
      rx_shift <= {poci_i, rx_shift[7:1]};

      `ifndef SYNTHESIS
        if (bit_count == 4'd7) begin
          $display("[RTL LOG] byte: %h recieved", {poci_i, rx_shift[7:1]});
        end
      `endif

    end
  end
end

// output
logic active_transaction;
assign active_transaction =  (current_state == SETUP)       ||
                             (current_state == SEND_WAKE)   || 
                             (current_state == SEND_POLL)   || 
                             (current_state == RECV_HEADER) || 
                             (current_state == BYTE_WAIT)   ||
                             (current_state == RECV_BTNS);


always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    cs_o <= 1'b1; 
  end else begin
    cs_o <= 1'b1;

  if (active_transaction) begin
      cs_o <= 1'b0;
    end
  end
end

always_ff @(posedge clk_i, negedge rst_ni) begin
  if (!rst_ni) begin
    button_buffer     <= 16'hFFFF; 
    gamepad_buttons_o <= 16'h0000;
    data_valid_o     <= 1'b0;

  end else begin
    data_valid_o     <= 1'b0;

    // read data on rising edge
    if (rising_edge && bit_count == 4'd7 && current_state == RECV_BTNS) begin
      case (byte_count)
        3'd3: begin
          button_buffer[15:8] <= {poci_i, rx_shift[7:1]};
        end
        
        3'd4: begin
          button_buffer[7:0] <= {poci_i, rx_shift[7:1]};
          gamepad_buttons_o <= ~{button_buffer[15:8], poci_i, rx_shift[7:1]};
          data_valid_o     <= 1'b1;
        end
      endcase
    end
  end
end

// wait timer 

always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    wait_count     <= 24'd0;
    setup_counter  <= 9'd0;
  end else begin
    

    if (current_state == WAIT || current_state == BYTE_WAIT) begin
      wait_count <= wait_count + 1'b1;
    end else begin
      wait_count <= 24'd0; 
    end

    if (current_state == SETUP) begin
      setup_counter <= setup_counter + 1'b1;
    end else begin
      setup_counter <= 9'd0; 
    end

  end
end

// clock divider

assign sclk_tick = (clk_count == 7'd99);

always_ff @(posedge clk_i, negedge rst_ni) begin
  if (!rst_ni) begin
    clk_count   <= 7'd0;
    sclk_o      <= 1'b1; 
  end else begin
    if (current_state == SEND_WAKE || current_state == SEND_POLL || current_state == RECV_HEADER || current_state == RECV_BTNS) begin
        
      if (sclk_tick) begin
        clk_count <= 7'd0;
        sclk_o    <= ~sclk_o; 
      end else begin
        clk_count <= clk_count + 1'b1;
      end
      
    end else begin
      clk_count   <= 7'd0;
      sclk_o      <= 1'b1; 
    end
  end
end

// edge detection

logic sclk_q; 

always_ff @(posedge clk_i, negedge rst_ni) begin
  if (!rst_ni) begin
    sclk_q <= 1'b1;
  end else begin
    sclk_q <= sclk_o; 
  end
end

assign rising_edge  = (sclk_o == 1'b1) && (sclk_q == 1'b0);
assign falling_edge = (sclk_o == 1'b0) && (sclk_q == 1'b1);

// byte_count and bit_count update

always_ff @(posedge clk_i, negedge rst_ni) begin
  if(!rst_ni) begin
    bit_count  <= 4'd0;
    byte_count <= 3'd0;
  end else begin

    if (current_state == SEND_WAKE || current_state == SEND_POLL || current_state == RECV_HEADER || current_state == RECV_BTNS) begin

      if (rising_edge) begin
        if (bit_count == 4'd7) begin
          bit_count  <= 4'd0;
          byte_count <= byte_count + 1'b1;
        end else begin
          bit_count  <= bit_count + 1'b1;
        end
      end

    end else begin
      bit_count  <= 4'd0;
      if (current_state == IDLE) begin
          byte_count <= 3'd0;
      end     
    end
  end
end

endmodule