#!/usr/bin/env python3
"""
Cross-Methodology Comparison Plots
=============================================================================
Generates visualisations comparing three performance analysis approaches
applied to the same Autoware ROS 2 nodes:

  1. CARET tracing   → node callback latency ranking
  2. perf agnostic   → ops/byte arithmetic intensity proxy
  3. miniperf roofline → LLVM IR direct arithmetic intensity

Plots produced:
  graphs/01_latency_vs_ai.png      — CARET latency rank vs miniperf AI
  graphs/02_ai_method_comparison.png — perf ops/byte vs miniperf AI
  graphs/03_bottleneck_agreement.png — stacked bar of classification agreement
  graphs/04_caret_vs_ai_scatter.png  — latency_ms vs arithmetic intensity
  graphs/05_combined_dashboard.png   — 2×2 overview dashboard

Usage: python3 plot_comparison.py
=============================================================================
"""

import sys
from pathlib import Path

try:
    import pandas as pd
    import numpy as np
    import matplotlib
    import matplotlib.pyplot as plt
    import matplotlib.gridspec as gridspec
    from matplotlib.colors import Normalize
    import matplotlib.cm as cm
except ImportError as e:
    print(f"ERROR: {e}")
    print("Install with: pip install pandas numpy matplotlib")
    sys.exit(1)

SCRIPT_DIR = Path(__file__).parent
DATA_DIR   = SCRIPT_DIR / "results"
GRAPHS_DIR = SCRIPT_DIR / "graphs"

# Consistent dark palette
BG_COLOR   = "#1a1a2e"
AX_COLOR   = "#16213e"
TEXT_COLOR = "white"
GRID_COLOR = "#2a2a4a"

BOUND_PALETTE = {
    "memory":  "#e74c3c",
    "cache":   "#f39c12",
    "compute": "#2ecc71",
    "branch":  "#9b59b6",
    "unknown": "#7f8c8d",
}

matplotlib.rcParams.update({
    "text.color":       TEXT_COLOR,
    "axes.labelcolor":  TEXT_COLOR,
    "xtick.color":      TEXT_COLOR,
    "ytick.color":      TEXT_COLOR,
    "figure.facecolor": BG_COLOR,
    "axes.facecolor":   AX_COLOR,
    "axes.edgecolor":   "#444466",
    "grid.color":       GRID_COLOR,
    "grid.linewidth":   0.5,
    "font.family":      "sans-serif",
})


def load_comparison() -> pd.DataFrame:
    p = DATA_DIR / "comparison_table.csv"
    if not p.exists():
        print(f"ERROR: comparison_table.csv not found: {p}")
        print("Run compare_methodologies.py first.")
        sys.exit(1)
    return pd.read_csv(p, index_col=0)


def node_label(name: str, max_len: int = 20) -> str:
    short = str(name).split("/")[-1]
    return short[:max_len] + "…" if len(short) > max_len else short


# ---------------------------------------------------------------------------
# Plot 1: CARET Latency Rank vs miniperf Arithmetic Intensity
# ---------------------------------------------------------------------------

def plot_latency_vs_ai(df: pd.DataFrame, out: Path) -> None:
    needed = ["caret_rank", "mperf_arithmetic_intensity"]
    sub = df.dropna(subset=[c for c in needed if c in df.columns])
    if sub.empty or len([c for c in needed if c in sub.columns]) < 2:
        print(f"  Skipping {out.name}: insufficient data")
        return

    fig, ax = plt.subplots(figsize=(12, 7))

    colors = [BOUND_PALETTE.get(str(b).lower(), BOUND_PALETTE["unknown"])
              for b in sub.get("mperf_bottleneck", ["unknown"] * len(sub))]

    sc = ax.scatter(sub["mperf_arithmetic_intensity"], sub["caret_rank"],
                    c=colors, s=120, edgecolors="white", linewidths=0.7, zorder=3)

    for node, row in sub.iterrows():
        ax.annotate(node_label(node),
                    xy=(row["mperf_arithmetic_intensity"], row["caret_rank"]),
                    xytext=(5, 3), textcoords="offset points",
                    fontsize=7.5, color=TEXT_COLOR, alpha=0.9)

    ax.set_xlabel("Arithmetic Intensity (FLOPs/byte)  [miniperf]", fontsize=11)
    ax.set_ylabel("CARET Latency Rank  (1 = highest latency)", fontsize=11)
    ax.invert_yaxis()
    ax.set_xscale("log")
    ax.set_title("CARET Latency Rank vs miniperf Arithmetic Intensity\n"
                 "Nodes in the top-left are both high-latency and memory-bound",
                 fontsize=12)
    ax.grid(True, alpha=0.4)

    # Legend
    from matplotlib.patches import Patch
    handles = [Patch(color=v, label=k.capitalize()) for k, v in BOUND_PALETTE.items()
               if k != "unknown"]
    ax.legend(handles=handles, loc="upper right",
              facecolor=AX_COLOR, edgecolor="#444466", labelcolor=TEXT_COLOR, fontsize=8)

    plt.tight_layout()
    fig.savefig(out, dpi=170, bbox_inches="tight", facecolor=fig.get_facecolor())
    plt.close()
    print(f"  Saved: {out.name}")


