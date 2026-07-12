// Copyright David Schröder 2026

module rasterizer_core (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic signed [63:0] ab_topleft_i,
    input  logic signed [63:0] bc_topleft_i,
    input  logic signed [63:0] ca_topleft_i,
    input  logic signed [63:0] un_topleft_i,
    input  logic signed [63:0] vn_topleft_i,
    input  logic signed [63:0] iw_topleft_i,

    /* All x/y/dx/dy inputs are in
       1/8th subpixel units */

    input  logic signed [31:0] ab_dx_i,
    input  logic signed [31:0] ab_dy_i,
    input  logic signed [31:0] bc_dx_i,
    input  logic signed [31:0] bc_dy_i,
    input  logic signed [31:0] ca_dx_i,
    input  logic signed [31:0] ca_dy_i,
    input  logic signed [31:0] un_dx_i,
    input  logic signed [31:0] un_dy_i,
    input  logic signed [31:0] vn_dx_i,
    input  logic signed [31:0] vn_dy_i,
    input  logic signed [31:0] iw_dx_i,
    input  logic signed [31:0] iw_dy_i,

    input  logic [15:0] min_x_i,
    input  logic [15:0] min_y_i,
    input  logic [15:0] max_x_i,
    input  logic [15:0] max_y_i,

    input  logic        start_i,
    output logic        idle_o,

    output logic [31:0] pixblk_mask_o,
    output logic [10:0] pixblk_cy_o,
    output logic [ 5:0] pixblk_cx_o,
    output logic        pixblk_valid_o,
    input  logic        pixblk_ready_i
);

    /* Raster grid control */

    logic [ 7:0] seg_x_q, seg_x_d;
    logic [ 7:0] seg_x_min, seg_x_max;
    logic [12:0] seg_y_q, seg_y_d;
    logic [12:0] seg_y_min, seg_y_max;

    logic [15:0] subpix_x_start, subpix_y_start;

    assign subpix_x_start = {min_x_i[15:3], 3'h0} - 1'b1;
    assign subpix_y_start = {min_y_i[15:3], 3'h0} - 1'b1;

    assign seg_x_min = subpix_x_start[15:8];
    assign seg_y_min = subpix_y_start[15:3];
    assign seg_x_max = max_x_i[15:8];
    assign seg_y_max = max_y_i[15:3];

    /* State logic */

    typedef enum logic [0:0] {
        IDLE,
        BUSY
    } state_e;

    state_e state_d, state_q;

    assign idle_o = state_q == IDLE;

    /* Segment update control */

    always_comb begin
        seg_x_d = seg_x_min;
        if (state_q == BUSY) begin
            if (seg_x_q == seg_x_max) begin
                seg_x_d = seg_x_min;
            end else begin
                seg_x_d = seg_x_q + 1;
            end
        end

        seg_y_d = seg_y_min;
        if (state_q == BUSY) begin
            if (seg_x_q == seg_x_max) seg_y_d = seg_y_q + 1;
            else seg_y_d = seg_y_q;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            seg_x_q <= '0;
            seg_y_q <= '0;
        end else begin
            if (!pixblk_valid_o || pixblk_ready_i) begin
                seg_x_q <= seg_x_d;
                seg_y_q <= seg_y_d;
            end
        end
    end

    /* Control FSM */

    always_comb begin
        state_d = state_q;
        case (state_d)
            IDLE: begin
                if (start_i) state_d = BUSY;
            end
            BUSY: begin
                if (seg_x_q == seg_x_max && seg_y_q == seg_y_max) begin
                    state_d = IDLE;
                end
            end
            default: ;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            state_q <= IDLE;
        end else begin
            state_q <= state_d;
        end
    end

    /* Pixel derivatives */

    logic signed [31:0] pix_ddx_ab [31:0];
    logic signed [31:0] pix_ddx_bc [31:0];
    logic signed [31:0] pix_ddx_ca [31:0];
    logic signed [31:0] pix_ddx_un [31:0];
    logic signed [31:0] pix_ddx_vn [31:0];
    logic signed [31:0] pix_ddx_iw [31:0];

    rasterizer_x32 x32_ab_i (
        .clk_i,
        .rst_ni,
        .ddx_i(ab_dx_i),
        .ddx_o(pix_ddx_ab)
    );

    rasterizer_x32 x32_bc_i (
        .clk_i,
        .rst_ni,
        .ddx_i(bc_dx_i),
        .ddx_o(pix_ddx_bc)
    );

    rasterizer_x32 x32_ca_i (
        .clk_i,
        .rst_ni,
        .ddx_i(ca_dx_i),
        .ddx_o(pix_ddx_ca)
    );

    rasterizer_x32 x32_un_i (
        .clk_i,
        .rst_ni,
        .ddx_i(un_dx_i),
        .ddx_o(pix_ddx_un)
    );

    rasterizer_x32 x32_vn_i (
        .clk_i,
        .rst_ni,
        .ddx_i(vn_dx_i),
        .ddx_o(pix_ddx_vn)
    );

    rasterizer_x32 x32_iw_i (
        .clk_i,
        .rst_ni,
        .ddx_i(iw_dx_i),
        .ddx_o(pix_ddx_iw)
    );

    /* Cell + Row Interpolation */

    logic signed [31:0] row_base_ab;
    logic signed [31:0] row_base_bc;
    logic signed [31:0] row_base_ca;
    logic signed [31:0] row_base_un;
    logic signed [31:0] row_base_vn;
    logic signed [31:0] row_base_iw;

    logic signed [31:0] cell_base_ab;
    logic signed [31:0] cell_base_bc;
    logic signed [31:0] cell_base_ca;
    logic signed [31:0] cell_base_un;
    logic signed [31:0] cell_base_vn;
    logic signed [31:0] cell_base_iw;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            row_base_ab <= '0;
            row_base_bc <= '0;
            row_base_ca <= '0;
            row_base_un <= '0;
            row_base_vn <= '0;
            row_base_iw <= '0;
            cell_base_ab <= '0;
            cell_base_bc <= '0;
            cell_base_ca <= '0;
            cell_base_un <= '0;
            cell_base_vn <= '0;
            cell_base_iw <= '0;
        end else begin
            if (state_q == IDLE && state_d == BUSY) begin
                row_base_ab <= '0;
                row_base_bc <= '0;
                row_base_ca <= '0;
                row_base_un <= '0;
                row_base_vn <= '0;
                row_base_iw <= '0;
                cell_base_ab <= '0;
                cell_base_bc <= '0;
                cell_base_ca <= '0;
                cell_base_un <= '0;
                cell_base_vn <= '0;
                cell_base_iw <= '0;
            end else if (state_q == BUSY) begin
                if (!pixblk_valid_o || pixblk_ready_i) begin
                    if (seg_x_q == seg_x_max) begin
                        row_base_ab  <= row_base_ab + (ab_dy_i << 3);
                        cell_base_ab <= row_base_ab + (ab_dy_i << 3);
                        row_base_bc  <= row_base_bc + (bc_dy_i << 3);
                        cell_base_bc <= row_base_bc + (bc_dy_i << 3);
                        row_base_ca  <= row_base_ca + (ca_dy_i << 3);
                        cell_base_ca <= row_base_ca + (ca_dy_i << 3);
                        row_base_un  <= row_base_un + (un_dy_i << 3);
                        cell_base_un <= row_base_un + (un_dy_i << 3);
                        row_base_vn  <= row_base_vn + (vn_dy_i << 3);
                        cell_base_vn <= row_base_vn + (vn_dy_i << 3);
                        row_base_iw  <= row_base_iw + (iw_dy_i << 3);
                        cell_base_iw <= row_base_iw + (iw_dy_i << 3);
                    end else begin
                        cell_base_ab <= cell_base_ab + (ab_dx_i << 8);
                        cell_base_bc <= cell_base_bc + (bc_dx_i << 8);
                        cell_base_ca <= cell_base_ca + (ca_dx_i << 8);
                        cell_base_un <= cell_base_un + (un_dx_i << 8);
                        cell_base_vn <= cell_base_vn + (vn_dx_i << 8);
                        cell_base_iw <= cell_base_iw + (iw_dx_i << 8);
                    end
                end
            end
        end
    end

    logic signed [63:0] cell_ab;
    logic signed [63:0] cell_bc;
    logic signed [63:0] cell_ca;
    logic signed [63:0] cell_un;
    logic signed [63:0] cell_vn;
    logic signed [63:0] cell_iw;

    assign cell_ab = ab_topleft_i + 64'(cell_base_ab);
    assign cell_bc = bc_topleft_i + 64'(cell_base_bc);
    assign cell_ca = ca_topleft_i + 64'(cell_base_ca);
    assign cell_un = un_topleft_i + 64'(cell_base_un);
    assign cell_vn = vn_topleft_i + 64'(cell_base_vn);
    assign cell_iw = iw_topleft_i + 64'(cell_base_iw);

    logic signed [63:0] pix_ab [31:0];
    logic signed [63:0] pix_bc [31:0];
    logic signed [63:0] pix_ca [31:0];
    logic signed [63:0] pix_un [31:0];
    logic signed [63:0] pix_vn [31:0];
    logic signed [63:0] pix_iw [31:0];

    logic [31:0] in_triangle;

    generate
        for (genvar i = 0; i < 32; i++) begin : gen_pix_attribs
            assign pix_ab[i] = cell_ab + 64'(pix_ddx_ab[i]);
            assign pix_bc[i] = cell_bc + 64'(pix_ddx_bc[i]);
            assign pix_ca[i] = cell_ca + 64'(pix_ddx_ca[i]);
            assign pix_un[i] = cell_un + 64'(pix_ddx_un[i]);
            assign pix_vn[i] = cell_vn + 64'(pix_ddx_vn[i]);
            assign pix_iw[i] = cell_iw + 64'(pix_ddx_iw[i]);

            assign in_triangle[i] = !pix_ab[i][63] && !pix_bc[i][63] && !pix_ca[i][63];
        end : gen_pix_attribs
    endgenerate

    /* Write output generation */

    assign pixblk_mask_o  = in_triangle;
    assign pixblk_cx_o    = seg_x_q[5:0];
    assign pixblk_cy_o    = seg_y_q[10:0];
    assign pixblk_valid_o = |in_triangle && state_q == BUSY;

endmodule
