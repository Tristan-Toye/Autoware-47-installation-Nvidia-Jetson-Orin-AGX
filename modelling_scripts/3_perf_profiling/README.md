# Perf Profiling

This folder contains scripts for running `perf` on isolated ROS 2 nodes and analyzing the results.

## Workflow

### Step 1: Run Perf Clusters
```bash
./run_perf_clusters.sh [node_name|all] [options]
```
Options:
- `--arm-only`: Only ARM-specific metrics
- `--generic-only`: Only generic metrics
- `--cluster NAME`: Specific cluster only

### Step 2: Clean Data
```bash
python3 clean_perf_data.py
```
Parses raw perf output into CSVs.

### Step 3: Analyze
```bash
python3 analyze_perf.py
python3 compute_agnostic_metrics.py
```

## Configuration

Edit `perf_config.yaml` to customize:
- Metric clusters (groups of related events)
- ARM Cortex-A78 specific events
- Derived metric formulas

## Output Structure

```
perf_data/
├── raw/                    # Raw perf stat output
│   └── <node>/
│       ├── core_execution.txt
│       ├── cache_l1_data.txt
│       └── ...
├── all_metrics.csv         # Combined raw metrics
├── derived_metrics.csv     # IPC, miss rates, MPKI
├── agnostic_metrics.csv    # Architecture-independent metrics
└── visualizations/
    ├── ipc_comparison.png
    ├── cache_miss_rates.png
    ├── mpki_heatmap.png
    └── ...
```

## Metrics

### Derived Metrics
- **IPC**: Instructions Per Cycle
- **Miss Rates**: L1D, L1I, LLC, TLB
- **MPKI**: Misses Per Kilo-Instruction

### Architecture-Agnostic Metrics
- **Arithmetic Intensity**: Operations per byte (roofline model)
- **Working Set**: Estimated from TLB behavior
- **Bottleneck Classification**: Memory/compute/cache/branches

## Tips

- Use `--generic-only` first to verify perf works
- Some ARM events may require kernel support
- Run multiple times for statistical significance
