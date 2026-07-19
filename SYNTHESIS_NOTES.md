# Synthesis Notes

These notes capture the current findings from `flow rvlab_fpga_top.syn` for the
student vertex-processor integration.

## Vertex processor BRAM output registers

Vivado reports messages like:

```text
INFO: [Synth 8-7052] The timing for the instance
core_i/student_i/vertex_processor_i/gen_dpram_lanes[*].u_dpram_lane/ram_reg_*
(implemented as a Block RAM) might be sub-optimal as no optional output register
could be merged into the ram block.
```

This is not a functional error. It means the DPRAMs were inferred as block RAMs,
but Vivado could not pack the read-data output register into the BRAM primitive's
optional output register. The current timing failures are not reported inside
`vertex_processor_i`, so this is a potential future timing issue rather than the
current blocker.

Possible solutions:

- Leave it unchanged until a failing timing path goes through
  `core_i/student_i/vertex_processor_i/gen_dpram_lanes`.
- Add an extra registered read-data stage in `dpram.sv`. This may allow Vivado to
  use the BRAM output register, but it adds one cycle of read latency. If this is
  done, `vertex_processor.sv` must also delay the matching metadata signals
  (`read_valid_q`, `read_first_vertex_q`, and `read_id_q`) by one cycle.
- Replace the inferred DPRAM with a Xilinx `xpm_memory_tdpram` instance and set
  an explicit read latency, for example `READ_LATENCY_B = 2`. This gives more
  synthesis control, but makes the memory implementation vendor-specific.

## Other findings from timing, DRC, and methodology reports

The synthesized design is present and `vertex_processor_i` is not optimized away:

```text
core_i/student_i/vertex_processor_i
```

The vertex processor uses 16 `RAMB36` blocks, matching four logical 4096 x 32-bit
DPRAM lanes split across BRAM primitives.

Timing is currently not clean for the whole design:

```text
Setup:      WNS = -0.633 ns, TNS = -2.044 ns, 11 failing endpoints
Hold:       WHS = -0.176 ns, THS = -7.740 ns, 45 failing endpoints
Pulse width WPWS = -0.808 ns, TPWS = -3.370 ns, 9 failing endpoints
```

The sampled worst failing paths are not in `vertex_processor_i`:

- `pixel_clk` setup failure in HDMI TMDS generation.
- `pixel_clk_x5` pulse-width failure in HDMI/MMCM clocking.
- `ddr_ctrl` hold failure in DDR PHY reset/OSERDES logic.
- `sys_clk` hold failure from timer interrupt logic into the CPU interrupt
  controller.

The timing report has no no-clock registers, no unconstrained internal endpoints,
no multiple-clock pins, and no latch loops.

DRC and methodology reports show warnings, but no direct vertex-processor DRC or
methodology violation was found. The notable warnings are:

- CPU DSP input/output pipelining and async-reset limitations.
- HDMI MMCM input phase-alignment warning.
- HDMI reset synchronization warning where a LUT drives async reset pins.
- DDR/cache small memories mapped to distributed RAM because of timing.
- DDR RAM retargeting advisories.
- Some generic unconnected/trimmed-register warnings in existing CPU/debug/TL-UL
  logic.

Vertex-specific synthesis notes from `vivado.log`:

- Vivado trims unused high bits from internal `u_matmul/mult_result_reg`
  registers. This is expected if only part of the full multiplication result is
  consumed.
- The current vertex output is kept alive through the `vertex_debug` marked-debug
  signal in `student.sv`. Once a real downstream rasterizer/consumer is connected,
  this temporary debug preservation should be revisited.
