module fft_butterfly (
    input  logic clk,
    input  logic rst,
    input  logic start,
 
    // Complex input A
    input  logic signed [15:0] a_re, a_im,
    // Complex input B
    input  logic signed [15:0] b_re, b_im,
    // Complex twiddle factor W
    input  logic signed [15:0] w_re, w_im,
 
    // Complex output X_top (A + B*W)
    output logic signed [15:0] x_top_re, x_top_im,
    // Complex output X_bottom (A - B*W)
    output logic signed [15:0] x_bot_re, x_bot_im,
 
    // Control outputs
    output logic busy,
    output logic done
);
 
    // Wires carrying the 4 enable pulses from controller -> datapath
    logic load_inputs, en_mult, en_scale, en_add;
 
    controller u_controller (
        .clk         (clk),
        .rst         (rst),
        .start       (start),
        .busy        (busy),
        .done        (done),
        .load_inputs (load_inputs),
        .en_mult     (en_mult),
        .en_scale    (en_scale),
        .en_add      (en_add)
    );
 
    datapath u_datapath (
        .clk         (clk),
        .rst         (rst),
        .load_inputs (load_inputs),
        .en_mult     (en_mult),
        .en_scale    (en_scale),
        .en_add      (en_add),
        .a_re (a_re), .a_im (a_im),
        .b_re (b_re), .b_im (b_im),
        .w_re (w_re), .w_im (w_im),
        .x_top_re (x_top_re), .x_top_im (x_top_im),
        .x_bot_re (x_bot_re), .x_bot_im (x_bot_im)
    );
 
endmodule
 
