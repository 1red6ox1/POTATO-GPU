module hdmi_tb ();

	logic clk_pixel_x5, clk_pixel;
	logic reset1, resetn, reset;

	logic clk_100mhz, clk_55mhz, clk_fb, clk_fb2;

	always begin
		clk_100mhz <= '1;
		#5000;
		clk_100mhz <= '0;
		#5000;
	end

	MMCME2_BASE #(
	   .BANDWIDTH("OPTIMIZED"),   // Jitter programming (OPTIMIZED, HIGH, LOW)
	   .CLKFBOUT_MULT_F(11),     // Multiply value for all CLKOUT (2.000-64.000).
	   .CLKFBOUT_PHASE(0.0),      // Phase offset in degrees of CLKFB (-360.000-360.000).
	   .CLKIN1_PERIOD(10.0),       // Input clock period in ns to ps resolution (i.e. 33.333 is 30 MHz).
	   // CLKOUT0_DIVIDE - CLKOUT6_DIVIDE: Divide amount for each CLKOUT (1-128)
	   .CLKOUT1_DIVIDE(1),
	   .CLKOUT2_DIVIDE(1),
	   .CLKOUT3_DIVIDE(1),
	   .CLKOUT4_DIVIDE(1),
	   .CLKOUT5_DIVIDE(1),
	   .CLKOUT6_DIVIDE(1),
	   .CLKOUT0_DIVIDE_F(20.0),    // Divide amount for CLKOUT0 (1.000-128.000).
	   // CLKOUT0_DUTY_CYCLE - CLKOUT6_DUTY_CYCLE: Duty cycle for each CLKOUT (0.01-0.99).
	   .CLKOUT0_DUTY_CYCLE(0.5),
	   .CLKOUT1_DUTY_CYCLE(0.5),
	   .CLKOUT2_DUTY_CYCLE(0.5),
	   .CLKOUT3_DUTY_CYCLE(0.5),
	   .CLKOUT4_DUTY_CYCLE(0.5),
	   .CLKOUT5_DUTY_CYCLE(0.5),
	   .CLKOUT6_DUTY_CYCLE(0.5),
	   // CLKOUT0_PHASE - CLKOUT6_PHASE: Phase offset for each CLKOUT (-360.000-360.000).
	   .CLKOUT0_PHASE(0.0),
	   .CLKOUT1_PHASE(0.0),
	   .CLKOUT2_PHASE(0.0),
	   .CLKOUT3_PHASE(0.0),
	   .CLKOUT4_PHASE(0.0),
	   .CLKOUT5_PHASE(0.0),
	   .CLKOUT6_PHASE(0.0),
	   .CLKOUT4_CASCADE("FALSE"), // Cascade CLKOUT4 counter with CLKOUT6 (FALSE, TRUE)
	   .DIVCLK_DIVIDE(1),         // Master division value (1-106)
	   .REF_JITTER1(0.0),         // Reference input jitter in UI (0.000-0.999).
	   .STARTUP_WAIT("FALSE")     // Delays DONE until MMCM is locked (FALSE, TRUE)
	) mmcm_i (
	   // Clock Outputs: 1-bit (each) output: User configurable clock outputs
	   .CLKOUT0(clk_55mhz),     // 1-bit output: CLKOUT0
	   .CLKOUT0B(),   // 1-bit output: Inverted CLKOUT0
	   .CLKOUT1(),     // 1-bit output: CLKOUT1
	   .CLKOUT1B(),   // 1-bit output: Inverted CLKOUT1
	   .CLKOUT2(),     // 1-bit output: CLKOUT2
	   .CLKOUT2B(),   // 1-bit output: Inverted CLKOUT2
	   .CLKOUT3(),     // 1-bit output: CLKOUT3
	   .CLKOUT3B(),   // 1-bit output: Inverted CLKOUT3
	   .CLKOUT4(),     // 1-bit output: CLKOUT4
	   .CLKOUT5(),     // 1-bit output: CLKOUT5
	   .CLKOUT6(),     // 1-bit output: CLKOUT6
	   // Feedback Clocks: 1-bit (each) output: Clock feedback ports
	   .CLKFBOUT(clk_fb),   // 1-bit output: Feedback clock
	   .CLKFBOUTB(), // 1-bit output: Inverted CLKFBOUT
	   // Status Ports: 1-bit (each) output: MMCM status ports
	   .LOCKED(reset1),       // 1-bit output: LOCK
	   // Clock Inputs: 1-bit (each) input: Clock input
	   .CLKIN1(clk_100mhz),       // 1-bit input: Clock
	   // Control Ports: 1-bit (each) input: MMCM control ports
	   .PWRDWN('0),       // 1-bit input: Power-down
	   .RST('0),             // 1-bit input: Reset
	   // Feedback Clocks: 1-bit (each) input: Clock feedback ports
	   .CLKFBIN(clk_fb)      // 1-bit input: Feedback clock
	);

	MMCME2_BASE #(
	   .BANDWIDTH("OPTIMIZED"),   // Jitter programming (OPTIMIZED, HIGH, LOW)
	   .CLKFBOUT_MULT_F(27.0),     // Multiply value for all CLKOUT (2.000-64.000).
	   .CLKFBOUT_PHASE(0.0),      // Phase offset in degrees of CLKFB (-360.000-360.000).
	   .CLKIN1_PERIOD(18.181),       // Input clock period in ns to ps resolution (i.e. 33.333 is 30 MHz).
	   // CLKOUT0_DIVIDE - CLKOUT6_DIVIDE: Divide amount for each CLKOUT (1-128)
	   .CLKOUT1_DIVIDE(10),
	   .CLKOUT2_DIVIDE(1),
	   .CLKOUT3_DIVIDE(1),
	   .CLKOUT4_DIVIDE(1),
	   .CLKOUT5_DIVIDE(1),
	   .CLKOUT6_DIVIDE(1),
	   .CLKOUT0_DIVIDE_F(2.0),    // Divide amount for CLKOUT0 (1.000-128.000).
	   // CLKOUT0_DUTY_CYCLE - CLKOUT6_DUTY_CYCLE: Duty cycle for each CLKOUT (0.01-0.99).
	   .CLKOUT0_DUTY_CYCLE(0.5),
	   .CLKOUT1_DUTY_CYCLE(0.5),
	   .CLKOUT2_DUTY_CYCLE(0.5),
	   .CLKOUT3_DUTY_CYCLE(0.5),
	   .CLKOUT4_DUTY_CYCLE(0.5),
	   .CLKOUT5_DUTY_CYCLE(0.5),
	   .CLKOUT6_DUTY_CYCLE(0.5),
	   // CLKOUT0_PHASE - CLKOUT6_PHASE: Phase offset for each CLKOUT (-360.000-360.000).
	   .CLKOUT0_PHASE(0.0),
	   .CLKOUT1_PHASE(0.0),
	   .CLKOUT2_PHASE(0.0),
	   .CLKOUT3_PHASE(0.0),
	   .CLKOUT4_PHASE(0.0),
	   .CLKOUT5_PHASE(0.0),
	   .CLKOUT6_PHASE(0.0),
	   .CLKOUT4_CASCADE("FALSE"), // Cascade CLKOUT4 counter with CLKOUT6 (FALSE, TRUE)
	   .DIVCLK_DIVIDE(1),         // Master division value (1-106)
	   .REF_JITTER1(0.0),         // Reference input jitter in UI (0.000-0.999).
	   .STARTUP_WAIT("FALSE")     // Delays DONE until MMCM is locked (FALSE, TRUE)
	) mmcm_i2 (
	   // Clock Outputs: 1-bit (each) output: User configurable clock outputs
	   .CLKOUT0(clk_pixel_x5),     // 1-bit output: CLKOUT0
	   .CLKOUT0B(),   // 1-bit output: Inverted CLKOUT0
	   .CLKOUT1(clk_pixel),     // 1-bit output: CLKOUT1
	   .CLKOUT1B(),   // 1-bit output: Inverted CLKOUT1
	   .CLKOUT2(),     // 1-bit output: CLKOUT2
	   .CLKOUT2B(),   // 1-bit output: Inverted CLKOUT2
	   .CLKOUT3(),     // 1-bit output: CLKOUT3
	   .CLKOUT3B(),   // 1-bit output: Inverted CLKOUT3
	   .CLKOUT4(),     // 1-bit output: CLKOUT4
	   .CLKOUT5(),     // 1-bit output: CLKOUT5
	   .CLKOUT6(),     // 1-bit output: CLKOUT6
	   // Feedback Clocks: 1-bit (each) output: Clock feedback ports
	   .CLKFBOUT(clk_fb2),   // 1-bit output: Feedback clock
	   .CLKFBOUTB(), // 1-bit output: Inverted CLKFBOUT
	   // Status Ports: 1-bit (each) output: MMCM status ports
	   .LOCKED(resetn),       // 1-bit output: LOCK
	   // Clock Inputs: 1-bit (each) input: Clock input
	   .CLKIN1(clk_55mhz),       // 1-bit input: Clock
	   // Control Ports: 1-bit (each) input: MMCM control ports
	   .PWRDWN('0),       // 1-bit input: Power-down
	   .RST(!reset1),             // 1-bit input: Reset
	   // Feedback Clocks: 1-bit (each) input: Clock feedback ports
	   .CLKFBIN(clk_fb2)      // 1-bit input: Feedback clock
	);

	prim_rstsyn rstsyn_i (
		.clk_i (clk_pixel_x5),
		.rst_ni(!resetn),
		.rst_no(reset)
	);

	hdmi #(
		.VIDEO_ID_CODE            (16),
		.VIDEO_REFRESH_RATE       (60.0)
	) DUT (
		.clk_pixel_x5     (clk_pixel_x5),
		.clk_pixel        (clk_pixel),
		.clk_audio        (clk_pixel),
		.reset            (reset),

		.rgb              (24'hF000A6),
		.audio_sample_word({16'h0, 16'h0}),

		.tmds             (),
		.tmds_clock       (),
		.cx               (),
		.cy               (),
		.frame_width      (),
		.frame_height     (),
		.screen_width     (),
		.screen_height    ()
	);

endmodule
