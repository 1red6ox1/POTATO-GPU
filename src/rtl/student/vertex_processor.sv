// SPDX-License-Identifier: SHL-2.1
// SPDX-FileCopyrightText: 2026 RVLab Contributors

module vertex_processor #(
    parameter int DATA_WIDTH = 32,
    parameter int OUT_WIDTH  = DATA_WIDTH,

    // Vector TL-UL byte address layout:
    //   a_address[ 1:0] = 2'b00
    //   a_address[ 3:2] = X/Y/Z/W lane ID
    //   a_address[ 5:4] = vertex ID
    //   a_address[15:6] = triangle ID
    //   a_address[31:16] = 16'b0
    //
    // Each lane has its own DPRAM, so the DPRAM address is the compact
    // {triangle_id, vertex_id} part decoded from the vector TL-UL address.
    parameter int                         TRI_ID_WIDTH = 10,
    parameter int                         VTX_ID_WIDTH = 2
) (
    input  logic                          clk_i,
    input  logic                          rst_ni,
         
    input  tlul_pkg::tl_h2d_t             tl_cfg_i,
    output tlul_pkg::tl_d2h_t             tl_cfg_o,
         
    input  tlul_pkg::tl_h2d_t             tl_vec_i,
    output tlul_pkg::tl_d2h_t             tl_vec_o,


    // Output vector stream. Stored vectors are launched into matmul and held
    // until accepted on this downstream interface.
    output logic                          out_valid_o,
    input  logic                          out_ready_i,
    output logic [TRI_ID_WIDTH-1:0]       out_id_o,
    output logic signed [OUT_WIDTH-1:0]   out_vec_o [3:0]
);

    import vertex_processor_reg_pkg::*;

    typedef logic signed [DATA_WIDTH-1:0] data_t;

    localparam int                        ADDR_WIDTH  = TRI_ID_WIDTH + VTX_ID_WIDTH;
    localparam int                        RAM_DEPTH   = 1 << ADDR_WIDTH;
    localparam int                        VEC_SRAM_AW = ADDR_WIDTH + 2;
    localparam int                        CFG_SEL_BIT = 6;

    // Register block control and split TL-UL configuration ports.
    vertex_processor_reg2hw_t             reg2hw;
    tlul_pkg::tl_h2d_t                    tl_matmul_cfg_i;
    tlul_pkg::tl_d2h_t                    tl_matmul_cfg_o;
    tlul_pkg::tl_h2d_t                    tl_vertex_cfg_i;
    tlul_pkg::tl_d2h_t                    tl_vertex_cfg_o;
    logic                                 cfg_select_vertex;

    // Persistent scene bounds and current render position.
    logic [TRI_ID_WIDTH-1:0]              launch_triangle_q;
    logic [VTX_ID_WIDTH-1:0]              launch_vertex_q;
    logic [TRI_ID_WIDTH-1:0]              last_stored_triangle_q;
    logic                                 stored_triangle_valid_q;
    logic                                 render_enabled_q;

    // Pipeline state that aligns synchronous DPRAM data with matmul metadata.
    data_t                                matmul_vec [3:0];
    logic                                 read_valid_q;
    logic                                 read_first_vertex_q;
    logic [TRI_ID_WIDTH-1:0]              read_id_q;

    // Render, configuration, and matmul handshake signals.
    logic                                 read_fire;
    logic                                 matmul_cfg_write_accept;
    logic                                 matmul_ready;
    logic                                 start_render;

    // TL-UL vector-memory request decoded by the SRAM adapter.
    logic                                 vec_req;
    logic                                 vec_we;
    logic [VEC_SRAM_AW-1:0]               vec_sram_addr;
    logic [DATA_WIDTH-1:0]                vec_wdata;
    logic [DATA_WIDTH-1:0]                vec_wmask;

    // State and lane data used to return synchronous vector-memory reads.
    logic [DATA_WIDTH-1:0]                vec_rdata;
    logic                                 vec_read_pending_q;
    logic [1:0]                           vec_read_lane_q;
    data_t                                dpram_rw_data_out [3:0];

    // vec_sram_addr is already word-addressed by tlul_adapter_sram, so
    // vec_sram_addr[1:0] corresponds to TL-UL byte address bits [3:2].
    assign cfg_select_vertex = tl_cfg_i.a_address[CFG_SEL_BIT];
    assign read_fire = matmul_ready && render_enabled_q && stored_triangle_valid_q;
    assign matmul_cfg_write_accept = tl_matmul_cfg_i.a_valid && tl_matmul_cfg_o.a_ready &&
        (tl_matmul_cfg_i.a_opcode inside {tlul_pkg::PutFullData,tlul_pkg::PutPartialData});
    assign start_render = reg2hw.start_render.qe && reg2hw.start_render.q;

    always_comb begin
        tl_matmul_cfg_i = tl_cfg_i;
        tl_vertex_cfg_i = tl_cfg_i;

        tl_matmul_cfg_i.a_valid = tl_cfg_i.a_valid && !cfg_select_vertex;
        tl_vertex_cfg_i.a_valid = tl_cfg_i.a_valid && cfg_select_vertex;

        tl_cfg_o = tl_matmul_cfg_o;
        if (tl_vertex_cfg_o.d_valid) begin
            tl_cfg_o = tl_vertex_cfg_o;
        end

        tl_cfg_o.a_ready = cfg_select_vertex ? tl_vertex_cfg_o.a_ready : tl_matmul_cfg_o.a_ready;
    end

    vertex_processor_reg_top u_reg_top (
        .clk_i,
        .rst_ni,
        .tl_i     (tl_vertex_cfg_i),
        .tl_o     (tl_vertex_cfg_o),
        .reg2hw   (reg2hw),
        .devmode_i(1'b1)
    );

    tlul_adapter_sram #(
        .SramDw(DATA_WIDTH),
        .SramAw(VEC_SRAM_AW),
        .Outstanding(1),
        .ByteAccess(1),
        .ErrOnWrite(0),
        .ErrOnRead(0)
    ) u_tlul_adapter_sram_vec (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .tl_i(tl_vec_i),
        .tl_o(tl_vec_o),
        .req_o(vec_req),
        .gnt_i(1'b1),
        .we_o(vec_we),
        .addr_o(vec_sram_addr),
        .wdata_o(vec_wdata),
        .wmask_o(vec_wmask),
        .rdata_i(vec_rdata),
        .rvalid_i(vec_read_pending_q),
        .rerror_i(2'b00)
    );

    for (genvar lane = 0; lane < 4; lane = lane + 1) begin : gen_dpram_lanes
        dpram #(
            .DATA_WIDTH(DATA_WIDTH),
            .DEPTH     (RAM_DEPTH),
            .ADDR_WIDTH(ADDR_WIDTH)
        ) u_dpram_lane (
            .clk_i    (clk_i),
            .rw_addr_i({vec_sram_addr[VEC_SRAM_AW-1:4], vec_sram_addr[3:2]}),
            .rw_en_i  (vec_req && (vec_sram_addr[1:0] == lane[1:0])),
            .rw_we_i  (vec_req && vec_we && (vec_sram_addr[1:0] == lane[1:0])),
            .rw_data_i(data_t'(vec_wdata & vec_wmask)),
            .rw_data_o(dpram_rw_data_out[lane]),
            .r_addr_i ({launch_triangle_q, launch_vertex_q}),
            .r_en_i   (read_fire),
            .r_data_o (matmul_vec[lane])
        );
    end

    matmul #(
        .ID_WIDTH(TRI_ID_WIDTH)
    ) u_matmul (
        .clk_i    (clk_i),
        .rst_ni   (rst_ni),
        .tl_ctrl_i(tl_matmul_cfg_i),
        .tl_ctrl_o(tl_matmul_cfg_o),
        .data_i   (matmul_vec),
        .data_o   (out_vec_o),
        .valid_i  (read_valid_q && read_first_vertex_q),
        .id_i     (read_id_q),
        .ready_o  (matmul_ready),
        .valid_o  (out_valid_o),
        .id_o     (out_id_o),
        .ready_i  (out_ready_i)
    );

    assign vec_rdata = dpram_rw_data_out[vec_read_lane_q];

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            launch_triangle_q <= '0;
            launch_vertex_q <= '0;
            last_stored_triangle_q <= '0;
            stored_triangle_valid_q <= 1'b0;
            render_enabled_q <= 1'b0;
            read_valid_q <= 1'b0;
            read_first_vertex_q <= 1'b0;
            read_id_q <= '0;
            vec_read_pending_q <= 1'b0;
            vec_read_lane_q <= '0;
        end else begin
            vec_read_pending_q <= vec_req && !vec_we;
            if (vec_req && !vec_we) begin
                vec_read_lane_q <= vec_sram_addr[1:0];
            end

            if (reg2hw.triangle_count.qe) begin
                last_stored_triangle_q <= TRI_ID_WIDTH'(reg2hw.triangle_count.q);
                stored_triangle_valid_q <= 1'b1;
                if (launch_triangle_q > TRI_ID_WIDTH'(reg2hw.triangle_count.q)) begin
                    launch_triangle_q <= '0;
                    launch_vertex_q <= '0;
                    read_valid_q <= 1'b0;
                    read_first_vertex_q <= 1'b0;
                    read_id_q <= '0;
                end
            end

            if (start_render) begin
                launch_triangle_q <= '0;
                launch_vertex_q <= '0;
                render_enabled_q <= 1'b1;
                read_valid_q <= 1'b0;
                read_first_vertex_q <= 1'b0;
                read_id_q <= '0;
            end else if (matmul_cfg_write_accept) begin
                launch_triangle_q <= '0;
                launch_vertex_q <= '0;
                render_enabled_q <= 1'b0;
                read_valid_q <= 1'b0;
                read_first_vertex_q <= 1'b0;
                read_id_q <= '0;
            end else begin
                if (matmul_ready) begin
                    read_valid_q <= read_fire;
                    if (read_fire) begin
                        read_first_vertex_q <= (launch_vertex_q == '0);
                        read_id_q <= launch_triangle_q;
                    end
                end

                if (read_fire) begin
                    if (launch_vertex_q == 2'd2) begin
                        launch_vertex_q <= '0;
                        if (launch_triangle_q == last_stored_triangle_q) begin
                            launch_triangle_q <= '0;
                            render_enabled_q <= 1'b0;
                        end else begin
                            launch_triangle_q <= launch_triangle_q + 1'b1;
                        end
                    end else begin
                        launch_vertex_q <= launch_vertex_q + 1'b1;
                    end
                end
            end
        end
    end

endmodule
