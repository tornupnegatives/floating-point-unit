`timescale 1ns/1ps

module test_divider;
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
    divider DUT_DIVIDER(
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

        .x_greater_i(x_greater_o),
        .exp_shift_i(exp_shift_o),

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
            $fatal(1, "Incorrect quotient");
    endtask

    task perform_exception;
        input [31:0] x;
        input [31:0] y;
        input integer operand;

        logic [31:0] result;
        logic except_invalid_operation;
        logic except_overflow;

        localparam DIV_BY_ZERO = 0;
        localparam INVALID_OPERANDS = 1;
        localparam OVERFLOW = 2;

        result = 'hx;
        except_invalid_operation = 'h0;
        except_overflow = 'h0;

        case(operand)
            DIV_BY_ZERO: begin
                result = (x[31] ^ y[31]) ? 32'hff800000 : 32'h7f800000;
                except_invalid_operation = 'h1;
            end

            INVALID_OPERANDS: begin
                result = (x[31] ^ y[31]) ? 'hffffffff : 'h7fffffff;
                except_invalid_operation = 'h1;
            end

            OVERFLOW: begin
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

        // -3.0 / 15.5 = -0.1935483871
        perform_arithmetic('h40866666, 'h404CCCCC, 'h3FA7FFFF);

        // 1.0 / 2.0 = 0.5
        perform_arithmetic('h3f800000, 'h40000000, 'h3effffff);

        // 209102.0123408 / 3.00000011676e-16 = 6.9700668068e20
        perform_arithmetic('h484c3381, 'h25acf030, 'h621723a5);

        // -243.001999 / -9.6 = 25.3127098083
        perform_arithmetic('hc3730083, 'hc119999a, 'h41ca806e);

        // 0.5 * -0.4375 = -1.1428571429
        perform_arithmetic('h3f000000, 'hbee00000, 'hbf924926);

        // 999.98999 / 0.01 = 99998.999
        perform_arithmetic('h4479ff5c, 'h3c23d70a, 'h47c34f80);

        // 150.0924 / -200 = -0.750462
        perform_arithmetic('h431617a8, 'hc3480000, 'hbf401e49);

        // 46.02 / -39.8034 = -1.1561826377
        perform_arithmetic('h4238147b, 'hc21f36ae, 'hbf93fdcb);

        // 0.09025 / 0.91006 = 0.09916928554
        perform_arithmetic('h3db8d4fe, 'h3f68f9b1, 'h3dcb1944);

        // 98.0125 / 12.0125 = 8.1592091571
        perform_arithmetic('h42c40666, 'h41403333, 'h41028c1f);
        
        // Zero numerator /////////////////////////////////////////////////////

        $display("Case C: Numerator is zero");

        // 0.0 / 209102.0123408 = +0.0
        perform_arithmetic(32'h0, 'h484c3381, 32'h0);

        // -0.0 / 999.98999 = -0.0
        perform_arithmetic('h80000000, 'h4479ff5c, 'h80000000);

        // Zero denominator ///////////////////////////////////////////////////

        $display("Case C: Denominator is zero");

        // 209102.0123408 / 0.0
        perform_exception('h484c3381, 32'h0, 0);

        // 999.98999 / -0.0
        perform_exception('h4479ff5c, 'h80000000, 0);

        // inf / 0.0
        perform_exception('h7f800000, 32'h0, 0);

        // -inf / -0.0
        perform_exception('hff800000, 'h80000000, 0);

        // Infinity ///////////////////////////////////////////////////////////

        $display("Case D: Valid infinite operands");

        // x / inf = 0
        perform_arithmetic('h4479ff5c, 'h7f800000, 32'h0);

        // -inf / x = -inf
        perform_arithmetic('hff800000, 'h4479ff5c, 'hff800000);

        // Invalid operand ////////////////////////////////////////////////////

        $display("Case E: Invalid operation exception");

        // inf / inf = NaN
        perform_exception('h7f800000, 'h7f800000, 1);

        // inf / -inf = -NaN
        perform_exception('h7f800000, 'hff800000, 1);

        // x / NaN = NaN
        perform_exception('h3db8d4fe, 'h7fffffff, 1);

        // x / -NaN = -NaN
        perform_exception('h3db8d4fe, 'hffffffff, 1);

        // NaN / NaN = NaN
        perform_exception('h7fffffff, 'h7fffffff, 1);

        // NaN / inf = NaN
        perform_exception('h7fffffff, 'h7f800000, 1);

        // Overflow ///////////////////////////////////////////////////////////

        $display("Case F: Overflow exception");
        
        // 3e38 / 6e-37 = inf
        perform_exception('h7f61b1e6, 'h034c2b5f, 2);

        $display("@@@ PASSED");
        $finish;
    end

    initial begin
        $dumpfile("build/test_divider.vcd");
        $dumpvars(0, test_divider);
    end

endmodule
