module dpram #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH      = 512,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
) (
    input  logic                          clk_i,

    // Port A: read/write port
    input  logic [ADDR_WIDTH-1:0]         rw_addr_i,
    input  logic                          rw_en_i,
    input  logic                          rw_we_i,
    input  logic signed [DATA_WIDTH-1:0]  rw_data_i,
    output logic signed [DATA_WIDTH-1:0]  rw_data_o,

    // Port B: read-only port
    input  logic [ADDR_WIDTH-1:0]         r_addr_i,
    input  logic                          r_en_i,
    output logic signed [DATA_WIDTH-1:0]  r_data_o
);

    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] ram [DEPTH-1:0] = '{default: '0};

    always_ff @(posedge clk_i) begin
        if (rw_en_i) begin
            if (rw_we_i) begin
                ram[rw_addr_i] <= rw_data_i;
                rw_data_o      <= rw_data_i;
            end else begin
                rw_data_o <= ram[rw_addr_i];
            end
        end

        if (r_en_i) begin
            r_data_o <= ram[r_addr_i];
        end
    end

endmodule
