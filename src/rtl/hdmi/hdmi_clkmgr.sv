// Copyright David Schröder 2026.

module hdmi_clkmgr (
	input  logic clk_100mhz_i,
	input  logic sys_rst_ni,

	output logic clk_pixel_o,
	output logic clk_fast_o, // 5X pixel clock
	output logic rst_no
);
	logic clk_pixel, clk_fast;
	logic mmcm1_lock, mmcm2_lock, resetn;

	logic clk_55mhz, clk_fb, clk_fb2;

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
	   .LOCKED(mmcm1_lock),       // 1-bit output: LOCK
	   // Clock Inputs: 1-bit (each) input: Clock input
	   .CLKIN1(clk_100mhz_i),       // 1-bit input: Clock
	   // Control Ports: 1-bit (each) input: MMCM control ports
	   .PWRDWN('0),       // 1-bit input: Power-down
	   .RST('0),             // 1-bit input: Reset
	   // Feedback Clocks: 1-bit (each) input: Clock feedback ports
	   .CLKFBIN(clk_fb)      // 1-bit input: Feedback clock
	);

	MMCME2_BASE #(
	   .BANDWIDTH("OPTIMIZED"),   // Jitter programming (OPTIMIZED, HIGH, LOW)
	   .CLKFBOUT_MULT_F(13.5),     // Multiply value for all CLKOUT (2.000-64.000).
	   .CLKFBOUT_PHASE(0.0),      // Phase offset in degrees of CLKFB (-360.000-360.000).
	   .CLKIN1_PERIOD(18.181),       // Input clock period in ns to ps resolution (i.e. 33.333 is 30 MHz).
	   // CLKOUT0_DIVIDE - CLKOUT6_DIVIDE: Divide amount for each CLKOUT (1-128)
	   .CLKOUT1_DIVIDE(5),
	   .CLKOUT2_DIVIDE(1),
	   .CLKOUT3_DIVIDE(1),
	   .CLKOUT4_DIVIDE(1),
	   .CLKOUT5_DIVIDE(1),
	   .CLKOUT6_DIVIDE(1),
	   .CLKOUT0_DIVIDE_F(1.0),    // Divide amount for CLKOUT0 (1.000-128.000).
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
	) mmcm2_i (
	   // Clock Outputs: 1-bit (each) output: User configurable clock outputs
	   .CLKOUT0(clk_fast),     // 1-bit output: CLKOUT0
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
	   .LOCKED(mmcm2_lock),       // 1-bit output: LOCK
	   // Clock Inputs: 1-bit (each) input: Clock input
	   .CLKIN1(clk_55mhz),       // 1-bit input: Clock
	   // Control Ports: 1-bit (each) input: MMCM control ports
	   .PWRDWN('0),       // 1-bit input: Power-down
	   .RST(~mmcm1_lock),             // 1-bit input: Reset
	   // Feedback Clocks: 1-bit (each) input: Clock feedback ports
	   .CLKFBIN(clk_fb2)      // 1-bit input: Feedback clock
	);

	prim_clock_gating clk_pix_cg_i (
		.clk_i    (clk_pixel),
		.en_i     (mmcm2_lock),
		.test_en_i('0),
		.clk_o    (clk_pixel_o)
	);

	prim_clock_gating clk_fast_cg_i (
		.clk_i    (clk_fast),
		.en_i     (mmcm2_lock),
		.test_en_i('0),
		.clk_o    (clk_fast_o)
	);

	prim_rstsyn rstsyn_i (
		.clk_i (clk_pixel_o),
		.rst_ni(mmcm2_lock & sys_rst_ni),
		.rst_no(rst_no)
	);

endmodule
