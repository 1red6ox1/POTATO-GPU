module writer (
	input logic clk_i,
	input logic rst_ni,

	input  logic [1:0] fbid_color_i,
	input  logic [1:0] fbid_depth_i,
	input  logic [rasterizer_pkg::TILE_X_WIDTH-1:0] tile_x_i,
	input  logic [rasterizer_pkg::FRAME_Y_WIDTH-1:0] y_i,
	input  logic [255:0] red_i,
	input  logic [255:0] green_i,
	input  logic [255:0] blue_i,
	input  logic [255:0] depth1_i,
	input  logic [255:0] depth2_i,
	input  logic [31:0] mask_i,
	input  logic in_valid_i,
	output logic in_ready_o,
	output logic busy_o,

	output rvlab_ddr_pkg::ddr3_h2d_t ddr_o,
	input  rvlab_ddr_pkg::ddr3_d2h_t ddr_i
);

	import rasterizer_pkg::*;
	import rvlab_ddr_pkg::*;
	import tlul_pkg::*;

	typedef enum logic [2:0] {
		IDLE,
		RED,
		GREEN,
		BLUE,
		DEPTH1,
		DEPTH2
	} state_e;

	state_e state_q;

	logic [1:0] fbid_color_q;
	logic [1:0] fbid_depth_q;
	logic [TILE_X_WIDTH-1:0] tile_x_q;
	logic [FRAME_Y_WIDTH-1:0] y_q;
	logic [255:0] red_q;
	logic [255:0] green_q;
	logic [255:0] blue_q;
	logic [255:0] depth1_q;
	logic [255:0] depth2_q;
	logic [31:0] mask_q;
	logic [31:0] depth1_mask;
	logic [31:0] depth2_mask;
	logic [5:0] outstanding_q;

	assign in_ready_o = state_q == IDLE;
	assign busy_o = state_q != IDLE || outstanding_q != '0;

	always_comb begin
		depth1_mask = '0;
		depth2_mask = '0;

		for (int pixel = 0; pixel < TILE_WIDTH / 2; pixel++) begin
			depth1_mask[2 * pixel +: 2] = {2{mask_q[pixel]}};
			depth2_mask[2 * pixel +: 2] = {2{mask_q[TILE_WIDTH / 2 + pixel]}};
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			state_q <= IDLE;
		end else if (state_q == IDLE && in_valid_i && in_ready_o) begin
			if (mask_i == '0) begin
				state_q <= IDLE;
			end else begin
				state_q <= RED;
			end
		end else if (ddr_o.a_valid && ddr_i.a_ready) begin
			unique case (state_q)
				RED:    state_q <= GREEN;
				GREEN:  state_q <= BLUE;
				BLUE: begin
					if (|mask_q[TILE_WIDTH / 2 - 1:0]) begin
						state_q <= DEPTH1;
					end else if (|mask_q[TILE_WIDTH - 1:TILE_WIDTH / 2]) begin
						state_q <= DEPTH2;
					end else begin
						state_q <= IDLE;
					end
				end
				DEPTH1: begin
					if (|mask_q[TILE_WIDTH - 1:TILE_WIDTH / 2]) begin
						state_q <= DEPTH2;
					end else begin
						state_q <= IDLE;
					end
				end
				DEPTH2: state_q <= IDLE;
				default: state_q <= IDLE;
			endcase
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			fbid_color_q <= '0;
			fbid_depth_q <= '0;
			tile_x_q     <= '0;
			y_q          <= '0;
			red_q        <= '0;
			green_q      <= '0;
			blue_q       <= '0;
			depth1_q     <= '0;
			depth2_q     <= '0;
			mask_q       <= '0;
		end else if (in_valid_i && in_ready_o) begin
			fbid_color_q <= fbid_color_i;
			fbid_depth_q <= fbid_depth_i;
			tile_x_q     <= tile_x_i;
			y_q          <= y_i;
			red_q        <= red_i;
			green_q      <= green_i;
			blue_q       <= blue_i;
			depth1_q     <= depth1_i;
			depth2_q     <= depth2_i;
			mask_q       <= mask_i;
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if (~rst_ni) begin
			outstanding_q <= '0;
		end else begin
			unique case ({ddr_o.a_valid && ddr_i.a_ready, ddr_i.d_valid})
				2'b10: outstanding_q <= outstanding_q + 1'b1;
				2'b01: outstanding_q <= outstanding_q - 1'b1;
				default: begin
				end
			endcase
		end
	end

	always_comb begin
		ddr_o = '0;
		ddr_o.a_valid = state_q != IDLE;
		ddr_o.a_opcode = PutFullData;
		ddr_o.d_ready = 1'b1;

		unique case (state_q)
			RED: begin
				ddr_o.a_address = {3'h0, fbid_color_q, y_q, tile_x_q, 2'b00};
				ddr_o.a_mask = mask_q;
				ddr_o.a_data = red_q;
			end
			GREEN: begin
				ddr_o.a_address = {3'h0, fbid_color_q, y_q, tile_x_q, 2'b01};
				ddr_o.a_mask = mask_q;
				ddr_o.a_data = green_q;
			end
			BLUE: begin
				ddr_o.a_address = {3'h0, fbid_color_q, y_q, tile_x_q, 2'b10};
				ddr_o.a_mask = mask_q;
				ddr_o.a_data = blue_q;
			end
			DEPTH1: begin
				ddr_o.a_address = {4'h2, fbid_depth_q, y_q, 7'({tile_x_q, 1'b0})};
				ddr_o.a_mask = depth1_mask;
				ddr_o.a_data = depth1_q;
			end
			DEPTH2: begin
				ddr_o.a_address = {4'h2, fbid_depth_q, y_q, 7'({tile_x_q, 1'b1})};
				ddr_o.a_mask = depth2_mask;
				ddr_o.a_data = depth2_q;
			end
			default: begin
			end
		endcase
	end

`ifndef SYNTHESIS
	always @(posedge clk_i) begin
		if (in_valid_i && in_ready_o) begin
			$display("writer,%0t,input,fbid_color,%0d,fbid_depth,%0d,tile_x,%0d,y,%0d,red,%h,green,%h,blue,%h,depth1,%h,depth2,%h,mask,%h",
				$time, fbid_color_i, fbid_depth_i, tile_x_i, y_i,
				red_i, green_i, blue_i, depth1_i, depth2_i, mask_i);
		end

		if (ddr_o.a_valid && ddr_i.a_ready) begin
			$display("writer,%0t,address,%h,mask,%h,data,%h",
				$time, ddr_o.a_address, ddr_o.a_mask, ddr_o.a_data);
		end
	end
`endif

endmodule
