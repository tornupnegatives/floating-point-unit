module multiplier (
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

// Expanded fractional components
logic [23:0] a_frac, b_frac;
assign a_frac = {1'b1, x_frac_i};
assign b_frac = {1'b1, y_frac_i};

enum {
    READY,
    NORMALIZE,
    INF_OPERANDS,
    INVALID_OPERANDS,
    ZERO_OPERANDS,
    VALIDATE_RESULT,
    DONE
}
    state, state_ns;

logic z_sign, z_sign_ns;
logic [8:0] z_exp, z_exp_ns;
logic [47:0] z_frac_expanded, z_frac_expanded_ns;
logic [8:0] z_exp_normalized, z_exp_normalized_ns;
logic [22:0] z_frac_normalized, z_frac_normalized_ns;

// Metadata
logic x_is_zero;
logic y_is_zero;

assign x_is_zero = (!x_exp_i && !x_frac_i);
assign y_is_zero = (!y_exp_i && !y_frac_i);

// Output registers
logic invalid_operation, invalid_operation_ns;
logic overflow, overflow_ns;

always_ff @(posedge clk_i) begin
    if (rst_i) begin
        z_sign <= 'h0;
        z_exp <= 'h0;

        z_frac_expanded <= 'h0;

        z_exp_normalized <= 'h0;
        z_frac_normalized <= 'h0;

        invalid_operation <= 'h0;
        overflow <= 'h0;

        state <= 'h0;
    end else begin
        z_sign <= z_sign_ns;
        z_exp <= z_exp_ns;

        z_frac_expanded <= z_frac_expanded_ns;

        z_exp_normalized <= z_exp_normalized_ns;
        z_frac_normalized <= z_frac_normalized_ns;

        invalid_operation <= invalid_operation_ns;
        overflow <= overflow_ns;

        state <= state_ns;
    end
end

always @(*) begin
    z_sign_ns = z_sign;
    z_exp_ns = z_exp;
    z_frac_expanded_ns = z_frac_expanded;
    z_exp_normalized_ns = z_exp_normalized;
    z_frac_normalized_ns = z_frac_normalized;
    invalid_operation_ns = invalid_operation;
    overflow_ns = overflow;
    state_ns = state;

    case (state)
        READY: begin
            if (rst_i) begin
                data_valid_o = 'h0;
                z_o = 'h0;
                except_invalid_operation_o = 'h0;
                except_overflow_o = 'h0;

            end else if (data_valid_i) begin
                z_sign_ns = x_sign_i ^ y_sign_i;
                z_exp_ns = (x_exp_i + y_exp_i) - 'd127;

                z_frac_expanded_ns = a_frac * b_frac;

                if (x_nan_i || y_nan_i)
                    state_ns = INVALID_OPERANDS;

                else if (x_infinity_i || y_infinity_i)
                    if (!x_is_zero && !y_is_zero)
                        state_ns = INF_OPERANDS;
                    else
                        state_ns = INVALID_OPERANDS;

                else if (x_is_zero || y_is_zero)
                    state_ns = ZERO_OPERANDS;

                else
                    state_ns = NORMALIZE;

                data_valid_o = 'h0;
            end
        end

        NORMALIZE: begin
            if (z_frac_expanded[47]) begin
                z_frac_normalized_ns = z_frac_expanded[46:24];
                z_exp_normalized_ns = z_exp + 1;
            end

            else begin
                z_frac_normalized_ns = z_frac_expanded[45:23];
                z_exp_normalized_ns = z_exp;

            end

            invalid_operation_ns = 'h0;
            state_ns = VALIDATE_RESULT;
        end

        VALIDATE_RESULT: begin
            overflow_ns = 'h0;

            if (z_exp_normalized[8] && !z_exp_normalized[7]) begin
                z_exp_normalized_ns = 'hff;
                z_frac_normalized_ns = 'h0;
                overflow_ns = 'h1;
            end

            state_ns = DONE;
        end

        INF_OPERANDS: begin
            z_exp_normalized_ns = 'hff;
            z_frac_normalized_ns = 'h0;

            state_ns = DONE;
        end

        INVALID_OPERANDS: begin
            static logic [31:0] quiet_nan = 32'h7fffffff;

            z_sign_ns = quiet_nan[31];
            z_exp_normalized_ns = quiet_nan[30:23];
            z_frac_normalized_ns = quiet_nan[22:0];

            invalid_operation_ns = 'h1;
            overflow_ns = 'h0;
            state_ns = DONE;
        end

        ZERO_OPERANDS: begin
            z_exp_normalized_ns = 'h0;
            z_frac_normalized_ns = 'h0;

            state_ns = DONE;
        end

        DONE: begin
            data_valid_o = 'h1;
            z_o = {z_sign, z_exp_normalized[7:0], z_frac_normalized[22:0]};
            except_invalid_operation_o = invalid_operation;
            except_overflow_o = overflow;

            state_ns = READY;
        end
    endcase
end
endmodule
