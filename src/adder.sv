module adder (
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
    input infinity_i,
    input nan_i,

    // Results
    output logic [31:0] z_o,
    output logic z_infinity_o,
    output logic z_nan_o
);

// Expanded fractional components
logic [23:0] a_frac, b_frac;
assign a_frac = {1'b1, (x_greater_i ? x_frac_i : y_frac_i)};
assign b_frac = {1'b1, (x_greater_i ? y_frac_i : x_frac_i)} >> exp_shift_i;

// Operation detection
logic should_subtract;
assign should_subtract = (x_sign_i ^ y_sign_i);

enum {
    READY,
    NORMALIZE,
    DONE
}
    state, state_ns;

logic z_sign, z_sign_ns;
logic [7:0] z_exp, z_exp_ns;

logic [23:0] z_frac_expanded, z_frac_expanded_ns;
logic z_frac_carry, z_frac_carry_ns;

// Outputs
logic [31:0] z, z_ns;
logic z_infinity, z_infinity_ns;
logic z_nan, z_nan_ns;

logic data_valid, data_valid_ns;

always_ff @(posedge clk_i) begin
    if (rst_i) begin
        z_sign <= 'h0;
        z_exp <= 'h0;

        z_frac_expanded <= 'h0;
        z_frac_carry <= 'h0;

        z <= 'h0;
        z_infinity <= 'h0;
        z_nan <= 'h0;
        data_valid <= 'h0;

        state <= 'h0;
    end else begin
        z_sign <= z_sign_ns;
        z_exp <= z_exp_ns;

        z_frac_expanded <= z_frac_expanded_ns;
        z_frac_carry <= z_frac_carry_ns;

        z <= z_ns;
        z_infinity <= z_infinity_ns;
        z_nan <= z_nan_ns;
        data_valid <= data_valid_ns;

        state <= state_ns;
    end
end

always_comb begin
    z_sign_ns = z_sign;
    z_exp_ns = z_exp;
    z_frac_expanded_ns = z_frac_expanded;
    z_frac_carry_ns = z_frac_carry;
    z_ns = z;
    z_infinity_ns = z_infinity;
    z_nan_ns = z_nan;
    data_valid_ns = data_valid;
    state_ns = state;

    case (state)
        READY: begin
            if (data_valid_i) begin
                z_sign_ns = (x_greater_i) ? x_sign_i : y_sign_i;
                z_exp_ns = (x_greater_i) ? x_exp_i : y_exp_i;

                {z_frac_carry_ns, z_frac_expanded_ns} = (should_subtract)   ?
                                                        a_frac - b_frac     :
                                                        a_frac + b_frac     ;

                // TODO SPECIAL CASES
                state_ns = NORMALIZE;
            end
        end

        NORMALIZE: begin
            if (z_frac_carry) begin
                z_frac_expanded_ns = z_frac_expanded >> 1;
                z_exp_ns = z_exp + 1;
            end else begin
                for (int i = 0; i < 23 && !z_frac_expanded_ns[23]; i++) begin
                    z_frac_expanded_ns = z_frac_expanded << i;
                    z_exp_ns = z_exp - i;
                end
            end

            // Assign output registers
            data_valid_ns = 'h1;
            z_ns = {z_sign, z_exp, z_frac_expanded[22:0]};
            z_infinity_ns = 'h0;
            z_nan_ns = 'h0;

            state_ns = DONE;
        end

        DONE: begin
            data_valid_ns = 'h0;
            state_ns = READY;
        end
    endcase
end

assign z_o = z;
assign z_infinity_o = z_infinity;
assign z_nan_o = z_nan;
assign data_valid_o = data_valid;

endmodule
