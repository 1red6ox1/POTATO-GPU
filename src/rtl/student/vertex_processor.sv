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
    parameter int                         VTX_ID_WIDTH = 2,
    parameter int                         OUT_ID_WIDTH = TRI_ID_WIDTH + 1
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
    output logic [OUT_ID_WIDTH-1:0]       out_id_o,
    output logic signed [OUT_WIDTH-1:0]   out_vec_o [3:0]
);

    import vertex_processor_reg_pkg::*;

    typedef logic signed [DATA_WIDTH-1:0] data_t;

    localparam int                        ADDR_WIDTH  = TRI_ID_WIDTH + VTX_ID_WIDTH;
    localparam int                        RAM_DEPTH   = 1 << ADDR_WIDTH;
    localparam int                        VEC_SRAM_AW = ADDR_WIDTH + 2;
    localparam int                        CFG_SEL_BIT = 6;
    localparam logic [OUT_ID_WIDTH-1:0]   COMPLETION_TRIANGLE_ID = '1;
    localparam data_t                     DUMMY_X_STEP = DATA_WIDTH'(32'sh0000_0100);
    localparam data_t                     DUMMY_Z      = DATA_WIDTH'(32'sh0001_0000);
    localparam data_t                     DUMMY_W      = DATA_WIDTH'(32'sh0001_0000);

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
    logic                                 matmul_out_valid;
    logic                                 matmul_out_ready;
    logic [TRI_ID_WIDTH-1:0]              matmul_out_id;
    data_t                                matmul_out_vec [3:0];
    logic                                 start_render;

    // A fixed completion triangle is appended after the final transformed
    // triangle. It bypasses the programmable matrix so it cannot be moved,
    // flattened, or placed behind the camera by software configuration.
    logic                                 final_output_active_q;
    logic [1:0]                           final_output_vertex_q;
    logic                                 dummy_active_q;
    logic [1:0]                           dummy_vertex_q;

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
    assign matmul_out_ready = out_ready_i && !dummy_active_q;

    always_comb begin
        out_valid_o = matmul_out_valid;
        out_id_o = OUT_ID_WIDTH'(matmul_out_id);
        for (int lane = 0; lane < 4; lane = lane + 1) begin
            out_vec_o[lane] = matmul_out_vec[lane];
        end

        if (dummy_active_q) begin
            // The collector uses valid on the first vertex and then consumes
            // the following two vertices as consecutive stream beats.
            out_valid_o = dummy_vertex_q == '0;
            out_id_o = COMPLETION_TRIANGLE_ID;
            out_vec_o[0] = '0;
            out_vec_o[1] = '0;
            out_vec_o[2] = DUMMY_Z;
            out_vec_o[3] = DUMMY_W;

            unique case (dummy_vertex_q)
                2'd1: out_vec_o[0] = DUMMY_X_STEP;
                2'd2: out_vec_o[1] = -DUMMY_X_STEP;
                default: ;
            endcase
        end
    end

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
        .data_o   (matmul_out_vec),
        .valid_i  (read_valid_q && read_first_vertex_q),
        .id_i     (read_id_q),
        .ready_o  (matmul_ready),
        .valid_o  (matmul_out_valid),
        .id_o     (matmul_out_id),
        .ready_i  (matmul_out_ready)
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
            final_output_active_q <= 1'b0;
            final_output_vertex_q <= '0;
            dummy_active_q <= 1'b0;
            dummy_vertex_q <= '0;
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
                final_output_active_q <= 1'b0;
                final_output_vertex_q <= '0;
                dummy_active_q <= 1'b0;
                dummy_vertex_q <= '0;
            end else if (matmul_cfg_write_accept) begin
                launch_triangle_q <= '0;
                launch_vertex_q <= '0;
                render_enabled_q <= 1'b0;
                read_valid_q <= 1'b0;
                read_first_vertex_q <= 1'b0;
                read_id_q <= '0;
                final_output_active_q <= 1'b0;
                final_output_vertex_q <= '0;
                dummy_active_q <= 1'b0;
                dummy_vertex_q <= '0;
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

                if (dummy_active_q) begin
                    if (out_ready_i) begin
                        if (dummy_vertex_q == 2'd2) begin
                            dummy_active_q <= 1'b0;
                            dummy_vertex_q <= '0;
                        end else begin
                            dummy_vertex_q <= dummy_vertex_q + 1'b1;
                        end
                    end
                end else if (matmul_out_ready) begin
                    if (matmul_out_valid && matmul_out_id == last_stored_triangle_q) begin
                        final_output_active_q <= 1'b1;
                        final_output_vertex_q <= 2'd1;
                    end else if (final_output_active_q) begin
                        if (final_output_vertex_q == 2'd2) begin
                            final_output_active_q <= 1'b0;
                            final_output_vertex_q <= '0;
                            dummy_active_q <= 1'b1;
                            dummy_vertex_q <= '0;
                        end else begin
                            final_output_vertex_q <= final_output_vertex_q + 1'b1;
                        end
                    end
                end
            end
        end
    end

endmodule
