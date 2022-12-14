`timescale 1ns/1ps

module adder (
    // FPGA inteface
    input rst_i,
    input clk_i,

    // Control
    input data_ready_i,
    input [6:0] rounding_mode_i,
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

// Expanded fractional components
logic [23:0] a_frac, b_frac;
assign a_frac = {1'b1, (x_greater_i ? x_frac_i : y_frac_i)};
assign b_frac = {1'b1, (x_greater_i ? y_frac_i : x_frac_i)};

// Operation detection
logic should_subtract;
assign should_subtract = (x_sign_i ^ y_sign_i);

// Sticky bit mask
logic [23:0] sticky_bit_mask;
assign sticky_bit_mask = 23'h7fffff >> (23 - exp_shift_i + 2);

enum {
    READY,
    NORMALIZE,
    INF_OPERANDS,
    INVALID_OPERANDS,
    ROUND_TIE_TO_EVEN,
    VALIDATE_RESULT,
    DONE
}
    state, state_ns;

logic z_sign, z_sign_ns;
logic [7:0] z_exp, z_exp_ns;

logic [23:0] z_frac_expanded, z_frac_expanded_ns;
logic z_frac_carry, z_frac_carry_ns;

logic [7:0] z_exp_normalized, z_exp_normalized_ns;
logic [23:0] z_frac_normalized, z_frac_normalized_ns;

// Rounding bits
logic [6:0] rounding_mode, rounding_mode_ns;
logic 
    guard_bit, guard_bit_ns,
    round_bit, round_bit_ns,
    sticky_bit, sticky_bit_ns;

// Output registers
logic invalid_operation, invalid_operation_ns;
logic overflow, overflow_ns;

always_ff @(posedge clk_i) begin
    if (rst_i) begin
        z_sign <= 'h0;
        z_exp <= 'h0;

        z_frac_expanded <= 'h0;
        z_frac_carry <= 'h0;

        z_exp_normalized <= 'h0;
        z_frac_normalized <= 'h0;

        rounding_mode <= 'h0;
        guard_bit <= 'h0;
        round_bit <= 'h0;
        sticky_bit <= 'h0;

        invalid_operation <= 'h0;
        overflow <= 'h0;

        state <= READY;
    end else begin
        z_sign <= z_sign_ns;
        z_exp <= z_exp_ns;

        z_frac_expanded <= z_frac_expanded_ns;
        z_frac_carry <= z_frac_carry_ns;

        z_exp_normalized <= z_exp_normalized_ns;
        z_frac_normalized <= z_frac_normalized_ns;

        rounding_mode <= rounding_mode_ns;
        guard_bit <= guard_bit_ns;
        round_bit <= round_bit_ns;
        sticky_bit <= sticky_bit_ns;

        invalid_operation <= invalid_operation_ns;
        overflow <= overflow_ns;

        state <= state_ns;
    end
end

`ifdef ICARUS
always @(*) begin
`else
always_comb begin
`endif
    z_sign_ns = z_sign;
    z_exp_ns = z_exp;

    z_frac_expanded_ns = z_frac_expanded;
    z_frac_carry_ns = z_frac_carry;

    z_exp_normalized_ns = z_exp_normalized;
    z_frac_normalized_ns = z_frac_normalized;

    rounding_mode_ns = rounding_mode;
    guard_bit_ns = guard_bit;
    round_bit_ns = round_bit;
    sticky_bit_ns = sticky_bit;

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

            end else if (data_ready_i) begin
                z_sign_ns = (x_greater_i) ? x_sign_i : y_sign_i;
                z_exp_ns = (x_greater_i) ? x_exp_i : y_exp_i;

                {z_frac_carry_ns, z_frac_expanded_ns} = (should_subtract) ? a_frac - (b_frac  >> exp_shift_i) : a_frac + (b_frac  >> exp_shift_i);

                rounding_mode_ns = rounding_mode_i;
                guard_bit_ns = (b_frac >> exp_shift_i - 1) & 23'b1;
                round_bit_ns = (b_frac >> (exp_shift_i - 2)) & 23'b1;
                sticky_bit_ns = |(b_frac & sticky_bit_mask);

                if ( (x_infinity_i && y_infinity_i) || (x_nan_i || y_nan_i) )
                    state_ns = INVALID_OPERANDS;

                else if (x_infinity_i ^ y_infinity_i)
                    state_ns = INF_OPERANDS;

                else
                    state_ns = NORMALIZE;

                data_valid_o = 'h0;
            end
        end

        NORMALIZE: begin
            z_exp_normalized_ns = z_exp;
            z_frac_normalized_ns = z_frac_expanded;

            guard_bit_ns = guard_bit;
            round_bit_ns = round_bit;
            sticky_bit_ns = sticky_bit;

            if (z_frac_carry) begin
                z_frac_normalized_ns = z_frac_expanded >> 1;
                z_frac_normalized_ns[23] = 'b1;
                z_exp_normalized_ns = z_exp + 1;

                guard_bit_ns = z_frac_normalized[0];
                round_bit_ns = guard_bit;
                sticky_bit_ns = sticky_bit | round_bit;
            end

            else begin
                int i;

`ifdef ICARUS
                i = 1;
                while(!z_frac_normalized_ns[23]) begin
                    z_frac_normalized_ns = z_frac_expanded << i;
                    z_exp_normalized_ns = z_exp - i;
                    
                    i++;
                end
 `else
                for (i = 23; i >= 0; i--) begin
                    if (z_frac_expanded[i]) begin
                        z_frac_normalized_ns = z_frac_expanded << (23 - i);
                        z_exp_normalized_ns = z_exp - (23 - i);
                        break;
                    end
                end
 `endif

                if (rounding_mode) begin
                    z_frac_normalized_ns[0] = guard_bit_ns;
                    guard_bit_ns = round_bit_ns;
                    round_bit_ns = 'b0;
                end
            end

            invalid_operation_ns = 'h0;

            if (rounding_mode == 'b000001)
                state_ns = ROUND_TIE_TO_EVEN;
            else
                state_ns = VALIDATE_RESULT;
        end

        ROUND_TIE_TO_EVEN: begin
            if (guard_bit && (round_bit | sticky_bit | z_frac_normalized[0])) begin
                z_frac_normalized_ns = z_frac_normalized + 1;

                if (z_frac_normalized_ns == 23'h7fffff)
                    z_exp_normalized_ns = z_exp + 1;
            end

            state_ns = VALIDATE_RESULT;
        end

        VALIDATE_RESULT: begin
            overflow_ns = 'h0;

            if (z_exp_normalized === 'hff) begin
                z_sign_ns = 'h0;
                z_frac_normalized_ns = 'h0;
                overflow_ns = 'h1;
            end

            state_ns = DONE;
        end

        INF_OPERANDS: begin
            z_sign_ns = (x_infinity_i) ? x_sign_i : y_sign_i;
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

        DONE: begin
            data_valid_o = 'h1;
            z_o = {z_sign, z_exp_normalized, z_frac_normalized[22:0]};
            except_invalid_operation_o = invalid_operation;
            except_overflow_o = overflow;

            state_ns = READY;
        end
    endcase
end

endmodule
