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

    localparam int VEC_SRAM_AW = ADDR_WIDTH + 2;
    localparam int MATMUL_ID_WIDTH = 16;

    data_t matmul_vec   [3:0];
    out_t  matmul_out   [3:0];

    logic [ADDR_WIDTH-1:0] ram_r_addr;
    logic [TRI_ID_WIDTH-1:0] launch_triangle_q;
    logic [VTX_ID_WIDTH-1:0] launch_vertex_q;
    // Despite the name, this stores the last completed triangle ID.
    logic [TRI_ID_WIDTH-1:0] stored_triangle_count_q;
    logic stored_triangle_valid_q;
    logic read_valid_q;
    logic read_first_vertex_q;
    logic [MATMUL_ID_WIDTH-1:0] read_id_q;

    logic vec_gnt;
    logic vec_accept;
    logic [TRI_ID_WIDTH-1:0] vec_triangle_id;
    logic triangle_write_complete;
    logic launch_last_vertex;
    logic launch_last_triangle;
    logic read_fire;
    logic cfg_write_accept;
    logic ram_r_en;
    logic matmul_in_valid;
    logic matmul_out_valid;
    logic matmul_ready;
    logic [MATMUL_ID_WIDTH-1:0] matmul_id_out;

    logic vec_req;
    logic vec_we;
    logic [VEC_SRAM_AW-1:0] vec_sram_addr;
    logic [DATA_WIDTH-1:0] vec_wdata;
    logic [DATA_WIDTH-1:0] vec_wmask;
    logic [DATA_WIDTH-1:0] vec_rdata;
    logic vec_rvalid;
    logic [1:0] vec_rerror;
    logic vec_read_pending_q;
    logic [1:0] vec_read_lane_q;

    data_t dpram_rw_data_out [3:0];
    tlul_pkg::tl_d2h_t tl_cfg_matmul_o;

    // vec_sram_addr is already word-addressed by tlul_adapter_sram, so
    // vec_sram_addr[1:0] corresponds to TL-UL byte address bits [3:2].
    assign triangle_write_complete = vec_req && vec_we &&
                                      (vec_sram_addr[1:0] == 2'd3) &&
                                      (vec_sram_addr[3:2] == 2'd2);
    assign vec_triangle_id = vec_sram_addr[VEC_SRAM_AW-1:4];
    assign launch_last_vertex = (launch_vertex_q == 2'd2);
    assign launch_last_triangle = (launch_triangle_q == stored_triangle_count_q);
    assign read_fire = matmul_ready && stored_triangle_valid_q;
    assign vec_gnt = 1'b1;
    assign vec_accept = vec_req && vec_gnt;
    assign cfg_write_accept = tl_cfg_i.a_valid && tl_cfg_matmul_o.a_ready &&
                              (tl_cfg_i.a_opcode inside {
                                  tlul_pkg::PutFullData,
                                  tlul_pkg::PutPartialData
                              });

    assign tl_cfg_o = tl_cfg_matmul_o;
    assign out_valid_o = matmul_out_valid;
    assign out_id_o    = {{(32-MATMUL_ID_WIDTH){1'b0}}, matmul_id_out};
    assign vec_rvalid = vec_read_pending_q;
    assign vec_rerror = 2'b00;
    assign ram_r_addr = {launch_triangle_q, launch_vertex_q};
    assign ram_r_en = read_fire;
    assign matmul_in_valid = read_valid_q && matmul_ready;

    for (genvar out_idx = 0; out_idx < 4; out_idx = out_idx + 1) begin : gen_out_assign
        assign out_vec_o[out_idx] = matmul_out[out_idx];
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
        .gnt_i(vec_gnt),
        .we_o(vec_we),
        .addr_o(vec_sram_addr),
        .wdata_o(vec_wdata),
        .wmask_o(vec_wmask),
        .rdata_i(vec_rdata),
        .rvalid_i(vec_rvalid),
        .rerror_i(vec_rerror)
    );

    for (genvar lane = 0; lane < 4; lane = lane + 1) begin : gen_dpram_lanes
        dpram #(
            .DATA_WIDTH(DATA_WIDTH),
            .DEPTH     (RAM_DEPTH),
            .ADDR_WIDTH(ADDR_WIDTH)
        ) u_dpram_lane (
            .clk        (clk),
            .rw_addr    ({vec_sram_addr[VEC_SRAM_AW-1:4], vec_sram_addr[3:2]}),
            .rw_en      (vec_accept && (vec_sram_addr[1:0] == lane[1:0])),
            .rw_we      (vec_accept && vec_we && (vec_sram_addr[1:0] == lane[1:0])),
            .rw_data_in (data_t'(vec_wdata & vec_wmask)),
            .rw_data_out(dpram_rw_data_out[lane]),
            .r_addr     (ram_r_addr),
            .r_en       (ram_r_en),
            .r_data_out (matmul_vec[lane])
        );
    end

    matmul #(
        .ID_WIDTH(MATMUL_ID_WIDTH)
    ) u_matmul (
        .clk_i    (clk),
        .rst_ni   (rst_n),
        .tl_ctrl_i(tl_cfg_i),
        .tl_ctrl_o(tl_cfg_matmul_o),
        .data_i   (matmul_vec),
        .data_o   (matmul_out),
        .valid_i  (matmul_in_valid && read_first_vertex_q),
        .id_i     (read_id_q),
        .ready_o  (matmul_ready),
        .valid_o  (matmul_out_valid),
        .id_o     (matmul_id_out),
        .ready_i  (out_ready_i)
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            launch_triangle_q <= '0;
            launch_vertex_q <= '0;
            stored_triangle_count_q <= '0;
            stored_triangle_valid_q <= 1'b0;
            read_valid_q <= 1'b0;
            read_first_vertex_q <= 1'b0;
            read_id_q <= '0;
            vec_read_pending_q <= 1'b0;
            vec_read_lane_q <= '0;
        end else begin
            vec_read_pending_q <= vec_accept && !vec_we;
            if (vec_accept && !vec_we) begin
                vec_read_lane_q <= vec_sram_addr[1:0];
            end

            if (cfg_write_accept) begin
                launch_triangle_q <= '0;
                launch_vertex_q <= '0;
                read_valid_q <= 1'b0;
                read_first_vertex_q <= 1'b0;
                read_id_q <= '0;
            end else begin
                if (matmul_ready) begin
                    read_valid_q <= read_fire;
                    if (read_fire) begin
                        read_first_vertex_q <= (launch_vertex_q == '0);
                        read_id_q <= MATMUL_ID_WIDTH'(launch_triangle_q);
                    end
                end

                if (read_fire) begin
                    if (launch_last_vertex) begin
                        launch_vertex_q <= '0;
                        if (launch_last_triangle) begin
                            launch_triangle_q <= '0;
                        end else begin
                            launch_triangle_q <= launch_triangle_q + 1'b1;
                        end
                    end else begin
                        launch_vertex_q <= launch_vertex_q + 1'b1;
                    end
                end
            end

            if (vec_accept && triangle_write_complete) begin
                stored_triangle_count_q <= vec_triangle_id;
                stored_triangle_valid_q <= 1'b1;
                if (!stored_triangle_valid_q || (launch_triangle_q > vec_triangle_id)) begin
                    launch_triangle_q <= '0;
                    launch_vertex_q <= '0;
                    read_valid_q <= 1'b0;
                    read_first_vertex_q <= 1'b0;
                    read_id_q <= '0;
                end
            end
        end
    end

endmodule
