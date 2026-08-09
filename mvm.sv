/***************************************************/
/* ECE 327: Digital Hardware Systems - Spring 2026 */
/* Lab 4                                           */
/* Matrix Vector Multiplication (MVM) Module       */
/***************************************************/

module mvm # (
    parameter IWIDTH = 8,
    parameter OWIDTH = 32,
    parameter MEM_DATAW = IWIDTH * 8,
    parameter VEC_MEM_DEPTH = 256,
    parameter VEC_ADDRW = $clog2(VEC_MEM_DEPTH),
    parameter MAT_MEM_DEPTH = 512,
    parameter MAT_ADDRW = $clog2(MAT_MEM_DEPTH),
    parameter NUM_OLANES = 128
)(
    input clk,
    input rst,
    input [MEM_DATAW-1:0] i_vec_wdata,
    input [VEC_ADDRW-1:0] i_vec_waddr,
    input i_vec_wen,
    input [MEM_DATAW-1:0] i_mat_wdata,
    input [MAT_ADDRW-1:0] i_mat_waddr,
    input [NUM_OLANES-1:0] i_mat_wen,
    input i_start,
    input [VEC_ADDRW-1:0] i_vec_start_addr,
    input [VEC_ADDRW:0] i_vec_num_words,
    input [MAT_ADDRW-1:0] i_mat_start_addr,
    input [MAT_ADDRW:0] i_mat_num_rows_per_olane,
    output o_busy,
    output [OWIDTH*NUM_OLANES-1:0] o_result,
    output o_valid
);

/******* Your code starts here *******/

// Vector path 
localparam VEC_ADDR_LATENCY  = 2;   // shared + per-memory replica
localparam MEM_LATENCY       = 1;   // mem.sv read latency
localparam VDIST_LATENCY     = 2;   // mid + leaf data distribution
localparam VEC_PATH_LAT      = VEC_ADDR_LATENCY + MEM_LATENCY + VDIST_LATENCY;

// Matrix path 
localparam MAT_ADDR_LATENCY  = 3;   // shared + mid + PER-LANE replica
localparam MAT_RDATA_LATENCY = 1;   // breaks the BRAM -> DSP hop
localparam MAT_PATH_LAT      = MAT_ADDR_LATENCY + MEM_LATENCY
                                                + MAT_RDATA_LATENCY;

//  Write path 
localparam WR_LATENCY        = 2;   // shared + per-group replica

// Downstream 
localparam DOT_LATENCY = 6;
localparam ACC_LATENCY = 2;

localparam PIPE      = VEC_PATH_LAT + DOT_LATENCY;   // = 11
localparam TOTAL_LAT = PIPE + ACC_LATENCY;           // = 13

//  Replication geometry, safe for ANY NUM_OLANES
localparam LANES_PER_VMEM  = 32;   // 4 vector memory copies at 128 lanes
localparam LANES_PER_VMID  = 16;   // vector data, mid level
localparam LANES_PER_VLEAF = 4;    // vector data, leaf level
localparam LANES_PER_AMID  = 16;   // matrix address, mid level
localparam LANES_PER_WGRP  = 4;    // write data/address replicas
localparam LANES_PER_CGRP  = 4;    // ivalid / first / last replicas

localparam NUM_VMEM  = (NUM_OLANES + LANES_PER_VMEM  - 1) / LANES_PER_VMEM;
localparam NUM_VMID  = (NUM_OLANES + LANES_PER_VMID  - 1) / LANES_PER_VMID;
localparam NUM_VLEAF = (NUM_OLANES + LANES_PER_VLEAF - 1) / LANES_PER_VLEAF;
localparam NUM_AMID  = (NUM_OLANES + LANES_PER_AMID  - 1) / LANES_PER_AMID;
localparam NUM_WGRP  = (NUM_OLANES + LANES_PER_WGRP  - 1) / LANES_PER_WGRP;
localparam NUM_CGRP  = (NUM_OLANES + LANES_PER_CGRP  - 1) / LANES_PER_CGRP;

// Controller
logic [VEC_ADDRW-1:0] vec_raddr;
logic [MAT_ADDRW-1:0] mat_raddr;
logic ctrl_first, ctrl_last, ctrl_ovalid, ctrl_busy;

ctrl #(
    .VEC_ADDRW(VEC_ADDRW),
    .MAT_ADDRW(MAT_ADDRW)
) ctrl_inst (
    .clk                    (clk),
    .rst                    (rst),
    .start                  (i_start),
    .vec_start_addr         (i_vec_start_addr),
    .vec_num_words          (i_vec_num_words),
    .mat_start_addr         (i_mat_start_addr),
    .mat_num_rows_per_olane (i_mat_num_rows_per_olane),
    .vec_raddr              (vec_raddr),
    .mat_raddr              (mat_raddr),
    .accum_first            (ctrl_first),
    .accum_last             (ctrl_last),
    .ovalid                 (ctrl_ovalid),
    .busy                   (ctrl_busy)
);

