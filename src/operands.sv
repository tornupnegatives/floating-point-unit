module operands (
    // Operands
    input [31:0] x_i,
    input [31:0] y_i,

    // Decomposition
    output logic x_sign_o,
    output logic y_sign_o,

    output logic [7:0] x_exp_o,
    output logic [7:0] y_exp_o,

    output logic [22:0] x_frac_o,
    output logic [22:0] y_frac_o,

    // Exponent shift
    output logic x_greater_o,
    output logic [7:0] exp_shift_o,

    // Infinity/NaN flags
    output logic x_infinity_o,
    output logic y_infinity_o,
    output logic x_nan_o,
    output logic y_nan_o
);

// Intermediate values
logic [7:0] x_exp;
logic [7:0] y_exp;

logic [22:0] x_frac;
logic [22:0] y_frac;

// Unbiased exponent metadata
logic [15:0] x_exp_unbiased;
logic [15:0] y_exp_unbiased;
logic x_greater;

// Extract intermediate values
assign x_exp = x_i[30:23];
assign y_exp = y_i[30:23];

assign x_frac = x_i[22:0];
assign y_frac = y_i[22:0];

// Exponent analysis
assign x_greater = (x_exp == y_exp) ? (x_frac > y_frac) : (x_exp > y_exp);

// Output assignments
assign x_sign_o = x_i[31];
assign y_sign_o = y_i[31];

assign x_exp_o = x_exp;
assign y_exp_o = y_exp;

assign x_frac_o = x_frac;
assign y_frac_o = y_frac;

assign x_greater_o = x_greater;
assign exp_shift_o = x_greater ? (x_exp - y_exp) : (y_exp - x_exp);

assign x_infinity_o = (x_exp == 'hff && x_frac == 'h0);
assign y_infinity_o = (y_exp == 'hff && y_frac == 'h0);

assign x_nan_o = (x_exp == 'hff && x_frac != 'h0);
assign y_nan_o = (y_exp == 'hff && y_frac != 'h0);

endmodule
