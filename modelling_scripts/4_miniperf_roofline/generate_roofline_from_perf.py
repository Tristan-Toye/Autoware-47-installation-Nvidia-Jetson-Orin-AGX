#!/usr/bin/env python3
"""
Generate roofline data from perf agnostic metrics (experiment 3).
Since the LLVM IR instrumented build is not available, we use the
perf LLC-miss-based arithmetic intensity as a proxy for the roofline.
"""

import sys
from pathlib import Path

import pandas as pd
import numpy as np
import yaml

SCRIPT_DIR = Path(__file__).parent
PERF_METRICS = SCRIPT_DIR / "../3_perf_profiling/perf_data/all_metrics.csv"
AGNOSTIC_METRICS = SCRIPT_DIR / "../3_perf_profiling/perf_data/agnostic_metrics.csv"
CONFIG = SCRIPT_DIR / "miniperf_config.yaml"
RESULTS_DIR = SCRIPT_DIR / "results"

CACHE_LINE_SIZE = 64

def main():
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    with open(CONFIG) as f:
        cfg = yaml.safe_load(f)

    hw = cfg["hardware"]["cpu"]
    peak_bw = hw["peak_memory_bandwidth_GBps"]

    df = pd.read_csv(PERF_METRICS, index_col="node_name")

    rows = []
    for node, r in df.iterrows():
        instr = r.get("instructions", 0)
        cycles = r.get("cpu-cycles", 0)
        cache_misses = r.get("cache-misses", 0)
        cache_refs = r.get("cache-references", 0)
        l1_loads = r.get("L1-dcache-loads", 0)
        task_clock = r.get("task-clock", 0)

        if cache_misses == 0 or instr == 0:
            continue

        bytes_transferred = cache_misses * CACHE_LINE_SIZE
        ops_per_byte = instr / bytes_transferred if bytes_transferred > 0 else 0

        # Estimate performance in GFLOPs/s using task-clock (ms)
        wall_time_s = task_clock / 1000.0 if task_clock > 0 else 1.0
        gflops = (instr / 1e9) / wall_time_s

        bound = "Memory" if ops_per_byte < (hw["peak_fp32_gflops"] / peak_bw) else "Compute"

        rows.append({
            "node_name": node,
            "hotspot": "aggregate",
            "arithmetic_intensity": round(ops_per_byte, 4),
            "performance_gflops": round(gflops, 4),
            "bound": bound,
        })

    df_roofline = pd.DataFrame(rows)
    out = RESULTS_DIR / "miniperf_roofline.csv"
    df_roofline.to_csv(out, index=False)
    print(f"Saved: {out} ({len(df_roofline)} nodes)")

    # Aggregate (one row per node)
    df_agg = df_roofline.copy()
    df_agg = df_agg.rename(columns={
        "arithmetic_intensity": "weighted_ai",
        "performance_gflops": "max_performance_gflops",
        "bound": "dominant_bound",
    })
    df_agg["n_hotspots"] = 1
    df_agg = df_agg.drop(columns=["hotspot"]).set_index("node_name")
    out_agg = RESULTS_DIR / "miniperf_roofline_agg.csv"
    df_agg.to_csv(out_agg)
    print(f"Saved: {out_agg} ({len(df_agg)} nodes)")

    print("\nRoofline data preview:")
    print(df_roofline.to_string(index=False))


if __name__ == "__main__":
    main()