# ---------------------------------------------------------------------------
# Plot 2: perf ops/byte vs miniperf AI — same metric, two methods
# ---------------------------------------------------------------------------

def plot_ai_method_comparison(df: pd.DataFrame, out: Path) -> None:
    needed = ["perf_ops_per_byte", "mperf_arithmetic_intensity"]
    sub = df.dropna(subset=[c for c in needed if c in df.columns])
    if len([c for c in needed if c in sub.columns]) < 2 or sub.empty:
        print(f"  Skipping {out.name}: insufficient data (need both perf and miniperf results)")
        return

    fig, ax = plt.subplots(figsize=(11, 9))

    x = sub["perf_ops_per_byte"]
    y = sub["mperf_arithmetic_intensity"]

    # Colour by whether both methods agree on bind type
    colors = []
    for node, row in sub.iterrows():
        pb = str(row.get("perf_bottleneck", "")).lower()
        mb = str(row.get("mperf_bottleneck", "")).lower()
        colors.append("#2ecc71" if pb == mb else "#e74c3c")

    ax.scatter(x, y, c=colors, s=130, edgecolors="white", linewidths=0.7, zorder=3)
    for node, row in sub.iterrows():
        ax.annotate(node_label(node),
                    xy=(row["perf_ops_per_byte"], row["mperf_arithmetic_intensity"]),
                    xytext=(5, 3), textcoords="offset points",
                    fontsize=7.5, color=TEXT_COLOR, alpha=0.9)

    # Perfect correlation reference line
    lim_min = min(x.min(), y.min()) * 0.5
    lim_max = max(x.max(), y.max()) * 2
    ax.plot([lim_min, lim_max], [lim_min, lim_max],
            color="#7f8c8d", linestyle="--", linewidth=1, alpha=0.6,
            label="Perfect agreement (y = x)")

    ax.set_xlabel("perf ops/byte  (LLC-miss proxy, Experiment 3)", fontsize=11)
    ax.set_ylabel("miniperf Arithmetic Intensity  (LLVM IR, Experiment 4)", fontsize=11)
    ax.set_xscale("log"); ax.set_yscale("log")
    ax.set_title("Arithmetic Intensity: perf (LLC proxy) vs miniperf (LLVM IR)\n"
                 "Green = methods agree on bottleneck class | Red = disagree",
                 fontsize=11)
    ax.grid(True, which="both", alpha=0.4)
    ax.legend(facecolor=AX_COLOR, edgecolor="#444466", labelcolor=TEXT_COLOR, fontsize=8)
    plt.tight_layout()
    fig.savefig(out, dpi=170, bbox_inches="tight", facecolor=fig.get_facecolor())
    plt.close()
    print(f"  Saved: {out.name}")


# ---------------------------------------------------------------------------
# Plot 3: Stacked bar — bottleneck classification by method
# ---------------------------------------------------------------------------

def plot_bottleneck_distribution(df: pd.DataFrame, out: Path) -> None:
    methods = {
        "perf (Exp. 3)":     "perf_bottleneck",
        "miniperf (Exp. 4)": "mperf_bottleneck",
    }
    available = {k: v for k, v in methods.items() if v in df.columns}
    if not available:
        print(f"  Skipping {out.name}: no bottleneck columns available")
        return

    bounds = ["memory", "cache", "compute", "branch", "unknown"]
    x = np.arange(len(available))
    bar_width = 0.55

    fig, ax = plt.subplots(figsize=(9, 6))
    bottoms = np.zeros(len(available))

    for bound in bounds:
        heights = []
        for method_col in available.values():
            series = df[method_col].dropna().str.lower()
            heights.append((series == bound).sum())
        bars = ax.bar(x, heights, bar_width, bottom=bottoms,
                      color=BOUND_PALETTE.get(bound, "#cccccc"), label=bound.capitalize())
        bottoms += np.array(heights, dtype=float)

        # Label inside bar if large enough
        for xi, h in zip(x, heights):
            if h > 0:
                ax.text(xi, bottoms[xi] - h / 2, str(int(h)),
                        ha="center", va="center", fontsize=9, color="white", fontweight="bold")

    ax.set_xticks(x)
    ax.set_xticklabels(list(available.keys()), fontsize=10)
    ax.set_ylabel("Number of Nodes", fontsize=11)
    ax.set_title("Bottleneck Classification Distribution by Method", fontsize=12)
    ax.legend(loc="upper right",
              facecolor=AX_COLOR, edgecolor="#444466", labelcolor=TEXT_COLOR, fontsize=9)
    ax.grid(axis="y", alpha=0.4)
    plt.tight_layout()
    fig.savefig(out, dpi=170, bbox_inches="tight", facecolor=fig.get_facecolor())
    plt.close()
    print(f"  Saved: {out.name}")


