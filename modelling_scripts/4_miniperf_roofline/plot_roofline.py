#!/usr/bin/env python3
"""
Roofline Model Plotter for Autoware Nodes (miniperf results)
=============================================================================
Generates a Roofline Model plot for the target Autoware nodes using data
collected by miniperf (parse_miniperf_results.py).

The Roofline Model (Williams et al., 2009) characterises application
performance relative to hardware limits:

  X-axis : Arithmetic Intensity (FLOPs / byte)
            How compute-dense the workload is.
            Low  → memory-bandwidth bound
            High → compute (peak FLOP rate) bound

  Y-axis : Performance (GFLOPs/s)
            Measured floating-point throughput.

The "roofline" is the minimum of:
    Performance ≤ min(Peak_FLOPS, AI × Peak_BW)

Operating well below the roofline indicates inefficiency (cache misses,
poor vectorisation, etc.). The ridge point at:
    AI_ridge = Peak_FLOPS / Peak_BW
is the transition between memory- and compute-bound regimes.

Hardware ceilings are taken from miniperf_config.yaml (Jetson Orin AGX).
Node data is coloured by CARET latency rank if the ranking CSV is present.

Usage: python3 plot_roofline.py [--no-caret] [--log-scale | --linear]
=============================================================================
"""

import sys
import argparse
from pathlib import Path

try:
    import pandas as pd
    import numpy as np
    import matplotlib
    import matplotlib.pyplot as plt
    import matplotlib.patches as mpatches
    import yaml
except ImportError as e:
    print(f"ERROR: Required package not found: {e}")
    print("Install with: pip install pandas numpy matplotlib pyyaml")
    sys.exit(1)

SCRIPT_DIR  = Path(__file__).parent
CONFIG_FILE = SCRIPT_DIR / "miniperf_config.yaml"
RESULTS_DIR = SCRIPT_DIR / "results"
GRAPHS_DIR  = SCRIPT_DIR / "graphs"
CARET_CSV   = SCRIPT_DIR / "../1_caret_tracing/results/node_latency_ranking.csv"


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

def load_config() -> dict:
    with open(CONFIG_FILE, "r") as f:
        return yaml.safe_load(f)


def get_hw_ceilings(cfg: dict) -> dict:
    hw = cfg.get("hardware", {}).get("cpu", {})
    return {
        "Peak FP32 SIMD (GFLOPs/s)": hw.get("peak_fp32_simd_gflops", 422.4),
        "Peak FP32 scalar (GFLOPs/s)": hw.get("peak_fp32_gflops", 105.6),
        "Peak FP64 scalar (GFLOPs/s)": hw.get("peak_fp64_gflops", 52.8),
        "peak_bw_GBps": cfg.get("hardware", {}).get("cpu", {}).get(
            "peak_memory_bandwidth_GBps", 204.8),
    }


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

def load_roofline_data() -> pd.DataFrame:
    agg_csv = RESULTS_DIR / "miniperf_roofline_agg.csv"
    raw_csv = RESULTS_DIR / "miniperf_roofline.csv"

    if agg_csv.exists():
        df = pd.read_csv(agg_csv, index_col="node_name")
        df.rename(columns={
            "weighted_ai":             "arithmetic_intensity",
            "max_performance_gflops":  "performance_gflops",
        }, inplace=True)
        return df

    if raw_csv.exists():
        df = pd.read_csv(raw_csv)
        # Aggregate: per node, take best hotspot by performance
        agg = (df.sort_values("performance_gflops", ascending=False)
                  .groupby("node_name")
                  .first()
                  .rename(columns={"performance_gflops": "performance_gflops",
                                   "arithmetic_intensity": "arithmetic_intensity"}))
        return agg

    return pd.DataFrame()


def load_caret_ranks() -> dict:
    """Return dict: node_name -> rank (1=highest latency)."""
    if not CARET_CSV.exists():
        return {}
    try:
        df = pd.read_csv(CARET_CSV)
        # Normalise node names (last segment of ROS 2 fully qualified name)
        ranks = {}
        for rank, row in enumerate(df.itertuples(), start=1):
            name = row.node_name.split("/")[-1] if "/" in str(row.node_name) else str(row.node_name)
            ranks[name] = rank
        return ranks
    except Exception:
        return {}


# ---------------------------------------------------------------------------
# Plot helpers
# ---------------------------------------------------------------------------

def node_label(name: str, max_len: int = 22) -> str:
    """Short display name for a node."""
    short = name.split("/")[-1]
    return short[:max_len] + "…" if len(short) > max_len else short


BOUND_COLORS = {
    "Memory":  "#e74c3c",
    "Compute": "#2ecc71",
    "unknown": "#95a5a6",
    "Cache":   "#f39c12",
}


