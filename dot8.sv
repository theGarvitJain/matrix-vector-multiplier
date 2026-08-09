/***************************************************/
/* ECE 327: Digital Hardware Systems - Spring 2026 */
/* Lab 4 (v2) (-0.340)                                           */
/* 8-Lane Dot Product Module                       */
/***************************************************/

module dot8 # (
    parameter IWIDTH = 8,
    parameter OWIDTH = 32
)(
    input clk,
    input rst,
    input signed [8*IWIDTH-1:0] vec0,
    input signed [8*IWIDTH-1:0] vec1,
    input ivalid,
    output signed [OWIDTH-1:0] result,
    output ovalid
);

/******* Your code starts here *******/

localparam STAGES = 6;

logic signed [IWIDTH-1:0] ra0, ra1, ra2, ra3, ra4, ra5, ra6, ra7;
logic signed [IWIDTH-1:0] rb0, rb1, rb2, rb3, rb4, rb5, rb6, rb7;

(* use_dsp = "yes" *)logic signed [IWIDTH*2-1:0] m0, m1, m2, m3, m4, m5, m6, m7;
logic signed [IWIDTH*2-1:0] p0, p1, p2, p3, p4, p5, p6, p7; // DSP block requires MREG and PREG

logic signed [IWIDTH*2:0] a0, a1, a2, a3;
logic signed [IWIDTH*2+1:0] a4, a5;
logic signed [OWIDTH-1:0] a6;

logic [STAGES-1:0] r_stages;

always_ff @ (posedge clk) begin
    if (rst) begin
        ra0 <= '0;
        ra1 <= '0;
        ra2 <= '0;
        ra3 <= '0;
        ra4 <= '0;
        ra5 <= '0;
        ra6 <= '0;
        ra7 <= '0;

        rb0 <= '0;
        rb1 <= '0;
        rb2 <= '0;
        rb3 <= '0;
        rb4 <= '0;
        rb5 <= '0;
        rb6 <= '0;
        rb7 <= '0;

        m0 <= '0;
        m1 <= '0;
        m2 <= '0;
        m3 <= '0;
        m4 <= '0;
        m5 <= '0;
        m6 <= '0;
        m7 <= '0;

        a0 <= '0;
        a1 <= '0;
        a2 <= '0;
        a3 <= '0;
        a4 <= '0;
        a5 <= '0;
        a6 <= '0;
       
       r_stages <= '0;
    end else begin
       
        ra0 <= vec0[8*IWIDTH-1 : 7*IWIDTH];
        ra1 <= vec0[7*IWIDTH-1 : 6*IWIDTH];
        ra2 <= vec0[6*IWIDTH-1 : 5*IWIDTH];
        ra3 <= vec0[5*IWIDTH-1 : 4*IWIDTH];
        ra4 <= vec0[4*IWIDTH-1 : 3*IWIDTH];
        ra5 <= vec0[3*IWIDTH-1 : 2*IWIDTH];
        ra6 <= vec0[2*IWIDTH-1 : 1*IWIDTH];
        ra7 <= vec0[1*IWIDTH-1 : 0];
       
        rb0 <= vec1[8*IWIDTH-1 : 7*IWIDTH];
        rb1 <= vec1[7*IWIDTH-1 : 6*IWIDTH];
        rb2 <= vec1[6*IWIDTH-1 : 5*IWIDTH];
        rb3 <= vec1[5*IWIDTH-1 : 4*IWIDTH];
        rb4 <= vec1[4*IWIDTH-1 : 3*IWIDTH];
        rb5 <= vec1[3*IWIDTH-1 : 2*IWIDTH];
        rb6 <= vec1[2*IWIDTH-1 : 1*IWIDTH];
        rb7 <= vec1[1*IWIDTH-1 : 0];
           
        r_stages <= {ivalid, r_stages[STAGES-1:1]};
       
        m0 <= ra0 * rb0;
        m1 <= ra1 * rb1;
        m2 <= ra2 * rb2;
        m3 <= ra3 * rb3;
        m4 <= ra4 * rb4;
        m5 <= ra5 * rb5;
        m6 <= ra6 * rb6;
        m7 <= ra7 * rb7;
       
        // 1 cycle delay to use the DSP blocks
        p0 <= m0;
        p1 <= m1;
        p2 <= m2;
        p3 <= m3;
        p4 <= m4;
        p5 <= m5;
        p6 <= m6;
        p7 <= m7;
       
        // Stage 2
        a0 <= p0 + p1;
        a1 <= p2 + p3;
        a2 <= p4 + p5;
        a3 <= p6 + p7;
       
        // Stage 3
        a4 <= a0 + a1;
        a5 <= a2 + a3;
       
        // Stage 4
        a6 <= a4 + a5;
    end    
end
   
assign result = a6;
assign ovalid = r_stages[0];

/******* Your code ends here ********/

endmodule