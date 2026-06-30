module dpram #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH      = 512,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
) (
    input  logic                          clk,

    // Port A: read/write port
    input  logic [ADDR_WIDTH-1:0]         rw_addr,
    input  logic                          rw_en,
    input  logic                          rw_we,
    input  logic signed [DATA_WIDTH-1:0]  rw_data_in,
    output logic signed [DATA_WIDTH-1:0]  rw_data_out,

    // Port B: read-only port
    input  logic [ADDR_WIDTH-1:0]         r_addr,
    input  logic                          r_en,
    output logic signed [DATA_WIDTH-1:0]  r_data_out
);

    (* ram_style = "block" *) logic signed [DATA_WIDTH-1:0] ram [DEPTH-1:0];

    always_ff @(posedge clk) begin
        if (rw_en) begin
            if (rw_we) begin
                ram[rw_addr] <= rw_data_in;
                rw_data_out  <= rw_data_in;
            end else begin
                rw_data_out  <= ram[rw_addr];
            end
        end

        if (r_en) begin
            r_data_out <= ram[r_addr];
        end
    end

endmodule
