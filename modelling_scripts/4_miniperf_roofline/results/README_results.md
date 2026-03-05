# Experiment 4: Roofline Analysis — Results

## Overview

A roofline model was constructed for 10 Autoware nodes on the Nvidia Jetson Orin
AGX. Because the full miniperf LLVM-IR instrumentation plugin could not be built
on this platform, arithmetic intensity and performance values were **derived from
hardware performance counters** (Experiment 3 data) using
`generate_roofline_from_perf.py`.

## Data Files

### `miniperf_roofline.csv`

Per-node roofline coordinates, one row per node:

| Column | Description |
|---|---|
| `node_name` | Name of the Autoware node/container |
| `function` | Set to `whole_program` (perf profiles the entire process) |
| `arithmetic_intensity` | Operations per byte of memory traffic |
| `performance_gflops` | Estimated performance in GFLOP/s |
| `bound` | `Compute` or `Memory` (relative to the roofline ceilings) |

### `miniperf_roofline_agg.csv`

Aggregated per-node summary (same data, wider format):

| Column | Description |
|---|---|
| `weighted_ai` | Weighted arithmetic intensity (ops/byte) |
| `max_performance_gflops` | Peak observed performance |
| `dominant_bound` | Whether the node is compute- or memory-bound on the roofline |
| `n_hotspots` | Number of hotspot functions detected |

## Visualisations (`../graphs/`)

| File | What it shows |
|---|---|
| `roofline_plot.png` | Classic roofline diagram with hardware ceilings and per-node data points |
| `roofline_interactive.html` | Bokeh interactive version (pan, zoom, hover tooltips) |

## Roofline Ceilings Used

| Ceiling | Value | Source |
|---|---|---|
| Peak compute | 275 GFLOP/s | Orin AGX GPU-side FP32 (CPU-side is lower) |
| Peak DRAM bandwidth | 204.8 GB/s | LPDDR5 spec (Orin AGX 64 GB config) |
| Ridge point | ~1.34 FLOP/byte | Peak compute / peak bandwidth |

## Key Findings

All nodes fall well below the roofline ceilings. Arithmetic intensity values
range from ~0.6 to ~0.9 ops/byte, placing every node to the **left of the ridge
point** and confirming the memory-bound classification from Experiment 3. The
compute-bound label in `dominant_bound` reflects the proxy derivation method;
the absolute positions on the roofline plot are more informative than the labels.

## Limitations

- Performance values are estimates derived from `instructions / wall-time`, not
  true FLOP counts. Actual FLOP-based arithmetic intensity would require
  LLVM-IR-level instrumentation (the full miniperf pipeline).
- The proxy approach cannot distinguish between integer and floating-point
  operations, so the GFLOP/s figures are upper bounds.