// Read address trees, dont_touch sotps vivavdo from condensing reg treee
logic [VEC_ADDRW-1:0] vec_raddr_d1;                        // fanout NUM_VMEM
(* dont_touch = "yes" *) logic [VEC_ADDRW-1:0] vec_raddr_q [NUM_VMEM-1:0];

logic [MAT_ADDRW-1:0] mat_raddr_d1;                        // fanout NUM_AMID
(* dont_touch = "yes" *) logic [MAT_ADDRW-1:0] mat_raddr_mid  [NUM_AMID-1:0];
(* dont_touch = "yes" *) logic [MAT_ADDRW-1:0] mat_raddr_leaf [NUM_OLANES-1:0];

always_ff @(posedge clk) begin
    // Vector address: 2 stages
    vec_raddr_d1 <= vec_raddr;
    for (int m = 0; m < NUM_VMEM; m++)
        vec_raddr_q[m] <= vec_raddr_d1;

    // Matrix address: 3 stages, ending in one register PER LANE so that each memory's address net has fanout 1
    mat_raddr_d1 <= mat_raddr;
    for (int m = 0; m < NUM_AMID; m++)
        mat_raddr_mid[m] <= mat_raddr_d1;
    for (int l = 0; l < NUM_OLANES; l++)
        mat_raddr_leaf[l] <= mat_raddr_mid[l / LANES_PER_AMID];
end

// Write port trees (2 stages)
logic [MEM_DATAW-1:0]  mat_wdata_d1, vec_wdata_d1;
logic [MAT_ADDRW-1:0]  mat_waddr_d1;
logic [VEC_ADDRW-1:0]  vec_waddr_d1;
logic [NUM_OLANES-1:0] mat_wen_d1;
logic                  vec_wen_d1;

(* dont_touch = "yes" *) logic [MEM_DATAW-1:0]  mat_wdata_q [NUM_WGRP-1:0];
(* dont_touch = "yes" *) logic [MAT_ADDRW-1:0]  mat_waddr_q [NUM_WGRP-1:0];
(* dont_touch = "yes" *) logic [NUM_OLANES-1:0] mat_wen_q;
(* dont_touch = "yes" *) logic [MEM_DATAW-1:0]  vec_wdata_q [NUM_VMEM-1:0];
(* dont_touch = "yes" *) logic [VEC_ADDRW-1:0]  vec_waddr_q [NUM_VMEM-1:0];
(* dont_touch = "yes" *) logic                  vec_wen_q   [NUM_VMEM-1:0];

always_ff @(posedge clk) begin
    mat_wdata_d1 <= i_mat_wdata;
    mat_waddr_d1 <= i_mat_waddr;
    vec_wdata_d1 <= i_vec_wdata;
    vec_waddr_d1 <= i_vec_waddr;
    for (int g = 0; g < NUM_WGRP; g++) begin
        mat_wdata_q[g] <= mat_wdata_d1;
        mat_waddr_q[g] <= mat_waddr_d1;
    end
    for (int m = 0; m < NUM_VMEM; m++) begin
        vec_wdata_q[m] <= vec_wdata_d1;
        vec_waddr_q[m] <= vec_waddr_d1;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        mat_wen_d1 <= '0;
        mat_wen_q  <= '0;
        vec_wen_d1 <= 1'b0;
        for (int m = 0; m < NUM_VMEM; m++) vec_wen_q[m] <= 1'b0;
    end else begin
        mat_wen_d1 <= i_mat_wen;
        mat_wen_q  <= mat_wen_d1;
        vec_wen_d1 <= i_vec_wen;
        for (int m = 0; m < NUM_VMEM; m++) vec_wen_q[m] <= vec_wen_d1;
    end
end

// Vector memories (2 copies at 128 lanes, to leave BRAM headroom)
logic [MEM_DATAW-1:0] vec_rdata_mem [NUM_VMEM-1:0];

genvar m;
generate
for (m = 0; m < NUM_VMEM; m++) begin : vmem
    mem #(.DATAW(MEM_DATAW), .DEPTH(VEC_MEM_DEPTH)) vec_mem (
        .clk   (clk),
        .wdata (vec_wdata_q[m]),
        .waddr (vec_waddr_q[m]),
        .wen   (vec_wen_q[m]),
        .raddr (vec_raddr_q[m]),
        .rdata (vec_rdata_mem[m])
    );
end
endgenerate

// Two-level vector data distribution tree
//   2 memories -> 8 mid regs (fanout 4) -> 32 leaf regs (fanout 4) -> lanes
(* dont_touch = "yes" *) logic [MEM_DATAW-1:0] vec_rdata_mid  [NUM_VMID-1:0];
(* dont_touch = "yes" *) logic [MEM_DATAW-1:0] vec_rdata_leaf [NUM_VLEAF-1:0];

