
module spi_host_core (
  input  logic        clk_i,
  input  logic        rst_ni,
  
  output logic        sclk0_o,
  output logic        sclk1_o,

  output logic        mosi0_o,
  output logic        mosi1_o,

  input  logic        miso0_i,
  input  logic        miso1_i,

  output logic        cs0_o,
  output logic        cs1_o,
  
  output logic [15:0] gamepad_0_buttons_o, 
  output logic        p0_data_valid_o,

  output logic [15:0] gamepad_1_buttons_o,
  output logic        p1_data_valid_o
);


spi_host spi_controller_0(
  .clk_i    (clk_i),
  .rst_ni   (rst_ni),
  
  .sclk_o   (sclk0_o),
  .pico_o   (mosi0_o),
  .poci_i   (miso0_i),

  .cs_o     (cs0_o),
  
  .gamepad_buttons_o  (gamepad_0_buttons_o), 
  .data_valid_o       (p0_data_valid_o)
);

spi_host spi_controller_2(
  .clk_i    (clk_i),
  .rst_ni   (rst_ni),
  
  .sclk_o   (sclk1_o),
  .pico_o   (mosi1_o),
  .poci_i   (miso1_i),

  .cs_o     (cs1_o),
  
  .gamepad_buttons_o  (gamepad_1_buttons_o), 
  .data_valid_o       (p1_data_valid_o)
);



endmodule