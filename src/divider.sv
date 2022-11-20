module divider (
    // FPGA inteface
    input rst_i,
    input clk_i,

    // Control
    input data_valid_i,
    output logic data_valid_o,

    // Decomposed operands
    input x_sign_i,
    input [7:0] x_exp_i,
    input [22:0] x_frac_i,

    input y_sign_i,
    input [7:0] y_exp_i,
    input [22:0] y_frac_i,

    // Operand metadata
    input x_greater_i,
    input [7:0] exp_shift_i,

    // Infinity/NaN flags
    input x_infinity_i,
    input y_infinity_i,
    input x_nan_i,
    input y_nan_i,

    // Results
    output logic [31:0] z_o,
    output logic except_invalid_operation_o,
    output logic except_overflow_o
);

typedef enum {
                ADD = 1,
                MULT = 0
} operation;

function void start_operation;
    input [31:0] x;
    input [31:0] y;
    input op;

    if (op == ADD) begin
        add_x = x;
        add_y = y;
        add_data_ready = 'h1;
    end

    else begin
        mult_x = x;
        mult_y = y;
        mult_data_ready = 'h1;
    end
endfunction

function bit operation_overflow;
    input op;

    return (op == ADD) ? add_overflow : mult_overflow;
endfunction

// Newton-Raphson Constants
// A=32/17
// B=48/17
localparam [31:0] 
                nr_const_a = 'h3ff0f0f1,
                nr_const_b = 'h4034b4b5,

                inf = 'h7f800000;

// Multiplier
logic mult_data_ready, mult_data_valid;
logic [31:0] mult_x, mult_y, mult_z;
logic mult_overflow;

multiplier M0 (
    .clk_i,
    .rst_i,

    .data_valid_i(mult_data_ready),
    .data_valid_o(mult_data_valid),

    .x_sign_i(mult_x[31]),
    .x_exp_i(mult_x[30:23]),
    .x_frac_i(mult_x[22:0]),

    .y_sign_i(mult_y[31]),
    .y_exp_i(mult_y[30:23]),
    .y_frac_i(mult_y[22:0]),

    //.x_infinity_i,
    //.y_infinity_i,
    //.x_nan_i,
    //.y_nan_i,

    .z_o(mult_z),
    //.except_invalid_operation_o,
    .except_overflow_o(mult_overflow)
);

// Adder + operand parser
logic add_data_ready, add_data_valid;
logic [31:0] add_x, add_y, add_z;
logic add_x_greater;
logic [7:0] add_exp_shift;
logic add_overflow;

operands O0 (
    .x_i(add_x),
    .y_i(add_y),

    .x_greater_o(add_x_greater),
    .exp_shift_o(add_exp_shift)
);

adder A0 (
    .clk_i,
    .rst_i,

    .data_valid_i(add_data_ready),
    .data_valid_o(add_data_valid),

    .x_sign_i(add_x[31]),
    .x_exp_i(add_x[30:23]),
    .x_frac_i(add_x[22:0]),

    .y_sign_i(add_y[31]),
    .y_exp_i(add_y[30:23]),
    .y_frac_i(add_y[22:0]),

    .x_greater_i(add_x_greater),
    .exp_shift_i(add_exp_shift),

    //.x_infinity_i,
    //.y_infinity_i,
    //.x_nan_i,
    //.y_nan_i,

    .z_o(add_z),
    //.except_invalid_operation_o,
    .except_overflow_o(add_overflow)
);

// Scaled denominator in range [0.5, 1]
logic [31:0] denominator_scaled;
assign denominator_scaled = {1'b0, 8'd126, denominator[22:0]};


// Metadata
logic x_is_zero;
logic y_is_zero;

assign x_is_zero = (!x_exp_i && !x_frac_i);
assign y_is_zero = (!y_exp_i && !y_frac_i);

enum {
    READY,

    PRECOMPUTE_A,
    PRECOMPUTE_B,
    RECURSION_A,
    RECURSION_B,
    RECURSION_C,
    SOLUTION,

    INF_OPERANDS,
    INVALID_OPERANDS,
    ZERO_OPERANDS,
    DIV_BY_ZERO,

    OVERFLOW,
    DONE
}
    state, state_ns;

logic [31:0]
    numerator, numerator_ns,
    denominator, denominator_ns,
    temp, temp_ns,
    partial, partial_ns;

logic [1:0] iteration, iteration_ns;
logic step_count, step_count_ns;

logic
    invalid_operation, invalid_operation_ns,
    overflow, overflow_ns;

always_ff @(posedge clk_i) begin
    if (rst_i) begin
        state <= READY;

        numerator <= 'h0;
        denominator <= 'h0;
        temp <= 'h0;
        partial <= 'h0;

        step_count <= 'h0;
        iteration <= 'h0;

        invalid_operation <= 'h0;
        overflow <= 'h0;
    end

    else begin
        state <= state_ns;

        numerator <= numerator_ns;
        denominator <= denominator_ns;
        temp <= temp_ns;
        partial <= partial_ns;

        step_count <= step_count_ns;
        iteration <= iteration_ns;

        invalid_operation <= invalid_operation_ns;
        overflow <= overflow_ns;
    end
end

