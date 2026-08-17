module datapath (
    input  logic clk,
    input  logic rst,
    
    // Signals coming from Controller
    input  logic               load_inputs,   
    input  logic               en_mult,        
    input  logic               en_scale,
  	input  logic               en_add, 
    // Complex inputs (16-bit signed)
  	input  logic signed [15:0] a_re, a_im,
  	input  logic signed [15:0] b_re, b_im,
  	input  logic signed [15:0] w_re, w_im,
  
  	// Complex Outputs (16-bit signed)
    output logic signed [15:0] x_top_re, x_top_im,
    output logic signed [15:0] x_bot_re, x_bot_im
);
  
  	localparam int FRAC_BITS = 12;
    localparam logic signed [15:0] MAX_Q = 16'sh7FFF;   //  32767
    localparam logic signed [15:0] MIN_Q = 16'sh8000;   // -32768
 
    function logic signed [15:0] saturate16(input logic signed [32:0] val);
        if (val > MAX_Q)      saturate16 = MAX_Q;
        else if (val < MIN_Q) saturate16 = MIN_Q;
        else                  saturate16 = val[15:0];
    endfunction

  	// Input Registers
    logic signed [15:0] a_re_reg, a_im_reg;
    logic signed [15:0] b_re_reg, b_im_reg;
    logic signed [15:0] w_re_reg, w_im_reg;
  
	    always_ff @(posedge clk) begin
        if (rst) begin
            a_re_reg <= '0;  a_im_reg <= '0;
            b_re_reg <= '0;  b_im_reg <= '0;
            w_re_reg <= '0;  w_im_reg <= '0;
        end else if (load_inputs) begin
            a_re_reg <= a_re;  a_im_reg <= a_im;
            b_re_reg <= b_re;  b_im_reg <= b_im;
            w_re_reg <= w_re;  w_im_reg <= w_im;
        end
    end
 
    // STAGE 1 -- Multiply
  
  	// Multiplier Outputs (32-bit for 16x16)
  	logic signed [31:0] M1, M2, M3, M4;
  	assign M1 = b_re_reg * w_re_reg;
    assign M2 = b_im_reg * w_im_reg;
    assign M3 = b_re_reg * w_im_reg;
    assign M4 = b_im_reg * w_re_reg;
  
  	// Intermediate Complex Product P = B * W (33-bit)
  	logic signed [32:0] P_re, P_im;
  	
     always_ff @(posedge clk) begin
        if (rst) begin
            P_re <= '0; P_im <= '0;
        end else if (en_mult) begin
            P_re <= M1 - M2;
            P_im <= M3 + M4;
        end
    end


 	// STAGE 2 -- Scale
 	 logic signed [15:0] mul_re, mul_im;
 
  	  always_ff @(posedge clk) begin
        if (rst) begin
            mul_re <= '0; mul_im <= '0;
        end else if (en_scale) begin
            // add half an LSB before the arithmetic shift = round-to-nearest
            mul_re <= saturate16((P_re + (1 <<< (FRAC_BITS - 1))) >>> FRAC_BITS);
            mul_im <= saturate16((P_im + (1 <<< (FRAC_BITS - 1))) >>> FRAC_BITS);
        end
    end
 

  	// STAGE 3 -- Add/Subtract: Xtop = A + mul, Xbot = A - mul.
    // Each result is saturated independently -- this sum can overflow even when A and mul 			   individually fit in 16 bits.
    always_ff @(posedge clk) begin
        if (rst) begin
            x_top_re <= '0; x_top_im <= '0;
            x_bot_re <= '0; x_bot_im <= '0;
        end else if (en_add) begin
            x_top_re <= saturate16(a_re_reg + mul_re);
            x_top_im <= saturate16(a_im_reg + mul_im);
            x_bot_re <= saturate16(a_re_reg - mul_re);
            x_bot_im <= saturate16(a_im_reg - mul_im);
        end
    end
 
endmodule
