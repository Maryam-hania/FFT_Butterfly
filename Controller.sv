module controller (
    input  logic clk,
    input  logic rst,
    input  logic start,
    
    // Status Outputs
    output logic busy,
    output logic done,
    // Signals from Controller to Datapath
    output logic load_inputs,   // save new inputs A,B,W
    output logic en_mult,       // enable multiplication
    output logic en_scale,  	// capture scaled/saturated product
    output logic en_add    		// enable adders/subtractors and calculate final answers 
);
  // State Definitions
  typedef enum logic [2:0] {
        IDLE,    
        MULT,      
        SCALE,
    	ADD,
        DONE          
    } state_t;

    state_t current_state, next_state;
  //Sequential Logic (Hamesha state ko next state se update karna)
      always_ff @(posedge clk) begin
        if (rst) current_state <= IDLE;
        else     current_state <= next_state;
    end
  //Combinational Logic 
  //Default values (har cycle pe reset hongi)
    always_comb begin
        next_state = current_state;
        busy        = 1'b1;  
        done        = 1'b0;
        load_inputs = 1'b0;
        en_mult     = 1'b0;
        en_scale    = 1'b0;
        en_add      = 1'b0;

      unique case (current_state)
            IDLE: begin
                busy = 1'b0;
              	if (start==1) begin
                    load_inputs  = 1'b1;
                    next_state = MULT;
                end else begin
                    next_state = IDLE;
                end
            end

            MULT: begin
                en_mult   = 1'b1;
                next_state = SCALE;
            end

            SCALE: begin
                en_scale  = 1'b1;
                next_state = ADD;
            end

            ADD: begin
                en_add    = 1'b1;
                next_state = DONE;
            end

            DONE: begin
                busy       = 1'b0;
                done       = 1'b1;
                next_state = IDLE;
            end

            default: begin
                busy       = 1'b0;
                next_state = IDLE;
            end
        endcase
    end

endmodule