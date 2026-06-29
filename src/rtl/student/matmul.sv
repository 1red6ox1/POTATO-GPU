module matmul #(
    parameter int DATA_WIDTH = 32,
    parameter int FRAC_WIDTH = 16,
    parameter int OUT_WIDTH  = DATA_WIDTH
) (
    input  logic                              clk,
    input  logic                              rst_n,
    input  logic                              in_valid,
    input  logic signed [DATA_WIDTH-1:0]      mat_A [3:0][3:0],
    input  logic signed [DATA_WIDTH-1:0]      vec_B [3:0],
    output logic                              out_valid,
    output logic signed [OUT_WIDTH-1:0]       mat_C [3:0]
);

    localparam int PROD_WIDTH = DATA_WIDTH * 2;
    localparam int ACC_WIDTH  = PROD_WIDTH + 2;

    logic signed [DATA_WIDTH-1:0] a_reg [3:0][3:0];
    logic signed [DATA_WIDTH-1:0] b_reg [3:0];
    logic signed [PROD_WIDTH-1:0] prod [3:0][3:0];
    logic signed [PROD_WIDTH:0]   sum_lvl1 [3:0][1:0];
    logic signed [ACC_WIDTH-1:0]  sum_lvl2 [3:0];
    logic [3:0] valid_pipe;

    generate
        genvar row;
        genvar col;

        for (row = 0; row < 4; row = row + 1) begin : gen_rows
            for (col = 0; col < 4; col = col + 1) begin : gen_cols
                always_ff @(posedge clk) begin
                    if (!rst_n) begin
                        a_reg[row][col] <= '0;
                        prod[row][col]  <= '0;
                    end else begin
                        if (in_valid) begin
                            a_reg[row][col] <= mat_A[row][col];
                        end

                        prod[row][col] <= a_reg[row][col] * b_reg[col];
                    end
                end
            end
        end

        for (col = 0; col < 4; col = col + 1) begin : gen_vector
            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    b_reg[col] <= '0;
                end else if (in_valid) begin
                    b_reg[col] <= vec_B[col];
                end
            end
        end

        for (row = 0; row < 4; row = row + 1) begin : gen_output
            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    sum_lvl1[row][0] <= '0;
                    sum_lvl1[row][1] <= '0;
                    sum_lvl2[row]    <= '0;
                    mat_C[row]       <= '0;
                end else begin
                    sum_lvl1[row][0] <= prod[row][0] + prod[row][1];
                    sum_lvl1[row][1] <= prod[row][2] + prod[row][3];
                    sum_lvl2[row]    <= sum_lvl1[row][0] + sum_lvl1[row][1];
                    mat_C[row]       <= ((sum_lvl2[row] >>> FRAC_WIDTH) >
                                         $signed({{(ACC_WIDTH-OUT_WIDTH){1'b0}},
                                         {1'b0, {(OUT_WIDTH-1){1'b1}}}})) ?
                                        {1'b0, {(OUT_WIDTH-1){1'b1}}} :
                                        (((sum_lvl2[row] >>> FRAC_WIDTH) <
                                         $signed({{(ACC_WIDTH-OUT_WIDTH){1'b1}},
                                         {1'b1, {(OUT_WIDTH-1){1'b0}}}})) ?
                                        {1'b1, {(OUT_WIDTH-1){1'b0}}} :
                                        sum_lvl2[row][FRAC_WIDTH+:OUT_WIDTH]);
                end
            end
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_pipe <= '0;
            out_valid  <= 1'b0;
        end else begin
            valid_pipe <= {valid_pipe[2:0], in_valid};
            out_valid  <= valid_pipe[3];
        end
    end

endmodule
