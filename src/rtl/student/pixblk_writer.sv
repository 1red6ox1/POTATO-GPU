// Copyright David Schröder 2026

module pixblk_writer
    import rvlab_ddr_pkg::*;
    import tlul_pkg::*;
(
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [31:0] pixblk_mask_i,
    input  logic [10:0] pixblk_cy_i,
    input  logic [ 5:0] pixblk_cx_i,
    input  logic        pixblk_valid_i,
    output logic        pixblk_ready_o,

    input  logic [ 1:0] fbid_i,

    output ddr3_h2d_t   ddr_o,
    input  ddr3_d2h_t   ddr_i
);

    logic [31:0] pixblk_mask_q;
    logic [10:0] pixblk_cy_q;
    logic [ 5:0] pixblk_cx_q;
    logic        pixblk_valid_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            pixblk_mask_q <= '0;
            pixblk_cy_q <= '0;
            pixblk_cx_q <= '0;
            pixblk_valid_q <= '0;
        end else begin
            if (pixblk_ready_o) begin
                pixblk_mask_q  <= pixblk_mask_i;
                pixblk_cy_q    <= pixblk_cy_i;
                pixblk_cx_q    <= pixblk_cx_i;
                pixblk_valid_q <= pixblk_valid_i;
            end
        end
    end

    assign ddr_o = '{
        a_valid: pixblk_valid_q,
        a_opcode: PutPartialData,
        a_address: {3'h0, fbid_i, pixblk_cy_q, pixblk_cx_q, 2'h0},
        a_mask: pixblk_mask_q,
        a_data: '1,
        a_anc: '0,
        d_ready: '1
    };

    assign pixblk_ready_o = !ddr_o.a_valid || ddr_i.a_ready;

endmodule