always @(*) begin
    state_ns = state;

    numerator_ns = numerator;
    denominator_ns = denominator;
    temp_ns = temp;
    partial_ns = partial;

    step_count_ns = step_count;
    iteration_ns = iteration;

    invalid_operation_ns = invalid_operation;
    overflow_ns = overflow;

    case (state)
        READY: begin
            if (rst_i) begin
                mult_x = 'h0;
                mult_y = 'h0;
                mult_data_ready = 'h0;

                add_x = 'h0;
                add_y = 'h0;
                add_data_ready = 'h0;

                data_valid_o = 'h0;
                z_o = 'h0;
                except_invalid_operation_o = 'h0;
                except_overflow_o = 'h0;
            end 
            
            else if (data_valid_i) begin
                state_ns = PRECOMPUTE_A;

                numerator_ns = {x_sign_i, x_exp_i, x_frac_i};
                denominator_ns = {y_sign_i, y_exp_i, y_frac_i};

                if ((x_nan_i || y_nan_i) || (x_infinity_i && y_infinity_i))
                    state_ns = INVALID_OPERANDS;

                else if (y_is_zero)
                    state_ns = DIV_BY_ZERO;

                else if (x_is_zero)
                    state_ns = ZERO_OPERANDS;

                else if (x_infinity_i ^ y_infinity_i)
                        state_ns = INF_OPERANDS;

                else
                    state_ns = PRECOMPUTE_A;

                step_count_ns = 'h0;
                data_valid_o = 'h0;
            end

        end

        // partial = (32/17) * D
        PRECOMPUTE_A: begin
            start_operation(nr_const_a, denominator_scaled, MULT);

            // Wait for mult to latch inputs
            if (!step_count && mult_data_valid) begin
                step_count_ns = 'h1;
            end

            else if (mult_data_valid) begin
                state_ns = operation_overflow(MULT) ? OVERFLOW : PRECOMPUTE_B;
                partial_ns = mult_z;
                step_count_ns = 'h0;
                mult_data_ready = 'b0;
            end
        end

        // partial = (48/17) - partial
        PRECOMPUTE_B: begin
            start_operation(nr_const_b, {~partial[31], partial[30:0]}, ADD);

            // Wait for add to latch inputs
            if (!step_count && add_data_valid) begin
                step_count_ns = 'h1;
            end

            else if (add_data_valid) begin
                state_ns = operation_overflow(ADD) ? OVERFLOW : RECURSION_A;
                partial_ns = add_z;
                step_count_ns = 'h0;
                iteration_ns = 'h0;
                add_data_ready = 'h0;
            end
        end

        // temp = partial * D
        RECURSION_A: begin
            start_operation(partial, denominator_scaled, MULT);

            // Wait for mult to latch inputs
            if (!step_count && mult_data_valid) begin
                step_count_ns = 'h1;
            end

            else if (mult_data_valid) begin
                state_ns = operation_overflow(MULT) ? OVERFLOW : RECURSION_B;
                temp_ns = mult_z;
                step_count_ns = 'h0;
                mult_data_ready = 'b0;
            end
        end

        // temp = 2 - temp
        RECURSION_B: begin
            start_operation(32'h40000000, {~temp[31], temp[30:0]}, ADD);

            // Wait for add to latch inputs
            if (!step_count && add_data_valid) begin
                step_count_ns = 'h1;
            end

            else if (add_data_valid) begin
                state_ns = operation_overflow(ADD) ? OVERFLOW : RECURSION_C;
                temp_ns = add_z;
                step_count_ns = 'h0;
                add_data_ready = 'h0;
            end
        end

        // partial = temp * partial
        RECURSION_C: begin
            start_operation(temp, partial, MULT);

            // Wait for mult to latch inputs
            if (!step_count && mult_data_valid) begin
                step_count_ns = 'h1;
            end

            else if (mult_data_valid) begin
                if (iteration == 'h2) begin
                    state_ns = operation_overflow(MULT) ? OVERFLOW : SOLUTION;
                end else begin
                    iteration_ns = iteration + 1;
                    state_ns = operation_overflow(MULT) ? OVERFLOW : RECURSION_A;
                end

                partial_ns = mult_z;
                step_count_ns = 'h0;
                mult_data_ready = 'b0;
            end
        end

        ZERO_OPERANDS: begin
            partial_ns = {numerator[31], 31'h0};
            state_ns = DONE;
        end

        DIV_BY_ZERO: begin
            partial_ns[31] = numerator[31] ^ denominator[31];
            partial_ns[30:0] = inf[30:0];
            invalid_operation_ns = 'h1;
            state_ns = DONE;
        end

        INF_OPERANDS: begin
            partial_ns[31] = numerator[31] ^ denominator[31];

            // inf / x = inf
            if (numerator[30:0] == inf[30:0])
                partial_ns[30:0] = inf[30:0];

            // x / inf = 0
            else
                partial_ns[30:0] = 31'h0;

            state_ns = DONE;
            invalid_operation_ns = 'h0;
            overflow_ns = 'h0;
        end

        INVALID_OPERANDS: begin
            partial_ns[31] = numerator[31] ^ denominator[31];
            partial_ns[30:0] = {8'd255, 23'd8388607};

            state_ns = DONE;
            invalid_operation_ns = 'h1;
            overflow_ns = 'h0;
        end

        // z = partial * N
        SOLUTION: begin
            start_operation(    numerator,
                                {  
                                    denominator[31],
                                    partial[30:23] + 8'd126 - denominator[30:23],
                                    partial[22:0]
                                },
                                MULT
            );

            // Wait for mult to latch inputs
            if (!step_count && mult_data_valid) begin
                step_count_ns = 'h1;
            end

            else if (mult_data_valid) begin
                state_ns = operation_overflow(MULT) ? OVERFLOW : DONE;

                partial_ns = mult_z;
                invalid_operation_ns = 'h0;
                step_count_ns = 'h0;
                mult_data_ready = 'b0;
            end
        end

        OVERFLOW: begin
            partial_ns = inf;
            overflow_ns = 'h1;
            state_ns = DONE;
        end

        DONE: begin
            data_valid_o = 'h1;
            z_o = partial;
            except_invalid_operation_o = invalid_operation;
            except_overflow_o = overflow;

            state_ns = READY;
        end
    endcase
end
endmodule
