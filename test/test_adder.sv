`timescale 1ns/1ps

module test_adder;
    // Operands
    logic [31:0] x_i;
    logic [31:0] y_i;

    // Decomposition
    logic x_sign_o;
    logic y_sign_o;

    logic [7:0] x_exp_o;
    logic [7:0] y_exp_o;

    logic [22:0] x_frac_o;
    logic [22:0] y_frac_o;

    // Exponent metadata
    logic x_greater_o;
    logic [7:0] exp_shift_o;

    // Error flags
    logic infinity_o;
    logic nan_o;

    // Control signals
    logic rst_i;
    logic clk_i;
    logic data_valid_i;
    logic data_ready_o;

    // Results
    logic [31:0] z_o;
    logic z_infinity_o;
    logic z_nan_o;

    // Connect modules
    operands DUT_OPERANDS(.*);
    adder DUT_ADDER(
        .rst_i,
        .clk_i,
        .data_valid_i,
        .data_ready_o,

        .x_sign_i(x_sign_o),
        .x_exp_i(x_exp_o),
        .x_frac_i(x_frac_o),

        .y_sign_i(y_sign_o),
        .y_exp_i(y_exp_o),
        .y_frac_i(y_frac_o),

        .x_greater_i(x_greater_o),
        .exp_shift_i(exp_shift_o),
        .infinity_i(infinity_o),
        .nan_i(nan_o),

        .z_o,
        .z_infinity_o,
        .z_nan_o
    );

    task perform_arithmetic;
        input [31:0] x;
        input [31:0] y;
        input [31:0] z;

        // Display operands
        $display("X=%x\tY=%x", x, y);

        // Place operands on parser
        @(negedge clk_i) begin
            x_i = x;
            y_i = y;
        end

        // Start adder
        @(posedge clk_i) begin
            data_valid_i = 'h1;
        end

        // Wait for adder
        @(posedge clk_i) begin
            data_valid_i = 'h0;
        end

        while (!data_ready_o)
            @(posedge clk_i);

        @(posedge clk_i);

        assert (z_o === z) else
            $fatal(1, "INCORRECT SUM/DIFFERENCE");
    endtask

    always #5 clk_i = ~clk_i;

    initial begin
        $display("Testing operand parser");

        // Prepare DUT
        clk_i = 'h0;
        rst_i = 'h1;
        x_i = 'h0;
        y_i = 'h0;
        data_valid_i = 'h0;

        // Reset DUT
        repeat (16) @ (posedge clk_i);
        rst_i = 'h0;

        // 4.5 + 3.75 = 8.25
        perform_arithmetic('h40900000, 'h40700000, 'h41040000);

        // -9 + 3.375 = -5.0625
        perform_arithmetic('hc1100000, 'h407c0000, 'hc0a20000);

        /*

        // Positive operands
        //
        // 1.5, 2048.006348
        full_parse('h3fc00000, 'h4500001a);
        // 209102.0123408, 3.00000011676e-16
        full_parse('h484c3381, 'h25acf030);

        // Negative operands
        //
        // -8092.000425, -0.00000040523
        full_parse('hc5fce001, 'hb4d98e63);
        // -243.002, -9.6
        full_parse('h3730083, 'hc119999a);

        // Positive-negative operands
        //
        // 0.0125, -102410.5059
        full_parse('h3c4ccccd, 'hc7c80541);
        // -10.2, 400.0069402
        full_parse('hc1233333, 'h43c800e3);

        // Infinity
        //
        // +inf, -0.00125
        full_parse('h7f800000, 'hbaa3d70a);
        // -inf, 2048.0192
        full_parse('hff800000, 'h4500004f);

        // NaN
        //
        // NaN, -6.08
        full_parse('h7fffffff,'hc0c28f5c);
        // 0.0000298, NaN
        full_parse('h37f9fb03, 'h7fffffff);

        // Positive-negative zero
        //
        // +0.0, -0.0
        full_parse('h00000000, 'h80000000);
        // +0.0, 92.6
        full_parse('h00000000, 'h42b93333);
        // -0.0, 0.02104
        full_parse('h80000000, 'h3cac5c14);
        */

        $display("@@@ PASSED");
        $finish;
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, test_adder);
    end

endmodule
