/***************************************************/
/* ECE 327: Digital Hardware Systems - Spring 2026 */
/* Lab 4                                           */
/* Simple Dual-Port Memory                         */
/***************************************************/

module mem # (
    parameter DATAW = 8,
    parameter DEPTH = 512,
    parameter ADDRW = $clog2(DEPTH)
)(
    input  clk,
    input  [DATAW-1:0] wdata,
    input  [ADDRW-1:0] waddr,
    input  wen,
    input  [ADDRW-1:0] raddr,
    output [DATAW-1:0] rdata
);

logic [DATAW-1:0] r_rdata;

logic [DATAW-1:0] mem_array [0:DEPTH-1];

always_ff @ (posedge clk) begin
    if (wen) begin
        mem_array[waddr] <= wdata;
    end
    r_rdata <= mem_array[raddr];
end

assign rdata = r_rdata;

endmodule