# ---------------------------------------------------------------------------
# Plot 4: CARET latency_ms vs arithmetic intensity (scatter with node labels)
# ---------------------------------------------------------------------------

def plot_latency_ms_vs_ai(df: pd.DataFrame, out: Path) -> None:
    needed = ["caret_latency_ms", "mperf_arithmetic_intensity"]
    sub = df.dropna(subset=[c for c in needed if c in df.columns])
    if len([c for c in needed if c in sub.columns]) < 2 or sub.empty:
        print(f"  Skipping {out.name}: insufficient data")
        return

    fig, ax = plt.subplots(figsize=(12, 7))

    norm = Normalize(vmin=sub["caret_latency_ms"].min(),
                     vmax=sub["caret_latency_ms"].max())
    cmap = cm.plasma

    sc = ax.scatter(sub["mperf_arithmetic_intensity"],
                    sub["caret_latency_ms"],
                    c=sub["caret_latency_ms"], cmap=cmap, norm=norm,
                    s=130, edgecolors="white", linewidths=0.7, zorder=3)

    for node, row in sub.iterrows():
        ax.annotate(node_label(node),
                    xy=(row["mperf_arithmetic_intensity"], row["caret_latency_ms"]),
                    xytext=(5, 3), textcoords="offset points",
                    fontsize=7.5, color=TEXT_COLOR, alpha=0.9)

    cbar = fig.colorbar(sc, ax=ax, pad=0.01)
    cbar.set_label("CARET Latency (ms)", color=TEXT_COLOR)
    cbar.ax.yaxis.set_tick_params(color=TEXT_COLOR)
    plt.setp(cbar.ax.yaxis.get_ticklabels(), color=TEXT_COLOR)

    ax.set_xlabel("Arithmetic Intensity (FLOPs/byte)  [miniperf]", fontsize=11)
    ax.set_ylabel("Node Callback Latency (ms)  [CARET]", fontsize=11)
    ax.set_xscale("log")
    ax.set_title("Absolute Latency vs Arithmetic Intensity\n"
                 "High latency + low AI → memory-bound bottleneck candidates",
                 fontsize=12)
    ax.grid(True, alpha=0.4)
    plt.tight_layout()
    fig.savefig(out, dpi=170, bbox_inches="tight", facecolor=fig.get_facecolor())
    plt.close()
    print(f"  Saved: {out.name}")


# ---------------------------------------------------------------------------
# Plot 5: 2×2 Dashboard
# ---------------------------------------------------------------------------

