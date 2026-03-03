# Autoware Performance Modelling Scripts

This folder contains a comprehensive set of scripts for performance modelling
of the Autoware autonomous driving stack on the **Nvidia Jetson Orin AGX**.

The methodology progresses from high-level latency identification down to
hardware-ceiling roofline analysis, with a final cross-methodology comparison.

## Structure

```
modelling_scripts/
├── 1_caret_tracing/           # CARET-based callback latency profiling
├── 2_single_node_isolation/   # Isolate nodes for standalone replay
├── 3_perf_profiling/          # perf-based architecture-agnostic metrics
├── 4_miniperf_roofline/       # LLVM IR roofline analysis (miniperf)
└── 5_methodology_comparison/  # Cross-methodology bottleneck comparison
```

## Workflow Overview

### Step 1: CARET Tracing (`1_caret_tracing/`)
Identifies the **top latency contributors** in a running Autoware system.
1. Run Autoware with CARET/LTTng tracing enabled
2. Analyse trace data and generate latency visualisations
3. Export node latency rankings to CSV

### Step 2: Single Node Isolation (`2_single_node_isolation/`)
Enables per-node profiling by replaying stored rosbag data through an
isolated node process (using `ros2_single_node_replayer`).
1. Collect node metadata while Autoware is running
2. Merge latency data with node info
3. Isolate and record the top-N latency nodes

### Step 3: Perf Profiling (`3_perf_profiling/`)
Applies **Linux perf** to quantify hardware counter–based metrics for each
isolated node (IPC, cache miss rates, MPKI, arithmetic intensity proxy).
1. Run perf stat using clustered event groups per node
2. Clean and parse raw perf output into CSVs
3. Compute architecture-agnostic derived metrics

### Step 4: miniperf Roofline (`4_miniperf_roofline/`)
Applies the **LLVM IR–based agnostic roofline technique** from
*Batashev et al. (see `agnostic_risc_paper.pdf`)* using the
[miniperf](https://github.com/alexbatashev/miniperf) tool.
Unlike perf, this approach instruments the binary at the LLVM IR level to
count FLOPs and memory bytes *directly*, producing a true roofline plot.
1. Install miniperf and build the Clang pass plugin
2. Recompile target nodes with the miniperf plugin (`-fpass-plugin=...`)
3. Run `mperf record -s roofline` (two-pass: PMU counters + IR loop stats)
4. Parse results and plot the roofline model

### Step 5: Methodology Comparison (`5_methodology_comparison/`)
Cross-experiment synthesis — loads data from experiments 1, 3, and 4 to
compare bottleneck classifications and identify high-confidence targets.
1. Run `compare_methodologies.py` to build a unified comparison table
2. Run `plot_comparison.py` to generate comparison visualisations

---

## Prerequisites

| Tool | Required by |
|---|---|
| Autoware + CARET/LTTng | Experiments 1, 2 |
| `ros2_single_node_replayer` | Experiment 2 |
| Linux `perf` | Experiment 3 |
| Rust toolchain + Clang 19 | Experiment 4 |
| `miniperf` (built from source) | Experiment 4 |
| Python 3.10+ | All experiments |
| `pandas matplotlib pyyaml numpy` | All experiments |
| `mpld3` (optional) | Experiment 4 (interactive HTML) |

---

## Quick Start

```bash
# ── Experiments 1–3 (existing methodology) ──────────────────────────────
cd 1_caret_tracing && ./run_caret_trace.sh
./analyze_caret_results.sh && python3 visualize_caret.py && python3 export_node_latency.py

cd ../2_single_node_isolation
./collect_node_info.sh        # while Autoware is active
python3 merge_latency_with_info.py
./isolate_top_nodes.sh 15

cd ../3_perf_profiling
./run_perf_clusters.sh        # --generic-only for quick start
python3 clean_perf_data.py && python3 analyze_perf.py
python3 compute_agnostic_metrics.py

# ── Experiment 4 (miniperf LLVM roofline) ────────────────────────────────
cd ../4_miniperf_roofline
./install_miniperf.sh                    # once only
./build_instrumented_nodes.sh all        # recompile with Clang plugin
./run_miniperf_roofline.sh all           # full roofline (two-pass)
./run_miniperf_stat.sh all               # optional: quick stat snapshot
python3 parse_miniperf_results.py
python3 plot_roofline.py

# ── Experiment 5 (cross-methodology comparison) ──────────────────────────
cd ../5_methodology_comparison
python3 compare_methodologies.py
python3 plot_comparison.py
```
