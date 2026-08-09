/***************************************************/
/* ECE 327: Digital Hardware Systems - Spring 2026 */
/* Lab 4                                           */
/* MVM Control FSM                                 */
/***************************************************/

module ctrl # (
    parameter VEC_ADDRW = 8,
    parameter MAT_ADDRW = 9,
    parameter VEC_SIZEW = VEC_ADDRW + 1,
    parameter MAT_SIZEW = MAT_ADDRW + 1
    
)(
    input  clk,
    input  rst,
    input  start,
    input  [VEC_ADDRW-1:0] vec_start_addr,
    input  [VEC_SIZEW-1:0] vec_num_words,
    input  [MAT_ADDRW-1:0] mat_start_addr,
    input  [MAT_SIZEW-1:0] mat_num_rows_per_olane,
    output [VEC_ADDRW-1:0] vec_raddr,
    output [MAT_ADDRW-1:0] mat_raddr,
    output accum_first,
    output accum_last,
    output ovalid,
    output busy
);

/******* Your code starts here *******/


localparam IDLE    = 1'b0;
localparam COMPUTE = 1'b1;
 
logic state;
 
// Registered copies of the operand descriptors, captured in IDLE
logic [VEC_ADDRW-1:0] r_vec_start_addr;
logic [VEC_SIZEW-1:0] r_vec_num_words;
logic [MAT_SIZEW-1:0] r_mat_num_rows;
 
// word_cnt: position within the current matrix row (0 .. vec_num_words-1)
// row_cnt : which row of this output lane we are on
logic [VEC_SIZEW-1:0] word_cnt;
logic [MAT_SIZEW-1:0] row_cnt;
 
// Address counters -- loaded with the start addresses, then incremented.
// Driving the memory ports straight out of a register keeps the path short.
logic [VEC_ADDRW-1:0] r_vec_raddr;
logic [MAT_ADDRW-1:0] r_mat_raddr;
 
logic last_word, last_row;
 
assign last_word = (word_cnt == r_vec_num_words - 1'b1);
assign last_row  = (row_cnt  == r_mat_num_rows  - 1'b1);
 
always_ff @(posedge clk) begin
    if (rst) begin
        state            <= IDLE;
        r_vec_start_addr <= '0;
        r_vec_num_words  <= '0;
        r_mat_num_rows   <= '0;
        word_cnt         <= '0;
        row_cnt          <= '0;
        r_vec_raddr      <= '0;
        r_mat_raddr      <= '0;
    end else begin
        case (state)
 
        IDLE: begin
            // Keep sampling the operand descriptors while idle
            r_vec_start_addr <= vec_start_addr;
            r_vec_num_words  <= vec_num_words;
            r_mat_num_rows   <= mat_num_rows_per_olane;
 
            // All outputs held at zero in IDLE
            word_cnt    <= '0;
            row_cnt     <= '0;
            r_vec_raddr <= '0;
            r_mat_raddr <= '0;
 
            if (start) begin
                state       <= COMPUTE;
                // Load from the live inputs: the registered copies above are
                // not visible until the next cycle.
                r_vec_raddr <= vec_start_addr;
                r_mat_raddr <= mat_start_addr;
            end
        end
 
        COMPUTE: begin
            // The matrix sweep is linear across the whole operation, because
            // each lane's rows are stored contiguously in its matrix memory.
            r_mat_raddr <= r_mat_raddr + 1'b1;
 
            if (!last_word) begin
                word_cnt    <= word_cnt + 1'b1;
                r_vec_raddr <= r_vec_raddr + 1'b1;
            end else begin
                // End of a row: restart the vector, advance to the next row
                word_cnt    <= '0;
                r_vec_raddr <= r_vec_start_addr;
                row_cnt     <= row_cnt + 1'b1;
 
                if (last_row) begin
                    // Whole MVM finished -- return to IDLE with outputs cleared
                    state       <= IDLE;
                    row_cnt     <= '0;
                    r_vec_raddr <= '0;
                    r_mat_raddr <= '0;
                end
            end
        end
 
        endcase
    end
end
 
assign vec_raddr   = r_vec_raddr;
assign mat_raddr   = r_mat_raddr;
assign busy        = (state == COMPUTE);
assign ovalid      = (state == COMPUTE);
assign accum_first = (state == COMPUTE) & (word_cnt == '0);
assign accum_last  = (state == COMPUTE) & last_word;

/******* Your code ends here ********/

endmodule
