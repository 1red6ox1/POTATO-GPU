module writer (
	input logic clk_i,
	input logic rst_ni,

	input logic [255:0] data_i,
	input logic [31:0]  mask_i,
	input logic [23:0]  address_i,
	input logic         in_valid_i,
	output logic         in_ready_o,

	output rvlab_ddr_pkg::ddr3_h2d_t ddr_o,
	input rvlab_ddr_pkg::ddr3_d2h_t ddr_i
);

	import rvlab_ddr_pkg::*;
	import tlul_pkg::*;

	assign in_ready_o = ddr_i.a_ready;

	assign ddr_o = '{
		a_valid:  in_valid_i,
		a_opcode: PutFullData,
		a_address: address_i,
		a_mask:   mask_i,
		a_data:   data_i,
		a_anc:    '0,
		d_ready:  1'b1
	};

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (ddr_o.a_valid && ddr_i.a_ready) begin
			$display("writer,%0t,address,%h,mask,%h,data,%h",
			         $time, address_i, mask_i, data_i);
		end
	end
`endif

endmodule
