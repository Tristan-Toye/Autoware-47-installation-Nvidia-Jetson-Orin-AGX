# Perf Roofline Metrics Definitions

This document defines the FLOPs and memory traffic metrics used in the
perf-based roofline analysis (experiment 3), and explains the dual-estimate
approach for the Nvidia Jetson Orin AGX (ARM Cortex-A78AE).

---

## Hardware Platform

| Parameter | Value | Source |
|---|---|---|
| CPU | 12x ARM Cortex-A78AE @ 2.2 GHz | Jetson Orin AGX 64 GB |
| SIMD | 128-bit NEON (Advanced SIMD), 2 pipes per core | ARM TRM |
| L1D/L1I | 64 KB / 64 KB per core | ARM TRM |
| L2 | 512 KB per core | ARM TRM |
| L3 (LLC) | 4 MB shared | ARM TRM |
| Cache line | 64 bytes | ARM TRM |
| Memory | LPDDR5, 204.8 GB/s peak bandwidth | Product brief |

---

## PMU Counters Used

| Event | Raw code | ARM name | Description |
|---|---|---|---|
| `r0076` | 0x0076 | `VFP_SPEC` | Scalar floating-point instructions speculatively executed (single or double precision) |
| `r0075` | 0x0075 | `ASE_SPEC` | Advanced SIMD (NEON) instructions speculatively executed |
| `ll_cache_miss_rd` | -- | `LL_CACHE_MISS_RD` | Last-level cache read misses (data fetched from DRAM) |
| `inst_retired` | -- | `INST_RETIRED` | Architecturally retired instructions |
| `cpu_cycles` | -- | `CPU_CYCLES` | CPU cycles |
| `task-clock` | -- | (software) | Wall-clock time attributed to the task (milliseconds) |

These are collected together in the `arm_fp_operations` cluster in
`perf_config.yaml` to ensure correlated measurement.

---

## Why ASE_SPEC Needs a Multiplier

`ASE_SPEC` counts SIMD **instructions**, not element-level **operations**.
Each NEON instruction operates on a 128-bit vector register that holds
multiple data elements. The number of elements depends on the data width:

| Data width | Bits | Elements per 128-bit register | FLOPs per instruction (no FMA) | FLOPs per instruction (with FMA) |
|---|---|---|---|---|
| FP16 | 16 | 8 | 8 | 16 |
| **FP32** | **32** | **4** | **4** | **8** |
| FP64 | 64 | 2 | 2 | 4 |

FMA (fused multiply-add) performs both a multiply and an add per element
in a single instruction, so the standard roofline convention counts it
as 2 FLOPs per element.

Since the PMU does not report data width or FMA usage, we compute
**two estimates** that bracket the true value.

---

## Dual FLOPs Estimates

### Estimate A: Conservative (x4)

```
FLOPs_conservative = VFP_SPEC + (ASE_SPEC x 4)
```

- Assumes all SIMD work is FP32 (4 elements per 128-bit register)
- Counts each element operation as 1 FLOP (FMA counted as 1, not 2)
- Paired ceiling: **peak_fp32_gflops = 105.6 GFLOPs/s**
  (12 cores x 2.2 GHz x 2 FMA ops x 2 pipes = 105.6, but since we don't
  count FMA double, use: 12 x 2.2 x 4 = 105.6)
- Ridge point: 105.6 / 204.8 = **0.5156 FLOPs/byte**

### Estimate B: FMA-adjusted (x8)

```
FLOPs_fma = VFP_SPEC + (ASE_SPEC x 8)
```

- Assumes all SIMD work is FP32 FMA (4 elements x 2 ops per FMA)
- Consistent with the full SIMD peak ceiling
- Paired ceiling: **peak_fp32_simd_gflops = 422.4 GFLOPs/s**
  (12 cores x 2.2 GHz x 2 pipes x 4 elements x 2 FMA = 422.4)
- Ridge point: 422.4 / 204.8 = **2.0625 FLOPs/byte**

### Which to trust

- The **conservative estimate** is a lower bound on FLOPs. If a node is
  classified as memory-bound under this estimate, it is very likely
  truly memory-bound.
