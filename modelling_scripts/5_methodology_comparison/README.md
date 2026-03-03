# Experiment 5: Cross-Methodology Comparison

This experiment synthesises results from three complementary performance analysis
approaches applied to the same Autoware ROS 2 nodes, assessing how well the
methods agree and which nodes represent the highest-priority optimisation targets.

| Method | Experiment | What it measures |
|---|---|---|
| CARET tracing | [`1_caret_tracing/`](../1_caret_tracing/) | End-to-end callback latency |
| `perf` agnostic metrics | [`3_perf_profiling/`](../3_perf_profiling/) | PMU counter–based ops/byte proxy |
| `miniperf` roofline | [`4_miniperf_roofline/`](../4_miniperf_roofline/) | LLVM IR–based roofline analysis |

---

## Why Compare Methodologies?

Each method has complementary strengths and weaknesses:

| | CARET | perf agnostic | miniperf roofline |
|---|---|---|---|
| **What it tells you** | _Which_ nodes are slow | _Why_ they may be slow (memory/compute/branch ratio) | _How far_ from hardware ceiling; per-loop AI |
| **Instrumentation required** | Yes (LTTng hooks) | No (PMU counters only) | Yes (Clang plugin required) |
| **Architecture-specific setup** | No | Partially (ARM event names) | No (LLVM IR is target-agnostic) |
| **Granularity** | Per-callback | Per-process | Per-loop hotspot |
| **Quantifies headroom** | No | Indirectly | Yes (distance from roofline) |

A node that appears in **all three** as high-latency, memory-bound, and below
the memory-bandwidth ceiling is a top-priority, high-confidence target for
optimisation (e.g. cache-blocking, memory layout improvements, vectorisation).

---

## Prerequisites

All three upstream experiments must have been run:

```bash
# Results required:
../1_caret_tracing/results/node_latency_ranking.csv
../3_perf_profiling/perf_data/agnostic_metrics.csv
../4_miniperf_roofline/results/miniperf_roofline_agg.csv
```

Python dependencies:
```bash
pip install pandas numpy matplotlib pyyaml
```

---

## Workflow

### Step 1 — Produce Comparison Table

```bash
python3 compare_methodologies.py
```

Loads data from all three experiments, normalises bottleneck labels to a common
taxonomy (`memory | cache | compute | branch | unknown`), and outputs:

```
results/
├── comparison_table.csv       # Per-node metrics from all 3 methods
├── bottleneck_agreement.csv   # Pairwise agreement rates between methods
└── methodology_summary.md     # Auto-generated markdown summary table
```

**Bottleneck normalisation rules:**

| Raw label (any method) | Canonical class |
|---|---|
| memory, mem, bandwidth | `memory` |
| compute, flop, cpu | `compute` |
| cache, llc, l1/l2/l3 | `cache` |
| branch | `branch` |
| other / missing | `unknown` |

### Step 2 — Generate Comparison Plots

```bash
python3 plot_comparison.py
```

Produces five figures in `graphs/`:

| File | Description |
|---|---|
| `01_latency_rank_vs_ai.png` | CARET rank (y) vs miniperf AI (x) — top-left quadrant = priority targets |
| `02_ai_method_comparison.png` | perf ops/byte vs miniperf AI scatter (green=agree, red=disagree) |
| `03_bottleneck_distribution.png` | Stacked bar of classification counts per method |
| `04_latency_ms_vs_ai.png` | Absolute latency (ms) vs arithmetic intensity |
| `05_combined_dashboard.png` | 2×2 overview dashboard |

---

## Interpreting the Results

### Reading `01_latency_rank_vs_ai.png`

```
CARET Rank
    (1 = highest latency)
         ^
    1   |  ★★ High-priority targets ★★
        |  (high latency, low AI → memory-bound)
   10   |   ○   ○  ○
        |        ○      ●  ●
   15   |              (low latency, compute-bound)
        +──────────────────────────────────> AI (FLOPs/byte)
             0.1       1        10
```

Nodes in the **top-left** quadrant have high CARET latency *and* low arithmetic
intensity. They are the candidates most likely to benefit from memory access
pattern improvements (cache blocking, NUMA-aware data layout, prefetching).

### Reading `02_ai_method_comparison.png`

The **diagonal** represents perfect agreement between perf's LLC-miss–based
arithmetic intensity proxy and miniperf's LLVM IR–counted AI.

- **Above diagonal**: miniperf sees more compute-intensity than perf (possible
  GPU/accelerator offload not captured by LLC misses, or inner-loop computation
  below LLC miss granularity).
- **Below diagonal**: perf overestimates memory intensity relative to the true
  FLOP/byte count.

### Agreement Rate Interpretation

| Agreement rate | Interpretation |
|---|---|
| > 80 % | Strong: both methods consistently identify the same primary bottleneck |
| 60–80 % | Moderate: methods broadly agree with some edge-case divergence |
| < 60 % | Weak: investigate nodes individually; workload may be phase-variable |

---

## Output File Reference

| File | Description |
|---|---|
| `results/comparison_table.csv` | Node-level side-by-side metrics |
| `results/bottleneck_agreement.csv` | Method pairwise agreement rates |
| `results/methodology_summary.md` | Auto-generated markdown table |
| `graphs/01_latency_rank_vs_ai.png` | Rank vs AI scatter |
| `graphs/02_ai_method_comparison.png` | Method correlation |
| `graphs/03_bottleneck_distribution.png` | Classification distribution |
| `graphs/04_latency_ms_vs_ai.png` | Absolute latency vs AI |
| `graphs/05_combined_dashboard.png` | 2×2 summary dashboard |