def bound_from_ai(ai: float, ridge: float) -> str:
    if ai < ridge * 0.5:
        return "Memory"
    elif ai < ridge:
        return "Cache"
    else:
        return "Compute"


# ---------------------------------------------------------------------------
# Main plot
# ---------------------------------------------------------------------------

def plot_roofline(df: pd.DataFrame, hw: dict, use_log: bool = True,
                  show_caret: bool = True) -> None:
    """Generate the roofline model plot."""
    GRAPHS_DIR.mkdir(parents=True, exist_ok=True)

    peak_bw = hw["peak_bw_GBps"]
    ceilings = {k: v for k, v in hw.items() if k != "peak_bw_GBps"}
    peak_flops = max(ceilings.values())

    # Ridge point: where compute ceiling meets memory ceiling
    ridge_ai = peak_flops / peak_bw  # FLOPs/byte

    # Build x-axis range for the roofline
    if use_log:
        ai_min = max(0.001, df["arithmetic_intensity"].min() * 0.1) if not df.empty else 0.01
        ai_max = max(ridge_ai * 10, df["arithmetic_intensity"].max() * 10) if not df.empty else ridge_ai * 10
        ai_range = np.logspace(np.log10(ai_min), np.log10(ai_max), 500)
    else:
        ai_min = 0
        ai_max = max(ridge_ai * 3, (df["arithmetic_intensity"].max() * 1.5) if not df.empty else ridge_ai * 3)
        ai_range = np.linspace(0.001, ai_max, 500)

    fig, ax = plt.subplots(figsize=(14, 9))
    fig.patch.set_facecolor("#1a1a2e")
    ax.set_facecolor("#16213e")

    # ── Draw roofline ceilings ──────────────────────────────────────────────
    ceiling_colors = ["#00d4ff", "#00a8cc", "#007299"]
    for i, (ceil_name, ceil_val) in enumerate(sorted(ceilings.items(),
                                                       key=lambda x: -x[1])):
        roofline = np.minimum(ceil_val, ai_range * peak_bw)
        lw = 2.5 if i == 0 else 1.5
        ls = "-" if i == 0 else "--"
        cc = ceiling_colors[min(i, len(ceiling_colors) - 1)]
        ax.plot(ai_range, roofline, color=cc, linewidth=lw, linestyle=ls,
                label=f"{ceil_name}: {ceil_val:.0f} GFLOPs/s", zorder=3)

    # Ridge point annotation
    ax.axvline(ridge_ai, color="#f39c12", linewidth=1.2, linestyle=":",
               alpha=0.7, zorder=2)
    ax.text(ridge_ai * 1.05, peak_flops * 0.6,
            f"Ridge\n{ridge_ai:.1f} FLOPs/B",
            color="#f39c12", fontsize=8, va="center")

    # ── Memory bandwidth slope label ─────────────────────────────────────────
    slope_x = ai_range[int(len(ai_range) * 0.05)]
    slope_y = slope_x * peak_bw
    ax.text(slope_x * 1.5, slope_y * 0.7,
            f"Memory BW\n{peak_bw:.0f} GB/s",
            color="#00d4ff", fontsize=8, alpha=0.8, rotation=30)

    # ── Plot node data points ────────────────────────────────────────────────
    if not df.empty:
        caret_ranks = load_caret_ranks() if show_caret else {}
        max_rank = max(caret_ranks.values()) if caret_ranks else 1

        for node_name, row in df.iterrows():
            ai   = row.get("arithmetic_intensity", np.nan)
            perf = row.get("performance_gflops",  np.nan)

            if pd.isna(ai) or pd.isna(perf) or ai <= 0 or perf <= 0:
                continue

            # Determine colour: from CARET rank if available, else from bound
            short_name = node_label(node_name)
            caret_rank = caret_ranks.get(node_name, caret_ranks.get(short_name, None))

            if caret_rank and show_caret:
                # Red (high latency) → green (low latency)
                t = (caret_rank - 1) / max(max_rank - 1, 1)
                color = plt.cm.RdYlGn(1 - t)
            else:
                bound = row.get("dominant_bound",
                                bound_from_ai(ai, ridge_ai))
                color = BOUND_COLORS.get(bound, "#95a5a6")

            ax.scatter(ai, perf, s=140, color=color, edgecolors="white",
                       linewidths=0.8, zorder=5)
            ax.annotate(
                short_name,
                xy=(ai, perf),
                xytext=(6, 4),
                textcoords="offset points",
                fontsize=7.5,
                color="white",
                alpha=0.9,
                zorder=6,
            )

    # ── Cache size reference lines (AI where footprint fits in each cache) ──
    cfg = load_config()
    cache = cfg.get("hardware", {}).get("cache", {})
    cache_refs = [
        (cache.get("l1d_size_KB", 64)    * 1024, "L1d"),
        (cache.get("l2_size_KB", 512)    * 1024, "L2"),
        (cache.get("l3_size_MB", 4) * 1024 * 1024, "L3"),
    ]
    for size_bytes, label in cache_refs:
        # Rough AI at which working set fills this cache level
        ref_ai = 1.0 / (size_bytes / 1e9)  # illustrative only
        if ai_min < ref_ai < ai_max:
            ax.axvline(ref_ai, color="#555577", linewidth=0.8,
                       linestyle=":", alpha=0.5, zorder=1)
            ax.text(ref_ai, peak_flops * 0.05, label,
                    color="#7777aa", fontsize=7, ha="center")

    # ── Axes & styling ─────────────────────────────────────────────────────
    if use_log:
        ax.set_xscale("log")
        ax.set_yscale("log")

    ax.set_xlabel("Arithmetic Intensity (FLOPs / byte)", color="white",
                  fontsize=12, labelpad=8)
    ax.set_ylabel("Performance (GFLOPs/s)", color="white",
                  fontsize=12, labelpad=8)
    ax.set_title(
        "Roofline Model — Autoware ROS 2 Nodes\n"
        "Nvidia Jetson Orin AGX  |  miniperf LLVM IR Instrumentation",
        color="white", fontsize=13, pad=14,
    )
    ax.tick_params(colors="white")
    for spine in ax.spines.values():
        spine.set_edgecolor("#444466")

    # ── Legend ─────────────────────────────────────────────────────────────
    legend_handles = [
        mpatches.Patch(color="#e74c3c", label="Memory-bound  (AI < ridge/2)"),
        mpatches.Patch(color="#f39c12", label="Cache-bound   (ridge/2 ≤ AI < ridge)"),
        mpatches.Patch(color="#2ecc71", label="Compute-bound (AI ≥ ridge)"),
    ]
    if not df.empty and caret_ranks and show_caret:
        legend_handles.append(
            mpatches.Patch(color="grey",
                           label="Node colour = CARET latency rank (red=high)"))
    ax.legend(
        handles=legend_handles,
        loc="lower right",
        facecolor="#1a1a2e",
        edgecolor="#555577",
        labelcolor="white",
        fontsize=8,
    )

    ax.grid(True, which="both", color="#2a2a4a", linewidth=0.5, alpha=0.6)

    plt.tight_layout()

    # ── Save outputs ────────────────────────────────────────────────────────
    png_out = GRAPHS_DIR / "roofline_plot.png"
    plt.savefig(png_out, dpi=180, bbox_inches="tight", facecolor=fig.get_facecolor())
    print(f"  Saved: {png_out}")

    # Try interactive HTML via mpld3 if available (optional dependency)
    try:
        import mpld3
        html_out = GRAPHS_DIR / "roofline_interactive.html"
        mpld3.save_html(fig, str(html_out))
        print(f"  Saved: {html_out}  (interactive)")
    except Exception:
        print("  (mpld3 interactive HTML skipped due to compatibility issue)")

    plt.close()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Plot miniperf roofline model")
    parser.add_argument("--no-caret", action="store_true",
                        help="Do not colour by CARET latency rank")
    parser.add_argument("--linear", action="store_true",
                        help="Use linear axes instead of log-log")
    args = parser.parse_args()

    print("=" * 60)
    print("Roofline Model Plotter")
    print("=" * 60)

    cfg = load_config()
    hw  = get_hw_ceilings(cfg)

    print(f"\nHardware: {cfg.get('hardware', {}).get('name', 'unknown')}")
    for name, val in hw.items():
        if name != "peak_bw_GBps":
            print(f"  {name}: {val} GFLOPs/s")
    print(f"  Peak BW: {hw['peak_bw_GBps']} GB/s")
    print(f"  Ridge point: {hw[max(hw, key=lambda k: hw[k] if k!='peak_bw_GBps' else 0)] / hw['peak_bw_GBps']:.2f} FLOPs/byte")

    print("\nLoading roofline data...")
    df = load_roofline_data()
    if df.empty:
        print("  No roofline data found.")
        print("  Run run_miniperf_roofline.sh → parse_miniperf_results.py first.")
        print("  Generating plot with hardware ceilings only...")
    else:
        print(f"  Loaded {len(df)} nodes")

    print("\nGenerating roofline plot...")
    plot_roofline(df, hw,
                  use_log=not args.linear,
                  show_caret=not args.no_caret)

    print("\n" + "=" * 60)
    print("Plots saved to:", GRAPHS_DIR)
    print("=" * 60)


if __name__ == "__main__":
    main()
