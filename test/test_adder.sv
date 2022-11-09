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
    adder DUT_ADDER(
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

        .x_greater_i(x_greater_o),
        .exp_shift_i(exp_shift_o),

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
            $fatal(1, "Incorrect sum/difference");
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
                result = 32'h7f800000;
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

        $display("Case A: Sum does not require normalization");

        // 1.5 + 2048.006348 = 2049.506348
        perform_arithmetic('h3fc00000, 'h4500001a, 'h4500181a);

        // 209102.0123408 + 3.00000011676e-16 = 209102.0123408
        perform_arithmetic('h484c3381, 'h25acf030, 'h484c3381);

        // -8092.000425 - 0.00000040523 = -8092.0004254052
        perform_arithmetic('hc5fce001, 'h34d98e63, 'hc5fce001);

        // -243.001999 - 9.6 = -252.601990
        perform_arithmetic('hc3730083, 'hc119999a, 'hc37c9a1c);

        // Normalization //////////////////////////////////////////////////////

        $display("Case B: Sum requires normalization");

        // 0.5 - 0.4375 = 0.0625
        perform_arithmetic('h3f000000, 'hbee00000, 'h3d800000);

        // 999.98999 + 0.01 = 999.999939
        perform_arithmetic('h4479ff5c, 'h3c23d70a, 'h4479ffff);

        // 150.0924 - 200 = -49.9076
        perform_arithmetic('h431617a8, 'hc3480000, 'hc247a160);

        // 46.02 - 39.8034 = 6.2166
        perform_arithmetic('h4238147b, 'hc21f36ae, 'h40c6ee68);

        // 0.09025 + 0.91006 = 1.00031
        perform_arithmetic('h3db8d4fe, 'h3f68f9b1, 'h3f800a28);

        // 98.0125 + 12.0125 = 110.025
        perform_arithmetic('h42c40666, 'h41403333, 'h42dc0ccc);

        // Zero operand ///////////////////////////////////////////////////////

        $display("Case C: Operand is zero");

        // 209102.0123408 + 0.0 = 209102.0123408
        perform_arithmetic('h484c3381, 'h00000000, 'h484c3381);

        // 999.98999 - 0.0 = 999.98999
        perform_arithmetic('h4479ff5c, 'h80000000, 'h4479ff5c);

        // Infinity ///////////////////////////////////////////////////////////

        $display("Case D: Operand is infinite and sum is infinte");

        // inf + x = inf
        perform_arithmetic('h7f800000, 'h4479ff5c, 'h7f800000);

        // x + inf = inf
        perform_arithmetic('h4479ff5c, 'h7f800000, 'h7f800000);

        // -inf + x = -inf
        perform_arithmetic('hff800000, 'h4479ff5c, 'hff800000);

        // inf - x = inf
        perform_arithmetic('h7f800000, 'hc21f36ae, 'h7f800000);

        // x - inf = -inf
        perform_arithmetic('h4479ff5c, 'hff800000, 'hff800000);

        // -inf - x = -inf
        perform_arithmetic('hff800000, 'hc21f36ae, 'hff800000);

        // Invalid operand ////////////////////////////////////////////////////

        $display("Case E: Invalid operation exception");

        // inf + inf
        perform_exception('h7f800000, 'h7f800000, 0);

        // inf - inf
        perform_exception('h7f800000, 'hff800000, 0);

        // x + NaN
        perform_exception('h3db8d4fe, 'h7fffffff, 0);

        // x - NaN
        perform_exception('h3db8d4fe, 'hffffffff, 0);

        // NaN + NaN
        perform_exception('h7fffffff, 'h7fffffff, 0);

        // NaN - NaN
        perform_exception('h7fffffff, 'hffffffff, 0);

        // NaN + inf
        perform_exception('h7fffffff, 'h7f800000, 0);

        // Overflow ///////////////////////////////////////////////////////////

        $display("Case F: Overflow exception");

        // 3e38 + 6e37 = inf
        perform_exception('h7f61b1e6, 'h7e348e52, 1);

        // 3.1804e38 + 9.0125e37 = inf
        perform_exception('h7f6f4447, 'h7e879ae3, 1);

        // 3.40e38 + 1e37 = inf
        perform_exception('h7f7fffff, 'h7cf0bdc2, 1);

        $display("@@@ PASSED");
        $finish;
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, test_adder);
    end

endmodule
