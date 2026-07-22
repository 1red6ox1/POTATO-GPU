// TL-UL front end for two SPI gamepads

module gamepad_ctrl (
  input  logic clk_i,
  input  logic rst_ni,

  input  tlul_pkg::tl_h2d_t tl_i,
  output tlul_pkg::tl_d2h_t tl_o,

  output logic sclk0_o,
  output logic mosi0_o,
  input  logic miso0_i,
  output logic cs0_o,

  output logic sclk1_o,
  output logic mosi1_o,
  input  logic miso1_i,
  output logic cs1_o
);

gamepad_ctrl_reg_pkg::gamepad_ctrl_reg2hw_t reg2hw;
gamepad_ctrl_reg_pkg::gamepad_ctrl_hw2reg_t hw2reg;

logic miso0_sync, miso1_sync;
logic [15:0] buttons0, buttons1;
logic valid0, valid1;
logic [7:0] polls0, polls1;   // wrapping poll counters for the STATUS register

// register file

gamepad_ctrl_reg_top reg_top_i (
  .clk_i,
  .rst_ni,
  .tl_i,
  .tl_o,
  .reg2hw,
  .hw2reg,
  .devmode_i('1)
);

// synchronize the miso pins (asynchronous inputs from the gamepad cable)

prim_flop_2sync #(.Width(1)) miso0_sync_i (
  .clk_i,
  .rst_ni,
  .d (miso0_i),
  .q (miso0_sync)
);

prim_flop_2sync #(.Width(1)) miso1_sync_i (
  .clk_i,
  .rst_ni,
  .d (miso1_i),
  .q (miso1_sync)
);

// spi hosts

spi_host_core spi_host_core_i (
  .clk_i,
  .rst_ni,
  .sclk0_o,
  .sclk1_o,
  .mosi0_o,
  .mosi1_o,
  .miso0_i (miso0_sync),
  .miso1_i (miso1_sync),
  .cs0_o,
  .cs1_o,
  .gamepad_0_buttons_o (buttons0),
  .p0_data_valid_o     (valid0),
  .gamepad_1_buttons_o (buttons1),
  .p1_data_valid_o     (valid1)
);

// button registers only update on a completed poll

assign hw2reg.buttons0.d  = buttons0;
assign hw2reg.buttons0.de = valid0;
assign hw2reg.buttons1.d  = buttons1;
assign hw2reg.buttons1.de = valid1;

// poll counters

always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    polls0 <= 8'd0;
    polls1 <= 8'd0;
  end else begin
    if (valid0) polls0 <= polls0 + 1'b1;
    if (valid1) polls1 <= polls1 + 1'b1;
  end
end

assign hw2reg.status.polls0.d  = polls0;
assign hw2reg.status.polls0.de = 1'b1;
assign hw2reg.status.polls1.d  = polls1;
assign hw2reg.status.polls1.de = 1'b1;

endmodule
