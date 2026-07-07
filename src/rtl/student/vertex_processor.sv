// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2026 RVLab Contributors

module vertex_processor #(
    parameter int DATA_WIDTH = 32,
    parameter int OUT_WIDTH  = DATA_WIDTH,
    parameter int FIFO_DEPTH = 16,

    // Vector TL-UL byte address layout:
    //   a_address[ 1:0] = 2'b00
    //   a_address[ 3:2] = X/Y/Z/W lane ID
    //   a_address[ 5:4] = vertex ID
    //   a_address[15:6] = triangle ID
    //   a_address[31:16] = 16'b0
    //
    // Each lane has its own DPRAM, so the DPRAM address is the compact
    // {triangle_id, vertex_id} part decoded from the vector TL-UL address.
    parameter int TRI_ID_WIDTH = 10,
    parameter int VTX_ID_WIDTH = 2,
    localparam int ADDR_WIDTH = TRI_ID_WIDTH + VTX_ID_WIDTH,
    localparam int RAM_DEPTH  = 1 << ADDR_WIDTH
) (
    input  logic                         clk,
    input  logic                         rst_n,

    input  tlul_pkg::tl_h2d_t tl_cfg_i,
    output tlul_pkg::tl_d2h_t tl_cfg_o,

    input  tlul_pkg::tl_h2d_t tl_vec_i,
    output tlul_pkg::tl_d2h_t tl_vec_o,


    // Output vector stream. Stored vectors are launched into matmul and held
    // until accepted on this downstream interface.
    output logic                         out_valid_o,
    input  logic                         out_ready_i,
    output logic [31:0]                  out_id_o,
    output logic signed [OUT_WIDTH-1:0]  out_vec_o [3:0]
);

    typedef logic signed [DATA_WIDTH-1:0] data_t;
    typedef logic signed [OUT_WIDTH-1:0]  out_t;

    localparam int FIFO_WIDTH = 32 + ADDR_WIDTH;
    localparam int VEC_SRAM_AW = ADDR_WIDTH + 2;
    localparam int FIFO_ADDR_LSB = 0;
    localparam int FIFO_ADDR_MSB = ADDR_WIDTH - 1;
    localparam int FIFO_ID_LSB   = ADDR_WIDTH;
    localparam int FIFO_ID_MSB   = ADDR_WIDTH + 31;

    typedef enum logic [1:0] {
        StateIdle,
        StateRead,
        StateWaitMatmul
    } state_e;

    state_e state_q, state_d;

    data_t matmul_vec   [3:0];
    logic [31:0] matmul_out   [3:0];
    out_t  out_vec_q    [3:0];

    logic [ADDR_WIDTH-1:0] ram_r_addr_q, ram_r_addr_d;
    logic [ADDR_WIDTH-1:0] pending_addr_q, pending_addr_d;
    logic [31:0] pending_id_q, pending_id_d, write_triangle_id;

    logic [RAM_DEPTH-1:0] addr_pending_q;
    logic [RAM_DEPTH-1:0] addr_pending_d;

    logic fifo_wvalid;
    logic fifo_wready;
    logic [FIFO_WIDTH-1:0] fifo_wdata;
    logic fifo_rvalid;
    logic fifo_rready;
    logic [FIFO_WIDTH-1:0] fifo_rdata;
    logic [$clog2(FIFO_DEPTH+1)-1:0] unused_fifo_depth;

    logic vec_write_enqueue;
    logic start_read;
    logic ram_r_en;
    logic matmul_in_valid;
    logic matmul_out_valid;
    logic [1:0] matmul_valid_pipe_q;

    logic out_buf_valid_q, out_buf_valid_d;
    logic [31:0] out_id_q, out_id_d;
    out_t out_vec_d [3:0];

    logic vec_req;
    logic vec_we;
    logic [VEC_SRAM_AW-1:0] vec_sram_addr;
    logic [DATA_WIDTH-1:0] vec_wdata;
    logic [DATA_WIDTH-1:0] vec_wmask;
    logic [DATA_WIDTH-1:0] vec_rdata;
    logic vec_rvalid;
    logic [1:0] vec_rerror;
    logic [1:0] vec_lane_sel;
    logic [TRI_ID_WIDTH-1:0] vec_triangle_id;
    logic [VTX_ID_WIDTH-1:0] vec_vertex_id;
    logic [ADDR_WIDTH-1:0] vec_addr;
    logic vec_read_pending_q;
    logic [1:0] vec_read_lane_q;

    logic dpram_rw_en [3:0];
    logic dpram_rw_we [3:0];
    logic [ADDR_WIDTH-1:0] dpram_rw_addr [3:0];
    data_t dpram_rw_data_in [3:0];
    data_t dpram_rw_data_out [3:0];

    assign write_triangle_id = {{(32-TRI_ID_WIDTH){1'b0}}, vec_triangle_id};
    assign vec_write_enqueue = vec_req && vec_we && (vec_lane_sel == 2'd3) &&
                               fifo_wready && !addr_pending_q[vec_addr];
    assign fifo_wvalid = vec_write_enqueue;
    assign fifo_wdata  = {write_triangle_id, vec_addr};

    assign out_valid_o = out_buf_valid_q;
    assign out_id_o    = out_id_q;
    assign vec_lane_sel = vec_sram_addr[1:0];
    assign vec_vertex_id = vec_sram_addr[3:2];
    assign vec_triangle_id = vec_sram_addr[VEC_SRAM_AW-1:4];
    assign vec_addr = {vec_triangle_id, vec_vertex_id};
    assign vec_rvalid = vec_read_pending_q;
    assign vec_rerror = 2'b00;
    assign matmul_out_valid = matmul_valid_pipe_q[1];

    for (genvar out_idx = 0; out_idx < 4; out_idx = out_idx + 1) begin : gen_out_assign
        assign out_vec_o[out_idx] = out_vec_q[out_idx];
    end

    tlul_adapter_sram #(
        .SramDw(DATA_WIDTH),
        .SramAw(VEC_SRAM_AW),
        .Outstanding(1),
        .ByteAccess(1),
        .ErrOnWrite(0),
        .ErrOnRead(0)
    ) u_tlul_adapter_sram_vec (
        .clk_i(clk),
        .rst_ni(rst_n),
        .tl_i(tl_vec_i),
        .tl_o(tl_vec_o),
        .req_o(vec_req),
        .gnt_i(1'b1),
        .we_o(vec_we),
        .addr_o(vec_sram_addr),
        .wdata_o(vec_wdata),
        .wmask_o(vec_wmask),
        .rdata_i(vec_rdata),
        .rvalid_i(vec_rvalid),
        .rerror_i(vec_rerror)
    );

    prim_fifo_sync #(
        .Width(FIFO_WIDTH),
        .Pass (1'b0),
        .Depth(FIFO_DEPTH)
    ) u_id_fifo (
        .clk_i (clk),
        .rst_ni(rst_n),
        .clr_i (1'b0),
        .wvalid(fifo_wvalid),
        .wready(fifo_wready),
        .wdata (fifo_wdata),
        .rvalid(fifo_rvalid),
        .rready(fifo_rready),
        .rdata (fifo_rdata),
        .depth (unused_fifo_depth)
    );

    for (genvar lane = 0; lane < 4; lane = lane + 1) begin : gen_dpram_lanes
        assign dpram_rw_en[lane] = vec_req && (vec_lane_sel == lane[1:0]);
        assign dpram_rw_we[lane] = vec_req && vec_we && (vec_lane_sel == lane[1:0]);
        assign dpram_rw_addr[lane] = vec_addr;
        assign dpram_rw_data_in[lane] = data_t'(vec_wdata & vec_wmask);

        dpram #(
            .DATA_WIDTH(DATA_WIDTH),
            .DEPTH     (RAM_DEPTH),
            .ADDR_WIDTH(ADDR_WIDTH)
        ) u_dpram_lane (
            .clk        (clk),
            .rw_addr    (dpram_rw_addr[lane]),
            .rw_en      (dpram_rw_en[lane]),
            .rw_we      (dpram_rw_we[lane]),
            .rw_data_in (dpram_rw_data_in[lane]),
            .rw_data_out(dpram_rw_data_out[lane]),
            .r_addr     (ram_r_addr_d),
            .r_en       (ram_r_en),
            .r_data_out (matmul_vec[lane])
        );
    end

    matmul u_matmul (
        .clk_i    (clk),
        .rst_ni   (rst_n),
        .tl_ctrl_i(tl_cfg_i),
        .tl_ctrl_o(tl_cfg_o),
        .data_i   (matmul_vec),
        .data_o   (matmul_out)
    );

    always_comb begin
        vec_rdata = '0;
        unique case (vec_read_lane_q)
            2'd0: vec_rdata = dpram_rw_data_out[0];
            2'd1: vec_rdata = dpram_rw_data_out[1];
            2'd2: vec_rdata = dpram_rw_data_out[2];
            2'd3: vec_rdata = dpram_rw_data_out[3];
            default: vec_rdata = '0;
        endcase
    end

    always_comb begin
        state_d         = state_q;
        pending_id_d    = pending_id_q;
        pending_addr_d  = pending_addr_q;
        ram_r_addr_d    = ram_r_addr_q;
        fifo_rready     = 1'b0;
        ram_r_en        = 1'b0;
        matmul_in_valid = 1'b0;
        start_read      = 1'b0;

        case (state_q)
            StateIdle: begin
                start_read = fifo_rvalid && out_ready_i && !out_buf_valid_q;
                if (start_read) begin
                    fifo_rready    = 1'b1;
                    ram_r_en       = 1'b1;
                    ram_r_addr_d   = fifo_rdata[FIFO_ADDR_MSB:FIFO_ADDR_LSB];
                    pending_addr_d = fifo_rdata[FIFO_ADDR_MSB:FIFO_ADDR_LSB];
                    pending_id_d   = fifo_rdata[FIFO_ID_MSB:FIFO_ID_LSB];
                    state_d        = StateRead;
                end
            end

            StateRead: begin
                matmul_in_valid = 1'b1;
                state_d         = StateWaitMatmul;
            end

            StateWaitMatmul: begin
                if (matmul_out_valid) begin
                    state_d = StateIdle;
                end
            end

            default: begin
                state_d = StateIdle;
            end
        endcase
    end

    always_comb begin
        out_buf_valid_d = out_buf_valid_q;
        out_id_d        = out_id_q;
        out_vec_d       = out_vec_q;

        if (out_buf_valid_q && out_ready_i) begin
            out_buf_valid_d = 1'b0;
        end

        if (matmul_out_valid) begin
            out_buf_valid_d = 1'b1;
            out_id_d        = pending_id_q;
            for (int lane = 0; lane < 4; lane = lane + 1) begin
                out_vec_d[lane] = out_t'(matmul_out[lane]);
            end
        end
    end

    always_comb begin
        addr_pending_d = addr_pending_q;

        if (matmul_in_valid) begin
            addr_pending_d[pending_addr_q] = 1'b0;
        end

        if (vec_write_enqueue) begin
            addr_pending_d[vec_addr] = 1'b1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q         <= StateIdle;
            pending_id_q    <= '0;
            pending_addr_q  <= '0;
            ram_r_addr_q    <= '0;
            out_buf_valid_q <= 1'b0;
            out_id_q        <= '0;
            matmul_valid_pipe_q <= '0;
            addr_pending_q  <= '0;
            vec_read_pending_q <= 1'b0;
            vec_read_lane_q <= '0;

            for (int row = 0; row < 4; row = row + 1) begin
                out_vec_q[row] <= '0;
            end
        end else begin
            state_q         <= state_d;
            pending_id_q    <= pending_id_d;
            pending_addr_q  <= pending_addr_d;
            ram_r_addr_q    <= ram_r_addr_d;
            out_buf_valid_q <= out_buf_valid_d;
            out_id_q        <= out_id_d;
            matmul_valid_pipe_q <= {matmul_valid_pipe_q[0], matmul_in_valid};
            out_vec_q       <= out_vec_d;
            addr_pending_q  <= addr_pending_d;
            vec_read_pending_q <= vec_req && !vec_we;
            if (vec_req && !vec_we) begin
                vec_read_lane_q <= vec_lane_sel;
            end
        end
    end

endmodule
