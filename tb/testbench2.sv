`timescale 1ns/1ps
module fft_butterfly_tb;

    logic clk = 0;
    logic rst, start;
    logic signed [15:0] a_re, a_im, b_re, b_im, w_re, w_im;
    logic signed [15:0] x_top_re, x_top_im, x_bot_re, x_bot_im;
    logic busy, done;

    // DUT
    fft_butterfly dut (.*);

    // 10ns clock period
    always #5 clk = ~clk;

    // Handy Q4.12 constants for running tests
    //2^12=4096, 4096*1, 4096*0.5 etc.
    localparam signed [15:0] Q1_0  =  16'sd4096;   // 1.0
    localparam signed [15:0] Q0_5  =  16'sd2048;   // 0.5
    localparam signed [15:0] Q0_25 =  16'sd1024;   // 0.25
    localparam signed [15:0] Q0    =  16'sd0;      // 0.0

    // Saturation limits (must match MAX_Q / MIN_Q inside datapath.sv)
    localparam signed [15:0] Q_MAX =  16'sd32767;  // largest positive Q4.12 value
    localparam signed [15:0] Q_MIN = -16'sd32768;  // most negative Q4.12 value

    // Fixed-point <-> real conversion (Q4.12, so divide/multiply by 2^12)
    localparam real SCALE = 4096.0;

    // Tolerance allowed between DUT output and the "golden" real-math model.
    // 1 LSB accounts for the round-to-nearest step inside the multiplier's
    // scale stage; we allow 2 LSB of slack just to be safe against rounding
    // boundary cases.
    localparam int TOL = 2;

    int pass_count = 0;
    int fail_count = 0;

    // ------------------------------------------------------------
    // Fixed-point -> real  and  real -> fixed-point (with rounding
    // and saturation, same behaviour as saturate16() in datapath.sv)
    // ------------------------------------------------------------
    function automatic real fixed_to_real(input logic signed [15:0] val);
        fixed_to_real = real'(val) / SCALE;
    endfunction

    function automatic logic signed [15:0] real_to_fixed(input real val);
        real scaled;
        longint temp;
        scaled = val * SCALE;
        // round to nearest (matches the +half-LSB rounding done in the DUT)
        if (scaled >= 0.0) temp = longint'(scaled + 0.5);
        else                temp = longint'(scaled - 0.5);
        // saturate, same limits as MAX_Q / MIN_Q
        if (temp > 32767)       temp = 32767;
        else if (temp < -32768) temp = -32768;
        real_to_fixed = temp[15:0];
    endfunction

    function automatic int abs_diff(input int a, input int b);
        abs_diff = (a > b) ? (a - b) : (b - a);
    endfunction

    // Add two fixed-point (integer) Q4.12 values and saturate to 16-bit,
    // same clamp behaviour as saturate16() in datapath.sv. Used to mirror
    // the DUT's STAGE 3 (final A +/- mul saturation) exactly.
    function automatic logic signed [15:0] sat_add16(input int a, input int b);
        int sum;
        sum = a + b;
        if (sum > 32767)       sat_add16 = 32767;
        else if (sum < -32768) sat_add16 = -32768;
        else                   sat_add16 = sum[15:0];
    endfunction

    // ------------------------------------------------------------
    // "Golden" reference model : Xtop = A + B*W , Xbot = A - B*W
    //
    // IMPORTANT: the DUT saturates TWICE, not once --
    //   STAGE 2 clamps the B*W product down to 16-bit  (mul_re/mul_im)
    //   STAGE 3 clamps A +/- mul down to 16-bit again   (x_top/x_bot)
    // The golden model must reproduce BOTH clamp points, in the same
    // order, or it will disagree with the DUT whenever the raw product
    // B*W is big enough to overflow 16 bits on its own (very common
    // with fully random operands).
    // ------------------------------------------------------------
    task automatic compute_expected(
        input  logic signed [15:0] in_a_re, in_a_im,
        input  logic signed [15:0] in_b_re, in_b_im,
        input  logic signed [15:0] in_w_re, in_w_im,
        output logic signed [15:0] exp_top_re, exp_top_im,
        output logic signed [15:0] exp_bot_re, exp_bot_im
    );
        real b_re_r, b_im_r, w_re_r, w_im_r;
        real p_re, p_im;
        logic signed [15:0] mul_re, mul_im;   // matches DUT's mul_re/mul_im register

        b_re_r = fixed_to_real(in_b_re);  b_im_r = fixed_to_real(in_b_im);
        w_re_r = fixed_to_real(in_w_re);  w_im_r = fixed_to_real(in_w_im);

        // complex multiply P = B * W  (real math, full precision)
        p_re = b_re_r * w_re_r - b_im_r * w_im_r;
        p_im = b_re_r * w_im_r + b_im_r * w_re_r;

        // STAGE 2 equivalent: round + saturate the product to 16-bit,
        // BEFORE adding A -- this is the clamp the old model was missing.
        mul_re = real_to_fixed(p_re);
        mul_im = real_to_fixed(p_im);

        // STAGE 3 equivalent: add/sub the (already clamped) product with
        // A, in integer domain, and saturate again.
        exp_top_re = sat_add16(in_a_re,  mul_re);
        exp_top_im = sat_add16(in_a_im,  mul_im);
        exp_bot_re = sat_add16(in_a_re, -mul_re);
        exp_bot_im = sat_add16(in_a_im, -mul_im);
    endtask

    // ------------------------------------------------------------
    // Task: apply one set of inputs, pulse start, wait for done,
    // then compare the 4 outputs against expected values.
    // using automatic allocates new memory space for inputs and variables
    // everytime task is called
    // ------------------------------------------------------------
    task automatic run_test(
        input string                test_name,
        input logic signed [15:0]   in_a_re, in_a_im,
        input logic signed [15:0]   in_b_re, in_b_im,
        input logic signed [15:0]   in_w_re, in_w_im,
        input logic signed [15:0]   exp_top_re, exp_top_im,
        input logic signed [15:0]   exp_bot_re, exp_bot_im
    );
        // Drive the inputs (task wali test values local variables se DUT ke
        // input ports pe apply hoti hain)
        a_re = in_a_re;  a_im = in_a_im;
        b_re = in_b_re;  b_im = in_b_im;
        w_re = in_w_re;  w_im = in_w_im;

        // Pulse start for exactly 1 cycle so that FSM knows there is data and
        // goes from IDLE to calc state
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait until the FSM finishes (done goes high)
        wait (done);
        #1;   // small delay so the register values have settled

        // Check all 4 outputs together (exact match, used for directed tests)
        if (x_top_re === exp_top_re && x_top_im === exp_top_im &&
            x_bot_re === exp_bot_re && x_bot_im === exp_bot_im) begin
            $display("PASS : %s", test_name);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL : %s", test_name);
            $display("       Xtop got (%0d, %0d)   expected (%0d, %0d)",
                       x_top_re, x_top_im, exp_top_re, exp_top_im);
            $display("       Xbot got (%0d, %0d)   expected (%0d, %0d)",
                       x_bot_re, x_bot_im, exp_bot_re, exp_bot_im);
            fail_count = fail_count + 1;
        end

        // Let the controller return to IDLE before the next test
        @(posedge clk); //1 cycle ka delay
    endtask

    // ------------------------------------------------------------
    // Task: same as run_test, but the expected value is computed
    // automatically from the real-number golden model, and the
    // comparison allows +/- TOL LSB of quantization error.
    // Used for randomized testing.
    // ------------------------------------------------------------
    task automatic run_test_tolerant(
        input string                test_name,
        input logic signed [15:0]   in_a_re, in_a_im,
        input logic signed [15:0]   in_b_re, in_b_im,
        input logic signed [15:0]   in_w_re, in_w_im
    );
        logic signed [15:0] exp_top_re, exp_top_im, exp_bot_re, exp_bot_im;

        compute_expected(in_a_re, in_a_im, in_b_re, in_b_im, in_w_re, in_w_im,
                          exp_top_re, exp_top_im, exp_bot_re, exp_bot_im);

        a_re = in_a_re;  a_im = in_a_im;
        b_re = in_b_re;  b_im = in_b_im;
        w_re = in_w_re;  w_im = in_w_im;

        start = 1;
        @(posedge clk);
        start = 0;

        wait (done);
        #1;

        if (abs_diff(x_top_re, exp_top_re) <= TOL && abs_diff(x_top_im, exp_top_im) <= TOL &&
            abs_diff(x_bot_re, exp_bot_re) <= TOL && abs_diff(x_bot_im, exp_bot_im) <= TOL) begin
            $display("PASS : %s", test_name);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL : %s", test_name);
            $display("       A=(%0d,%0d) B=(%0d,%0d) W=(%0d,%0d)",
                       in_a_re, in_a_im, in_b_re, in_b_im, in_w_re, in_w_im);
            $display("       Xtop got (%0d, %0d)   expected (%0d, %0d)  [tol=%0d]",
                       x_top_re, x_top_im, exp_top_re, exp_top_im, TOL);
            $display("       Xbot got (%0d, %0d)   expected (%0d, %0d)  [tol=%0d]",
                       x_bot_re, x_bot_im, exp_bot_re, exp_bot_im, TOL);
            fail_count = fail_count + 1;
        end

        @(posedge clk);
    endtask

    // ------------------------------------------------------------
    // Test vectors
    // ------------------------------------------------------------
    initial begin
        rst = 1; start = 0;
        a_re = 0; a_im = 0; b_re = 0; b_im = 0; w_re = 0; w_im = 0;
        repeat (2) @(posedge clk); //2 clock cycles ka delay
        rst = 0;
        @(posedge clk);

        // ---------- Test 1: trivial twiddle W0 = 1 + j0 ----------
        // W=1 means no rotation at all, B*W = B exactly.
        // A = 0.5, B = -0.25  =>  Xtop = A+B = 0.25, Xbot = A-B = 0.75
        run_test("W=1+j0 (trivial, no rotation)",
            Q0_5, Q0,             // A = 0.5 + j0
            -Q0_25, Q0,           // B = -0.25 + j0
            Q1_0, Q0,             // W = 1 + j0
            Q0_25, Q0,            // expect Xtop = 0.25 + j0
            16'sd3072, Q0);       // expect Xbot = 0.75 + j0  (0.75 * 4096 = 3072)

        // ---------- Test 2: trivial twiddle W(N/4) = 0 - j1 ----------
        // W=-j rotates B by -90 degrees: B*(-j) = b_im - j*b_re
        // A = 0, B = 0.5 + j0.25  =>  B*W = 0.25 - j0.5
        // Xtop = A + B*W = 0.25 - j0.5, Xbot = A - B*W = -0.25 + j0.5
        run_test("W=0-j1 (trivial, imaginary rotation)",
            Q0, Q0,               // A = 0
            Q0_5, Q0_25,          // B = 0.5 + j0.25
            Q0, -Q1_0,            // W = 0 - j1
            Q0_25, -Q0_5,         // expect Xtop = 0.25 - j0.5
            -Q0_25, Q0_5);        // expect Xbot = -0.25 + j0.5

        // ---------- Test 3: zero inputs ----------
        // A = 0, B = 0  =>  result is always 0, regardless of W
        run_test("A=0, B=0 (zero inputs)",
            Q0, Q0,
            Q0, Q0,
            Q1_0, Q0,
            Q0, Q0,
            Q0, Q0);

        // ---------- Test 4: maximum positive saturation ----------
        // A = max, B = max, W = 1  =>  Xtop = max+max, must clamp to Q_MAX
        // Xbot = max-max = 0 (no saturation on this side, but checks routing)
        run_test("Max positive saturation",
            Q_MAX, Q_MAX,
            Q_MAX, Q_MAX,
            Q1_0, Q0,
            Q_MAX, Q_MAX,         // expect Xtop clamped to +32767
            Q0, Q0);              // expect Xbot = 0

        // ---------- Test 5: minimum negative saturation ----------
        // A = min, B = min, W = 1  =>  Xbot = min-min... wait, min-min=0,
        // so use A = min, B = max instead to force the negative clamp:
        // Xbot = A - B = min - max, must clamp to Q_MIN
        run_test("Min negative saturation",
            Q_MIN, Q_MIN,
            Q_MAX, Q_MAX,
            Q1_0, Q0,
            -16'sd1, -16'sd1,      // expect Xtop = min+max = -1 (no clamp needed)
            Q_MIN, Q_MIN);         // expect Xbot clamped to -32768

        // ---------- Test 6: phase rotation, W = -1 + j0 (180 deg) ----------
        // Multiplying by -1 flips both real and imaginary signs of B.
        // A = 0, B = 0.5 + j0.25  =>  B*W = -0.5 - j0.25
        run_test("W=-1+j0 (180 degree rotation)",
            Q0, Q0,
            Q0_5, Q0_25,
            -Q1_0, Q0,
            -Q0_5, -Q0_25,         // expect Xtop = -0.5 - j0.25
            Q0_5, Q0_25);          // expect Xbot = 0.5 + j0.25

        // ---------- Test 7: phase rotation, W = 0 + j1 (+90 deg) ----------
        // Multiplying by +j: B*(+j) = -b_im + j*b_re
        // A = 0, B = 0.5 + j0.25  =>  B*W = -0.25 + j0.5
        run_test("W=0+j1 (90 degree rotation)",
            Q0, Q0,
            Q0_5, Q0_25,
            Q0, Q1_0,
            -Q0_25, Q0_5,          // expect Xtop = -0.25 + j0.5
            Q0_25, -Q0_5);         // expect Xbot = 0.25 - j0.5

        // ------------------------------------------------------------
        // Test 8: hundreds of randomized complex operand combinations,
        // self-checked against the real-number golden model above.
        // ------------------------------------------------------------
        begin
            int i;
            logic signed [15:0] r_a_re, r_a_im, r_b_re, r_b_im, r_w_re, r_w_im;
            for (i = 0; i < 300; i++) begin
                r_a_re = $urandom_range(0, 65535);
                r_a_im = $urandom_range(0, 65535);
                r_b_re = $urandom_range(0, 65535);
                r_b_im = $urandom_range(0, 65535);
                r_w_re = $urandom_range(0, 65535);
                r_w_im = $urandom_range(0, 65535);
                run_test_tolerant($sformatf("random_%0d", i),
                    r_a_re, r_a_im, r_b_re, r_b_im, r_w_re, r_w_im);
            end
        end

        // ------------------------------------------------------------
        $display("----------------------------------------");
        $display("Total: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $stop;
    end

endmodule