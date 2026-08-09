# matrix-vector-multiplier

A deeply pipelined, fixed-point matrix-vector multiplication accelerator in SystemVerilog, built for ECE 327 (Digital Hardware Systems) Lab 4 and targeted at the Zynq UltraScale+ MPSoC on the Xilinx Kria board. The design broadcasts one input vector across 128 parallel output lanes, with 8 signed multiplications per lane per cycle, and was iteratively restructured to reach **450 MHz** and sustain approximately **850 GOPS** on a 512 x 512 matrix-vector multiplication.

The architecture follows the tiled dot-product style used by Microsoft's BrainWave accelerator: every output lane owns a matrix memory, dot-product unit, and accumulator, while the vector operand is shared across all lanes. The main challenge was not the arithmetic itself, but distributing shared data and addresses across 128 lanes without allowing fanout, BRAM pressure, or routing distance to set the critical path.

## Interface

```systemverilog
module mvm #(
    parameter IWIDTH        = 8,
    parameter OWIDTH        = 32,
    parameter MEM_DATAW     = IWIDTH * 8,
    parameter VEC_MEM_DEPTH = 256,
    parameter VEC_ADDRW     = $clog2(VEC_MEM_DEPTH),
    parameter MAT_MEM_DEPTH = 512,
    parameter MAT_ADDRW     = $clog2(MAT_MEM_DEPTH),
    parameter NUM_OLANES    = 128
)(
    input  clk,
    input  rst,                         // active-high

    // Vector-memory write port
    input  [MEM_DATAW-1:0] i_vec_wdata,
    input  [VEC_ADDRW-1:0] i_vec_waddr,
    input                  i_vec_wen,

    // Matrix-memory write port
    input  [MEM_DATAW-1:0]  i_mat_wdata,
    input  [MAT_ADDRW-1:0]  i_mat_waddr,
    input  [NUM_OLANES-1:0] i_mat_wen,

    // Operation control
    input                   i_start,
    input [VEC_ADDRW-1:0]   i_vec_start_addr,
    input [VEC_ADDRW:0]     i_vec_num_words,
    input [MAT_ADDRW-1:0]   i_mat_start_addr,
    input [MAT_ADDRW:0]     i_mat_num_rows_per_olane,

    output                              o_busy,
    output [OWIDTH*NUM_OLANES-1:0]      o_result,
    output                              o_valid
);
```

- Inputs are packed into 8-element words. With the default parameters, each memory word contains eight signed 8-bit values.
- `i_mat_wen` is one-hot: each bit selects the matrix memory belonging to one output lane. Vector writes are replicated internally so every vector-memory copy remains identical.
- `i_start` begins the operation described by the vector and matrix start addresses, vector length, and number of rows assigned to each lane.
- `o_result` concatenates one signed 32-bit accumulated result from every lane. `o_valid` pulses when a complete group of lane results is available, and `o_busy` remains asserted until the controller and datapath have drained.

## Architecture

Each of the 128 output lanes reads one 8-element matrix word and computes its dot product against the same 8-element vector word:

```text
lane_result = sum over row words (
                  matrix_word[0] * vector_word[0] +
                  ... +
                  matrix_word[7] * vector_word[7]
              )
```

The final design contains:

- **4 replicated vector memories**, each serving 32 lanes.
- A **two-level vector-data register tree** (mid and leaf stages) between the vector memories and compute lanes.
- A **three-stage matrix-address tree** ending in one address register per lane, giving every matrix memory a local, fanout-1 address connection.
- **128 matrix memories**, `dot8` units, and accumulators, one set per output lane.
- Replicated write and control registers so the high-lane-count paths remain local.

The distribution registers carry `dont_touch` attributes. Without them, Vivado can merge equivalent copies back into a single high-fanout driver and undo the intended routing structure.

## Design evolution

The design was optimized for throughput, deliberately trading additional latency for lane count and clock frequency. Each iteration removed one physical bottleneck and exposed the next:

| Version | Bottleneck | What changed | Result |
|---|---|---|---|
| v1 - baseline | One vector memory and shared control/address nets drove every lane. | Implemented the straightforward architecture directly from the module specification. | Functionally correct, but unable to scale because shared nets accumulated large fanout and routing delay. |
| v2 - 80 lanes | Broadcasting vector read data across 80 lanes produced net-delay-dominated critical paths. | Replicated the vector memory 8 times so each copy drove fewer lanes. | Fanout fell, but BRAM utilization rose to **92%**. The placer could no longer keep memories close to their DSP consumers, replacing the fanout problem with long routes. |
| v3 - register-tree distribution | Excessive BRAM replication constrained placement. | Reduced the vector memories to 4 copies and distributed their outputs through a two-level register tree. | Recovered BRAM headroom, shortened the vector-data routes, and made **128 lanes** practical. |
| v4 - matrix-address tree | A shared matrix read address still drove all 128 lane memories, or thousands of loads when memories mapped to LUTRAM. | Added shared, mid-level, and per-lane address registers so each memory is driven by a fanout-1 leaf. | Collapsed address-net delay and moved the critical path into the compute datapath. |
| v5 - compute pipelining | Once memory distribution was local, the dot product and accumulator limited frequency. | Pipelined `dot8` across registered inputs, DSP multiply registers, and a three-level adder tree; reduced `accum` to register-then-add. | The integrated 128-lane design reached **450 MHz**, approximately **850 GOPS sustained** on a 512 x 512 MVM. |

All of these changes are expressed in RTL. The final result does not rely on extra synthesis flags, manual placement, custom XDC exceptions, or `phys_opt_design` directives.

## Performance

| Metric | Result |
|---|---|
| Output lanes | 128 |
| Multiplications per lane per cycle | 8 |
| Total multiplications per cycle | 1,024 |
| Integrated Fmax | **450 MHz** |
| Peak arithmetic throughput | **~922 GOPS** |
| Sustained 512 x 512 throughput | **~850 GOPS** |
| Full 512 x 512 latency | **~270 cycles** |
| Input / accumulator precision | signed 8-bit / signed 32-bit |

Peak throughput counts one multiplication and one addition as separate operations:

```text
128 lanes x 8 elements x 2 operations x 450 MHz = 921.6 GOPS
```

The standalone compute blocks were also synthesized against a 1 ns probe clock to expose their true critical paths:

- `dot8`: worst negative slack of -0.340 ns, corresponding to a 1.340 ns period or approximately **746 MHz**.
- `accum`: worst negative slack of approximately -0.010 ns, corresponding to approximately **990 MHz**.

The complete engine runs more slowly than either isolated block because memory placement and chip-wide distribution still dominate at full scale. Its internal data path adds 13 cycles from controller issue through accumulation; the approximately 270-cycle end-to-end figure for a 512 x 512 workload also includes streaming all matrix words through the lanes.

## Files

| File | Purpose |
|---|---|
| [`mvm.sv`](mvm.sv) | Top-level MVM engine containing the replicated vector memories, per-lane matrix memories, distribution trees, compute lanes, and output wiring. |
| [`ctrl.sv`](ctrl.sv) | `IDLE` / `COMPUTE` controller that generates vector and matrix addresses plus the `first`, `last`, valid, and busy control signals. |
| [`dot8.sv`](dot8.sv) | Six-stage, 8-element signed dot product using eight DSP multipliers and a three-level adder-reduction tree. |
| [`accum.sv`](accum.sv) | Two-stage streaming accumulator using `first` and `last` to delimit each matrix row. |
| [`mem.sv`](mem.sv) | Simple dual-port memory with independent synchronous write and read ports and one-cycle read latency. |