def plot_dashboard(df: pd.DataFrame, out: Path) -> None:
    fig = plt.figure(figsize=(18, 12))
    fig.patch.set_facecolor(BG_COLOR)
    gs = gridspec.GridSpec(2, 2, figure=fig, hspace=0.38, wspace=0.3)

    axes = [fig.add_subplot(gs[r, c]) for r in range(2) for c in range(2)]
    for ax in axes:
        ax.set_facecolor(AX_COLOR)

    ax1, ax2, ax3, ax4 = axes

    # ── Panel 1: Rank vs AI ───────────────────────────────────────────────
    needed1 = ["caret_rank", "mperf_arithmetic_intensity"]
    sub1 = df.dropna(subset=[c for c in needed1 if c in df.columns])
    if not sub1.empty and len([c for c in needed1 if c in sub1.columns]) == 2:
        colors1 = [BOUND_PALETTE.get(str(b).lower(), BOUND_PALETTE["unknown"])
                   for b in sub1.get("mperf_bottleneck", ["unknown"] * len(sub1))]
        ax1.scatter(sub1["mperf_arithmetic_intensity"], sub1["caret_rank"],
                    c=colors1, s=80, edgecolors="white", linewidths=0.5)
        ax1.set_xscale("log"); ax1.invert_yaxis()
        ax1.set_xlabel("AI (FLOPs/byte)", fontsize=9)
        ax1.set_ylabel("CARET Rank", fontsize=9)
        ax1.set_title("Latency Rank vs AI", fontsize=10)
        ax1.grid(True, alpha=0.4)

    # ── Panel 2: Bottleneck distribution  ─────────────────────────────────
    bounds = ["memory", "cache", "compute", "unknown"]
    method_cols = [(m, c) for m, c in
                   [("perf", "perf_bottleneck"), ("miniperf", "mperf_bottleneck")]
                   if c in df.columns]
    if method_cols:
        x = np.arange(len(method_cols))
        bottoms = np.zeros(len(method_cols))
        for bound in bounds:
            heights = [(df[col].dropna().str.lower() == bound).sum()
                       for _, col in method_cols]
            ax2.bar(x, heights, 0.5, bottom=bottoms,
                    color=BOUND_PALETTE.get(bound, "#cccccc"), label=bound.capitalize())
            bottoms += np.array(heights, dtype=float)
        ax2.set_xticks(x)
        ax2.set_xticklabels([m for m, _ in method_cols], fontsize=9)
        ax2.set_ylabel("Count", fontsize=9)
        ax2.set_title("Bottleneck Distribution", fontsize=10)
        ax2.grid(axis="y", alpha=0.4)
        ax2.legend(fontsize=7, facecolor=AX_COLOR, edgecolor="#444466",
                   labelcolor=TEXT_COLOR)

    # ── Panel 3: perf vs miniperf AI  ─────────────────────────────────────
    needed3 = ["perf_ops_per_byte", "mperf_arithmetic_intensity"]
    sub3 = df.dropna(subset=[c for c in needed3 if c in df.columns])
    if not sub3.empty and len([c for c in needed3 if c in sub3.columns]) == 2:
        colors3 = []
        for _, row in sub3.iterrows():
            pb = str(row.get("perf_bottleneck", "")).lower()
            mb = str(row.get("mperf_bottleneck", "")).lower()
            colors3.append("#2ecc71" if pb == mb else "#e74c3c")
        ax3.scatter(sub3["perf_ops_per_byte"], sub3["mperf_arithmetic_intensity"],
                    c=colors3, s=80, edgecolors="white", linewidths=0.5)
        lim = max(sub3["perf_ops_per_byte"].max(), sub3["mperf_arithmetic_intensity"].max()) * 1.5
        ax3.plot([0, lim], [0, lim], color="#7f8c8d", linestyle="--", linewidth=1, alpha=0.5)
        ax3.set_xscale("log"); ax3.set_yscale("log")
        ax3.set_xlabel("perf ops/byte", fontsize=9)
        ax3.set_ylabel("miniperf AI", fontsize=9)
        ax3.set_title("Method Correlation\n(green=agree, red=disagree)", fontsize=10)
        ax3.grid(True, which="both", alpha=0.4)

    # ── Panel 4: Latency vs AI scatter with latency colour ───────────────
    needed4 = ["caret_latency_ms", "mperf_arithmetic_intensity"]
    sub4 = df.dropna(subset=[c for c in needed4 if c in df.columns])
    if not sub4.empty and len([c for c in needed4 if c in sub4.columns]) == 2:
        sc4 = ax4.scatter(sub4["mperf_arithmetic_intensity"],
                          sub4["caret_latency_ms"],
                          c=sub4["caret_latency_ms"], cmap="plasma",
                          s=80, edgecolors="white", linewidths=0.5)
        ax4.set_xscale("log")
        ax4.set_xlabel("AI (FLOPs/byte)", fontsize=9)
        ax4.set_ylabel("Latency (ms)", fontsize=9)
        ax4.set_title("Latency (ms) vs AI", fontsize=10)
        ax4.grid(True, alpha=0.4)

    fig.suptitle(
        "Autoware Performance Analysis — Cross-Methodology Dashboard\n"
        "CARET Tracing  ·  perf Agnostic Metrics  ·  miniperf LLVM Roofline",
        fontsize=13, color=TEXT_COLOR, y=1.01,
    )

    fig.savefig(out, dpi=160, bbox_inches="tight", facecolor=fig.get_facecolor())
    plt.close()
    print(f"  Saved: {out.name}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("Cross-Methodology Comparison Plots")
    print("=" * 60)

    GRAPHS_DIR.mkdir(parents=True, exist_ok=True)

    df = load_comparison()
    print(f"\nLoaded {len(df)} nodes from comparison_table.csv")
    print(f"Columns: {list(df.columns)}")

    print("\nGenerating plots...")
    plot_latency_vs_ai(df,         GRAPHS_DIR / "01_latency_rank_vs_ai.png")
    plot_ai_method_comparison(df,  GRAPHS_DIR / "02_ai_method_comparison.png")
    plot_bottleneck_distribution(df, GRAPHS_DIR / "03_bottleneck_distribution.png")
    plot_latency_ms_vs_ai(df,      GRAPHS_DIR / "04_latency_ms_vs_ai.png")
    plot_dashboard(df,             GRAPHS_DIR / "05_combined_dashboard.png")

    print("\n" + "=" * 60)
    print(f"All plots saved to: {GRAPHS_DIR}")
    print("=" * 60)


if __name__ == "__main__":
    main()
