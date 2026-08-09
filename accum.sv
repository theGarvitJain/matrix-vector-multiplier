/***************************************************/
/* ECE 327: Digital Hardware Systems - Spring 2026 */
/* Lab 4                                           */
/* Accumulator Module                              */
/***************************************************/

module accum # (
    parameter DATAW = 32,
    parameter ACCUMW = 32
)(
    input  clk,
    input  rst,
    input  signed [DATAW-1:0] data,
    input  ivalid,
    input  first,
    input  last,
    output signed [ACCUMW-1:0] result,
    output ovalid
);

/******* Your code starts here *******/
logic signed [DATAW-1:0] r_data;
logic r_first;
logic r_last;
logic r_ivalid;
logic signed [ACCUMW-1:0] r_result;
logic r_ovalid;

always_ff @(posedge clk) begin
    if (rst) begin
        r_data <= '0; r_first <= '0; r_last <= '0; r_ivalid <= '0;
        r_result <= '0; r_ovalid <= '0;
    end else begin
        // stage 1: register inputs
        r_data   <= data;
        r_first  <= first;
        r_last   <= last;
        r_ivalid <= ivalid;
        // stage 2: accumulate
        r_ovalid <= r_ivalid & r_last;
        if (r_ivalid)
            r_result <= r_first ? r_data : (r_result + r_data);
    end
end

assign result = r_result;
assign ovalid = r_ovalid;

/******* Your code ends here ********/

endmodule
