#!/usr/bin/env python3
"""
Compute Perf-Based Roofline (Dual-Estimate)
=============================================================================
Reads FP hardware counter data from the arm_fp_operations perf cluster and
computes roofline coordinates using two FLOPs estimates:

  Conservative (x4):  FLOPs = VFP_SPEC + ASE_SPEC * 4
    - Assumes FP32 SIMD (4 elements per 128-bit NEON register)
    - Does not count FMA as 2 ops
    - Paired ceiling: peak_fp32_gflops = 105.6 GFLOPs/s
    - Ridge point:    105.6 / 204.8 = 0.5156 FLOPs/byte

  FMA-adjusted (x8):  FLOPs = VFP_SPEC + ASE_SPEC * 8
    - Assumes FP32 FMA (4 elements * 2 ops per FMA instruction)
    - Paired ceiling: peak_fp32_simd_gflops = 422.4 GFLOPs/s
    - Ridge point:    422.4 / 204.8 = 2.0625 FLOPs/byte

Memory axis (shared):
  bytes_from_DRAM = ll_cache_miss_rd * 64   (cache line size)

See METRICS_DEFINITIONS.md for the full rationale and caveats.

Input:  perf_data/all_metrics.csv  (must contain r0075, r0076, ll_cache_miss_rd columns)
Output: perf_data/perf_roofline.csv

Usage: python3 compute_perf_roofline.py
=============================================================================
"""

import sys
from pathlib import Path

try:
    import pandas as pd
    import numpy as np
except ImportError as e:
    print(f"ERROR: {e}")
    print("Install with: pip install pandas numpy")
    sys.exit(1)

SCRIPT_DIR = Path(__file__).parent
METRICS_CSV = SCRIPT_DIR / "perf_data" / "all_metrics.csv"
OUTPUT_CSV = SCRIPT_DIR / "perf_data" / "perf_roofline.csv"

CACHE_LINE_SIZE = 64

# Jetson Orin AGX hardware ceilings
PEAK_FP32_GFLOPS = 105.6          # Scalar FP32 peak (12 cores * 2.2GHz * FMA)
PEAK_FP32_SIMD_GFLOPS = 422.4     # SIMD FP32 peak (12 cores * 2.2GHz * 2 pipes * 4 elem * FMA)
PEAK_MEM_BW_GBPS = 204.8          # LPDDR5 bandwidth

RIDGE_CONSERVATIVE = PEAK_FP32_GFLOPS / PEAK_MEM_BW_GBPS        # 0.5156
RIDGE_FMA = PEAK_FP32_SIMD_GFLOPS / PEAK_MEM_BW_GBPS            # 2.0625


def main():
    if not METRICS_CSV.exists():
        print(f"ERROR: {METRICS_CSV} not found. Run clean_perf_data.py first.")
        sys.exit(1)

    df = pd.read_csv(METRICS_CSV, index_col="node_name")

    required = {"r0075", "r0076"}
    available = set(df.columns)
    missing = required - available
    if missing:
        print(f"ERROR: Missing FP counter columns: {missing}")
        print(f"Available columns: {sorted(available)}")
        print("\nThe arm_fp_operations cluster has not been collected yet.")
        print("Run: ./run_perf_fp_cluster.sh all --live --duration 30")
        sys.exit(1)

    rows = []
    for node, r in df.iterrows():
        ase_spec = r.get("r0075", 0) or 0
        vfp_spec = r.get("r0076", 0) or 0
        inst_retired = r.get("armv8_cortex_a78/inst_retired/", r.get("instructions", 0)) or 0
        ll_cache_miss = r.get("armv8_cortex_a78/ll_cache_miss_rd/", r.get("cache-misses", 0)) or 0
        task_clock_ms = r.get("task-clock", 0) or 0

        if ll_cache_miss == 0 or (ase_spec + vfp_spec) == 0:
            print(f"  SKIP: {node} (zero FP ops or zero LLC misses)")
            continue

        bytes_from_dram = ll_cache_miss * CACHE_LINE_SIZE
        wall_time_s = task_clock_ms / 1000.0 if task_clock_ms > 0 else 1.0

        flops_conservative = vfp_spec + ase_spec * 4
        flops_fma = vfp_spec + ase_spec * 8

        ai_conservative = flops_conservative / bytes_from_dram
        ai_fma = flops_fma / bytes_from_dram

        perf_gflops_conservative = (flops_conservative / 1e9) / wall_time_s
        perf_gflops_fma = (flops_fma / 1e9) / wall_time_s

        bound_conservative = "Memory" if ai_conservative < RIDGE_CONSERVATIVE else "Compute"
        bound_fma = "Memory" if ai_fma < RIDGE_FMA else "Compute"

        fp_fraction = (vfp_spec + ase_spec) / inst_retired if inst_retired > 0 else 0
        simd_fraction = ase_spec / (vfp_spec + ase_spec) if (vfp_spec + ase_spec) > 0 else 0

        rows.append({
            "node_name": node,
            "ASE_SPEC": int(ase_spec),
            "VFP_SPEC": int(vfp_spec),
            "ll_cache_miss_rd": int(ll_cache_miss),
            "bytes_from_DRAM": int(bytes_from_dram),
            "wall_time_s": round(wall_time_s, 3),
            "FLOPs_conservative": int(flops_conservative),
            "FLOPs_fma": int(flops_fma),
            "AI_conservative": round(ai_conservative, 4),
            "AI_fma": round(ai_fma, 4),
            "perf_gflops_conservative": round(perf_gflops_conservative, 4),
            "perf_gflops_fma": round(perf_gflops_fma, 4),
            "bound_conservative": bound_conservative,
            "bound_fma": bound_fma,
            "fp_fraction": round(fp_fraction, 4),
            "simd_fraction": round(simd_fraction, 4),
        })

    if not rows:
        print("ERROR: No nodes had valid FP counter data.")
        sys.exit(1)

    df_out = pd.DataFrame(rows)
    OUTPUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    df_out.to_csv(OUTPUT_CSV, index=False)

    print(f"\nSaved: {OUTPUT_CSV} ({len(df_out)} nodes)")
    print(f"\nRidge points:")
    print(f"  Conservative (FP32, no FMA): {RIDGE_CONSERVATIVE:.4f} FLOPs/byte")
    print(f"  FMA-adjusted (FP32 + FMA):   {RIDGE_FMA:.4f} FLOPs/byte")
    print(f"\nRoofline preview:")
    print(df_out[["node_name", "AI_conservative", "AI_fma",
                   "bound_conservative", "bound_fma",
                   "fp_fraction", "simd_fraction"]].to_string(index=False))


if __name__ == "__main__":
    main()
