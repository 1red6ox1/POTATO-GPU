// Copyright David Schröder 2026

module rasterizer_x32 (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic signed [31:0] ddx_i,
    output logic signed [31:0] ddx_o [31:0]
);

    logic signed [31:0] shift1;
    logic signed [31:0] shift2;
    logic signed [31:0] shift3;
    logic signed [31:0] shift4;

    assign shift1 = ddx_i << 4;
    assign shift2 = ddx_i << 5;
    assign shift3 = ddx_i << 6;
    assign shift4 = ddx_i << 7;

    logic signed [31:0] ddx [31:0];

    assign ddx[ 0] = '0;
    assign ddx[16] = shift4;

    assign ddx[ 8] = ddx[ 0] + shift3;
    assign ddx[24] = ddx[16] + shift3;

    assign ddx[ 4] = ddx[ 0] + shift2;
    assign ddx[12] = ddx[ 8] + shift2;
    assign ddx[20] = ddx[16] + shift2;
    assign ddx[28] = ddx[24] + shift2;

    assign ddx[ 2] = ddx[ 0] + shift1;
    assign ddx[ 6] = ddx[ 4] + shift1;
    assign ddx[10] = ddx[ 8] + shift1;
    assign ddx[14] = ddx[12] + shift1;
    assign ddx[18] = ddx[16] + shift1;
    assign ddx[22] = ddx[20] + shift1;
    assign ddx[26] = ddx[24] + shift1;
    assign ddx[30] = ddx[28] + shift1;

    assign ddx[ 1] = ddx[ 0] + (ddx_i << 3);
    assign ddx[ 3] = ddx[ 2] + (ddx_i << 3);
    assign ddx[ 5] = ddx[ 4] + (ddx_i << 3);
    assign ddx[ 7] = ddx[ 6] + (ddx_i << 3);
    assign ddx[ 9] = ddx[ 8] + (ddx_i << 3);
    assign ddx[11] = ddx[10] + (ddx_i << 3);
    assign ddx[13] = ddx[12] + (ddx_i << 3);
    assign ddx[15] = ddx[14] + (ddx_i << 3);
    assign ddx[17] = ddx[16] + (ddx_i << 3);
    assign ddx[19] = ddx[18] + (ddx_i << 3);
    assign ddx[21] = ddx[20] + (ddx_i << 3);
    assign ddx[23] = ddx[22] + (ddx_i << 3);
    assign ddx[25] = ddx[24] + (ddx_i << 3);
    assign ddx[27] = ddx[26] + (ddx_i << 3);
    assign ddx[29] = ddx[28] + (ddx_i << 3);
    assign ddx[31] = ddx[30] + (ddx_i << 3);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            ddx_o <= '{default: '0};
        end else begin
            ddx_o <= ddx;
        end
    end

endmodule
