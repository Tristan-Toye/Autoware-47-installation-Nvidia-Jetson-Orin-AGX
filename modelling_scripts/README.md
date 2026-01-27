# Autoware Performance Modelling Scripts

This folder contains a comprehensive set of scripts for performance modelling of the Autoware stack.

## Structure

```
modelling_scripts/
├── 1_caret_tracing/          # CARET-based latency analysis
├── 2_single_node_isolation/  # Isolate nodes for profiling
└── 3_perf_profiling/         # perf-based performance analysis
```

## Workflow Overview

### Step 1: CARET Tracing (`1_caret_tracing/`)
1. Run Autoware with CARET tracing enabled
2. Analyze trace data and generate visualizations
3. Export node latency rankings to CSV

### Step 2: Single Node Isolation (`2_single_node_isolation/`)
1. Collect node metadata while Autoware is running
2. Merge latency data with node info
3. Isolate top N latency nodes using ros2_single_node_replayer

### Step 3: Perf Profiling (`3_perf_profiling/`)
1. Run perf on isolated nodes with clustered metrics
2. Clean and analyze perf data
3. Compute architecture-agnostic metrics

## Prerequisites

- Autoware installed and built with CARET support
- ros2_single_node_replayer installed
- Python 3 with packages: pandas, matplotlib, bokeh, pyyaml
- perf tool available on the system

## Quick Start

```bash
# 1. Run CARET tracing
cd 1_caret_tracing && ./run_caret_trace.sh

# 2. Analyze results
./analyze_caret_results.sh
python3 visualize_caret.py
python3 export_node_latency.py

# 3. Isolate top nodes
cd ../2_single_node_isolation
./collect_node_info.sh  # Run while Autoware is active
python3 merge_latency_with_info.py
./isolate_top_nodes.sh 10

# 4. Run perf profiling
cd ../3_perf_profiling
./run_perf_clusters.sh
python3 analyze_perf.py
```
