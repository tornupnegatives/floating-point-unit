`timescale 1ns/1ps

module test_operands;
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

    // Connect module
    operands DUT(.*);

    task full_parse;
        input [31:0] x;
        input [31:0] y;

        logic x_sign;
        logic [7:0] x_exp;
        logic [22:0] x_frac;

        logic y_sign;
        logic [7:0] y_exp;
        logic [22:0] y_frac;

        logic [31:0] exp_shift;

        logic infinity;
        logic nan;

        // Display operands
        $display("X=%x\tY=%x", x, y);

        // Operand construction
        x_sign = x[31];
        x_exp = x[30:23];
        x_frac = x[22:0];

        y_sign = y[31];
        y_exp = y[30:23];
        y_frac = y[22:0];

        // Error flags
        infinity = (x_frac === 'hff && x_frac === 'h0) || (y_frac === 'hff && y_frac === 'h0);
        nan = (x_frac == 'hff && x_frac !== 'h0) || (y_frac == 'hff && y_frac !== 'h0);

        exp_shift = (x_exp > y_exp) ? (x_exp - y_exp) : (y_exp - x_exp);

        // DUT operands
        x_i = x;
        y_i = y;

        #5;

        // Check decomposition
        assert(x_sign_o === x_sign) else
            $fatal(1, "Incorrect sign bit for x\nExpected=%b, Actual=%b", x_sign, x_sign_o);

        assert(y_sign_o === y_sign) else
            $fatal(1, "Incorrect sign bit for y\nExpected=%b, Actual=%b", y_sign, y_sign_o);

        assert(x_exp_o === x_exp) else
            $fatal(1, "Incorrect exponent for x\nExpected=%x, Actual=%x", x_exp, x_exp_o);

        assert(y_exp_o === y_exp) else
            $fatal(1, "Incorrect exponent for y\nExpected=%x, Actual=%x", y_exp, y_exp_o);

        assert(x_frac_o === x_frac) else
            $fatal(1, "Incorrect fraction for x\nExpected=%x, Actual=%x", x_frac, x_frac_o);

        assert(y_frac_o === y_frac) else
            $fatal(1, "Incorrect fraction to y\nExpected=%x, Actual=%x", y_frac, y_frac_o);

        // Check exponent metadata
        assert((x_exp > y_exp) ? x_greater_o : ~x_greater_o) else
            $fatal(1, "Incorrect exponent comparison");

        assert(exp_shift_o === exp_shift) else
            $fatal(1, "Incorrect exponent shift\nExpected=%x, Actual=%x", exp_shift, exp_shift_o);
        
        // Check error flags
        if (x_exp === 'hff) begin
            assert(x_frac === 'h0 ? infinity_o : nan_o) else
                $fatal(1, "Incorrect error flags for x\tExpected=(inf=%h, NaN=%h), Actual=(inf=%h, NaN=%h)", infinity, nan, infinity_o, nan_o);
        end

        if (y_exp == 'hff) begin
            assert(y_frac === 'h0 ? infinity_o : nan_o) else
                $fatal(1, "Incorrect error flags for y\tExpected=(inf=%h, NaN=%h), Actual=(inf=%h, NaN=%h)", infinity, nan, infinity_o, nan_o);
        end

        #5;

    endtask

    initial begin
        $display("Testing operand parser");

        // Prepare DUT
        x_i = 'h0;
        y_i = 'h0;

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

        $display("@@@ PASSED");
        $finish;
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end

endmodule