- The **FMA estimate** is an upper bound on FLOPs. If a node is classified
  as compute-bound under this estimate, it is very likely truly
  compute-bound.
- Nodes where the two estimates **disagree** (conservative says compute,
  FMA says memory) are **ambiguous** and warrant deeper investigation
  with instruction-level profiling or LLVM-based analysis (experiment 4).

---

## Memory Traffic Definition

```
bytes_from_DRAM = ll_cache_miss_rd x 64
```

- `ll_cache_miss_rd` is the ARM PMU event for last-level-cache read misses
- Each miss causes a 64-byte cache line to be fetched from DRAM
- This measures **actual DRAM read traffic** for the profiled process

### Why not use generic `cache-misses`?

The generic perf event `cache-misses` maps to different hardware events
depending on kernel configuration and may include:
- L1 misses (not DRAM traffic)
- Speculative misses
- Write misses (not just reads)

`ll_cache_miss_rd` is unambiguous on this platform: it counts LLC read
misses that result in DRAM fetches.

---

## Roofline Coordinates

For each node, two points are plotted on the roofline:

| Axis | Conservative | FMA-adjusted |
|---|---|---|
| X (Arithmetic Intensity) | `FLOPs_conservative / bytes_from_DRAM` | `FLOPs_fma / bytes_from_DRAM` |
| Y (Performance) | `FLOPs_conservative / wall_time_s / 1e9` | `FLOPs_fma / wall_time_s / 1e9` |

Bound classification:
- **Memory-bound** if AI < ridge point (node is below the sloped memory ceiling)
- **Compute-bound** if AI >= ridge point (node is below the flat compute ceiling)

---

## Additional Derived Metrics

| Metric | Formula | Purpose |
|---|---|---|
| `fp_fraction` | `(VFP_SPEC + ASE_SPEC) / inst_retired` | Fraction of all instructions that are FP/SIMD (higher = more FP-intensive) |
| `simd_fraction` | `ASE_SPEC / (VFP_SPEC + ASE_SPEC)` | Fraction of FP work that is vectorized (higher = better SIMD utilization) |

---

## Caveats

1. **Speculative vs retired counts.** `VFP_SPEC` and `ASE_SPEC` count
   speculatively executed instructions, not architecturally retired ones.
   Instructions on mispredicted branch paths are included. On well-behaved
   workloads, the speculative overcount is typically 1-5%.

2. **ASE_SPEC includes integer SIMD.** ARM NEON handles both floating-point
   and integer vector operations (byte shuffles, integer comparisons,
   saturating arithmetic, etc.). The `ASE_SPEC` counter does not
   distinguish between FP and integer SIMD. For compute-heavy numerical
   code this is usually dominated by FP, but for data-processing or
   serialization code the integer SIMD fraction may be significant.

3. **Data width is unknown.** The x4 and x8 multipliers assume FP32.
   If a node performs primarily FP64 operations, x4 overcounts by 2x.
   If a node uses FP16, x4 undercounts by 2x. Most Autoware perception
   and planning nodes use FP32 for point cloud and transform math.

4. **FMA ratio is unknown.** The x8 estimate assumes every SIMD instruction
   is an FMA. In practice, many SIMD instructions are simple add, multiply,
   compare, or conversion operations (1 op per element, not 2). The true
   FLOPs value lies between the x4 and x8 estimates.

5. **Write traffic is excluded.** The `ll_cache_miss_rd` counter only
   captures read misses. Write-back traffic from dirty cache lines is not
   counted. This means `bytes_from_DRAM` underestimates total memory
   traffic, which can make AI appear higher (more compute-bound) than
   reality for write-heavy workloads.

---

## Output Files

| File | Description |
|---|---|
| `perf_data/perf_roofline.csv` | Per-node dual-estimate roofline coordinates |
| `perf_data/agnostic_metrics.csv` | Architecture-agnostic metrics including AI and bottleneck classification |
| `perf_data/visualizations/arithmetic_intensity.png` | Dual-estimate AI bar chart |
