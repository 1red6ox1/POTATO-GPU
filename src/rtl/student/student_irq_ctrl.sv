module student_irq_ctrl #(
	parameter int IRQ_MAX = 32
) (
	input logic clk_i,
	input logic rst_ni,

	output tlul_pkg::tl_d2h_t tl_o,
	input tlul_pkg::tl_h2d_t tl_i,

	input logic [IRQ_MAX-1:0] irq_i,
	output logic irq_o
);
	import student_irq_ctrl_reg_pkg::*;
	
	student_irq_ctrl_reg2hw_t reg2hw;
	student_irq_ctrl_hw2reg_t hw2reg;
	
	logic all_enable;
	assign all_enable = reg2hw.all_en.q;
	
	logic [IRQ_MAX-1:0] irq_vector;
	
	assign irq_o = all_enable & |irq_vector;
	
	assign hw2reg.status.de = '1;
	assign hw2reg.status.d = irq_vector;
	
	student_irq_ctrl_reg_top irq_ctrl_reg (
		.clk_i,
		.rst_ni,
		
		.tl_i,
		.tl_o,
		
		.reg2hw,
		.hw2reg,
		
		.devmode_i('1)
	);

	// Mask logic
	logic [IRQ_MAX-1:0] irq_mask, next_irq_mask;
	always_comb begin
		next_irq_mask = irq_mask;
		if (reg2hw.mask.qe) next_irq_mask = reg2hw.mask.q;
		if (reg2hw.mask_set.qe) next_irq_mask = next_irq_mask | reg2hw.mask_set.q;
		if (reg2hw.mask_clr.qe) next_irq_mask = next_irq_mask & ~reg2hw.mask_clr.q;
	end

	always_ff @(posedge clk_i, negedge rst_ni) begin
		if (~rst_ni) begin
			irq_mask <= '0;
		end else begin
			irq_mask <= next_irq_mask;
		end
	end
	
	// if any bits have been flipped by hw, update mask reg
	assign hw2reg.mask.de = |(next_irq_mask ^ reg2hw.mask.q);
	assign hw2reg.mask.d = irq_mask;

	// IRQ Vector generation logic
	assign irq_vector = (reg2hw.test.q ? reg2hw.test_irq.q : irq_i) & irq_mask;
	
	// count trailing zeroes
	logic [$clog2(IRQ_MAX):0] tz_count;
	always_comb begin
		tz_count = IRQ_MAX;
		for (int i = IRQ_MAX; i > 0; i = i - 1) begin
			if (irq_vector[i-1]) tz_count = i-1;
		end
	end

	assign hw2reg.irq_no.de = '1;
	assign hw2reg.irq_no.d = tz_count;
	
endmodule
