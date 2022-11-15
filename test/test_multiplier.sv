`timescale 1ns/1ps

module test_multiplier;
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

    // Exponent metadata (UNUSED)
    logic x_greater_o;
    logic [7:0] exp_shift_o;

    // Infinity/NaN flags
    logic x_infinity_o;
    logic y_infinity_o;
    logic x_nan_o;
    logic y_nan_o;

    // Control signals
    logic rst_i;
    logic clk_i;
    logic data_valid_i;
    logic data_valid_o;

    // Results
    logic [31:0] z_o;
    logic except_invalid_operation_o;
    logic except_overflow_o;

    // Connect modules
    operands DUT_OPERANDS(.*);
    multiplier DUT_MULTPLIER(
        .rst_i,
        .clk_i,
        .data_valid_i,
        .data_valid_o,

        .x_sign_i(x_sign_o),
        .x_exp_i(x_exp_o),
        .x_frac_i(x_frac_o),

        .y_sign_i(y_sign_o),
        .y_exp_i(y_exp_o),
        .y_frac_i(y_frac_o),

        .x_infinity_i(x_infinity_o),
        .y_infinity_i(y_infinity_o),
        .x_nan_i(x_nan_o),
        .y_nan_i(y_nan_o),

        .z_o,
        .except_invalid_operation_o,
        .except_overflow_o
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

        while (!data_valid_o)
            @(posedge clk_i);

        @(posedge clk_i);

        assert (z_o === z) else
            $fatal(1, "Incorrect prodcut");
    endtask

    task perform_exception;
        input [31:0] x;
        input [31:0] y;
        input integer operand;

        logic [31:0] result;
        logic except_invalid_operation;
        logic except_overflow;

        result = 'hx;
        except_invalid_operation = 'h0;
        except_overflow = 'h0;

        case(operand)
            0: begin
                result = 'h7fffffff;
                except_invalid_operation = 'h1;
            end

            1: begin
                result = (x[31] ^ y[31]) ? 32'hff800000 : 32'h7f800000;
                except_overflow = 'h1;
            end
        endcase

        perform_arithmetic(x, y, result);

        assert (except_invalid_operation_o === except_invalid_operation) else
            $fatal(1, "Incorrect flag for invalid operation");

        assert (except_overflow_o === except_overflow) else
            $fatal(1, "Incorrect flag for overflow");
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

        // No normalization ///////////////////////////////////////////////////

        $display("Case A: Legal operands");

        // 1.5 * 2048.006348 = 3072.009522
        perform_arithmetic('h3fc00000, 'h4500001a, 'h45400027);

        // 209102.0123408 * 3.00000011676e-16 = 6.273060614E-11
        perform_arithmetic('h484c3381, 'h25acf030, 'h2e89f231);

        // -8092.000425 * 0.00000040523 = 0.003279121332
        perform_arithmetic('hc5fce001, 'h34d98e63, 'hbb56e686);

        // -243.001999 * -9.6 = 2332.8191904
        perform_arithmetic('hc3730083, 'hc119999a, 'h4511cd1b);

        // 0.5 * -0.4375 = -0.21875
        perform_arithmetic('h3f000000, 'hbee00000, 'hbe600000);

        // 999.98999 * 0.01 = 9.9998999
        perform_arithmetic('h4479ff5c, 'h3c23d70a, 'h411fff96);

        // 150.0924 * -200 = -30018.48
        perform_arithmetic('h431617a8, 'hc3480000, 'hc6ea84f6);

        // 46.02 * -39.8034 = -1831.752468
        perform_arithmetic('h4238147b, 'hc21f36ae, 'hc4e4f813);

        // 0.09025 * 0.91006 = 0.082132915
        perform_arithmetic('h3db8d4fe, 'h3f68f9b1, 'h3da8354d);

        // 98.0125 * 12.0125 = 1177.37515625
        perform_arithmetic('h42c40666, 'h41403333, 'h44932c00);

        // Zero operand ///////////////////////////////////////////////////////

        $display("Case C: Operand is zero");

        // 209102.0123408 + 0.0 = +0.0
        perform_arithmetic('h484c3381, 'h00000000, 'h00000000);

        // 999.98999 * -0.0 = -0.0
        perform_arithmetic('h4479ff5c, 'h80000000, 'h80000000);

        // -16.4 * -0.0 = 0.0
        perform_arithmetic('h41833333, 'h80000000, 'h80000000);

        // Infinity ///////////////////////////////////////////////////////////

        $display("Case D: Valid infinite operands");

        // x * inf = inf
        perform_arithmetic('h7f800000, 'h7f800000, 'h7f800000);

        // -inf * x = -inf
        perform_arithmetic('hff800000, 'h4479ff5c, 'hff800000);

        // inf * inf = inf
        perform_arithmetic('h7f800000, 'h7f800000, 'h7f800000);

        // inf * -inf = -inf
        perform_arithmetic('h7f800000, 'hff800000, 'hff800000);

        // Invalid operand ////////////////////////////////////////////////////

        $display("Case E: Invalid operation exception");

        // inf * 0.0
        perform_exception('h7f800000, 'h00000000, 0);

        // -0.0 * inf
        perform_exception('h80000000, 'h7f800000, 0);

        // x * NaN
        perform_exception('h3db8d4fe, 'h7fffffff, 0);

        // x * -NaN
        perform_exception('h3db8d4fe, 'hffffffff, 0);

        // NaN * NaN
        perform_exception('h7fffffff, 'h7fffffff, 0);

        // NaN * inf
        perform_exception('h7fffffff, 'h7f800000, 0);

        // Overflow ///////////////////////////////////////////////////////////

        $display("Case F: Overflow exception");
        
        // 3e38 * 6e37 = inf
        perform_exception('h7f61b1e6, 'h7e348e52, 1);

        // -3.1804e38 * -9.0125e37 = inf
        perform_exception('hff6f4447, 'hfe879ae3, 1);

        // 3.40e38 * -1e37 = inf
        perform_exception('h7f7fffff, 'hfcf0bdc2, 1);

        $display("@@@ PASSED");
        $finish;
    end

    initial begin
        $dumpfile("build/test_multiplier.vcd");
        $dumpvars(0, test_multiplier);
    end

endmodule