always_ff @(posedge clk) begin
    for (int v = 0; v < NUM_VMID; v++)
        vec_rdata_mid[v] <= vec_rdata_mem[(v * LANES_PER_VMID) / LANES_PER_VMEM];
    for (int v = 0; v < NUM_VLEAF; v++)
        vec_rdata_leaf[v] <= vec_rdata_mid[(v * LANES_PER_VLEAF) / LANES_PER_VMID];
end

// Control bit pipelines: shared shift chain + replicated final stage, so the replication costs no extra latency
logic [VEC_PATH_LAT-2:0] ivalid_pipe;   // 4 shared stages
logic [PIPE-2:0]         first_pipe;    // 10 shared stages
logic [PIPE-2:0]         last_pipe;
logic [TOTAL_LAT-1:0]    busy_pipe;

(* dont_touch = "yes" *) logic dot_ivalid_q [NUM_CGRP-1:0];
(* dont_touch = "yes" *) logic acc_first_q  [NUM_CGRP-1:0];
(* dont_touch = "yes" *) logic acc_last_q   [NUM_CGRP-1:0];

always_ff @(posedge clk) begin
    if (rst) begin
        ivalid_pipe <= '0;
        first_pipe  <= '0;
        last_pipe   <= '0;
        for (int g = 0; g < NUM_CGRP; g++) begin
            dot_ivalid_q[g] <= 1'b0;
            acc_first_q[g]  <= 1'b0;
            acc_last_q[g]   <= 1'b0;
        end
    end else begin
        ivalid_pipe <= {ivalid_pipe[VEC_PATH_LAT-3:0], ctrl_ovalid};
        first_pipe  <= {first_pipe[PIPE-3:0], ctrl_first};
        last_pipe   <= {last_pipe [PIPE-3:0], ctrl_last};

        for (int g = 0; g < NUM_CGRP; g++) begin
            dot_ivalid_q[g] <= ivalid_pipe[VEC_PATH_LAT-2];
            acc_first_q[g]  <= first_pipe[PIPE-2];
            acc_last_q[g]   <= last_pipe [PIPE-2];
        end
    end
end

// Matrix read data register: breaks the long memory -> DSP hop
logic [MEM_DATAW-1:0] mat_rdata   [NUM_OLANES-1:0];
logic [MEM_DATAW-1:0] mat_rdata_q [NUM_OLANES-1:0];

always_ff @(posedge clk)
    for (int l = 0; l < NUM_OLANES; l++)
        mat_rdata_q[l] <= mat_rdata[l];

// Compute lanes
logic signed [OWIDTH-1:0] dot_result [NUM_OLANES-1:0];
logic dot_ovalid [NUM_OLANES-1:0];
logic signed [OWIDTH-1:0] acc_result [NUM_OLANES-1:0];
logic acc_ovalid [NUM_OLANES-1:0];

genvar i;
generate
for (i = 0; i < NUM_OLANES; i++) begin : olane

    localparam WGRP = i / LANES_PER_WGRP;
    localparam CGRP = i / LANES_PER_CGRP;
    localparam VLF  = i / LANES_PER_VLEAF;

    mem #(.DATAW(MEM_DATAW), .DEPTH(MAT_MEM_DEPTH)) mat_mem (
        .clk   (clk),
        .wdata (mat_wdata_q[WGRP]),
        .waddr (mat_waddr_q[WGRP]),
        .wen   (mat_wen_q[i]),
        .raddr (mat_raddr_leaf[i]),      // per-lane: fanout 1
        .rdata (mat_rdata[i])
    );

    dot8 #(.IWIDTH(IWIDTH), .OWIDTH(OWIDTH)) dot (
        .clk    (clk),
        .rst    (rst),
        .vec0   (vec_rdata_leaf[VLF]),
        .vec1   (mat_rdata_q[i]),
        .ivalid (dot_ivalid_q[CGRP]),
        .result (dot_result[i]),
        .ovalid (dot_ovalid[i])
    );

    accum #(.DATAW(OWIDTH), .ACCUMW(OWIDTH)) acc (
        .clk    (clk),
        .rst    (rst),
        .data   (dot_result[i]),
        .ivalid (dot_ovalid[i]),
        .first  (acc_first_q[CGRP]),
        .last   (acc_last_q[CGRP]),
        .result (acc_result[i]),
        .ovalid (acc_ovalid[i])
    );

    assign o_result[OWIDTH*i +: OWIDTH] = acc_result[i];
end
endgenerate

assign o_valid = acc_ovalid[0];

// Busy
always_ff @(posedge clk) begin
    if (rst) busy_pipe <= '0;
    else     busy_pipe <= {busy_pipe[TOTAL_LAT-2:0], ctrl_ovalid};
end

assign o_busy = i_start | ctrl_busy | (|busy_pipe);

/******* Your code ends here ********/

endmodule
