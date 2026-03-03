#!/usr/bin/env python3
"""
Cross-Methodology Comparison
=============================================================================
Loads results from all three performance analysis experiments and produces
a unified comparison table showing how well the methods agree on bottleneck
classification for each Autoware node.

Data sources:
  Experiment 1 (CARET tracing):
    ../1_caret_tracing/results/node_latency_ranking.csv
    Columns: node_name, latency_ms, percentage_of_total

  Experiment 3 (perf agnostic metrics):
    ../3_perf_profiling/perf_data/agnostic_metrics.csv
    Columns: node_name, ops_per_byte, overall_cache_hit_rate_%, primary_bottleneck

  Experiment 4 (miniperf roofline):
    ../4_miniperf_roofline/results/miniperf_roofline_agg.csv
    Columns: node_name, weighted_ai, max_performance_gflops, dominant_bound

Output files:
  results/comparison_table.csv      — per-node side-by-side metrics
  results/bottleneck_agreement.csv  — agreement matrix between methods
  results/methodology_summary.md    — auto-generated markdown summary
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
BASE       = SCRIPT_DIR / ".."
OUTPUT_DIR = SCRIPT_DIR / "results"

# ── Input paths ──────────────────────────────────────────────────────────────
CARET_CSV   = BASE / "1_caret_tracing/results/node_latency_ranking.csv"
PERF_CSV    = BASE / "3_perf_profiling/perf_data/agnostic_metrics.csv"
MPERF_CSV   = BASE / "4_miniperf_roofline/results/miniperf_roofline_agg.csv"
MPERF_STAT  = BASE / "4_miniperf_roofline/results/miniperf_stat.csv"


# ---------------------------------------------------------------------------
# Bottleneck normalisation
# ---------------------------------------------------------------------------

def normalise_bottleneck(label: str | float) -> str:
    """Map diverse bottleneck strings to a canonical 3-class label."""
    if pd.isna(label):
        return "unknown"
    s = str(label).lower().strip()
    if any(k in s for k in ("memory", "mem", "bandwidth", "bw")):
        return "memory"
    if any(k in s for k in ("compute", "flop", "cpu")):
        return "compute"
    if any(k in s for k in ("cache", "llc", "l1", "l2", "l3")):
        return "cache"
    if any(k in s for k in ("branch",)):
        return "branch"
    return "unknown"


def bottleneck_from_ai(ai: float, ridge: float = 2.1) -> str:
    """Classify from arithmetic intensity alone (experiment 4 fallback)."""
    if pd.isna(ai) or ai <= 0:
        return "unknown"
    if ai < ridge * 0.5:
        return "memory"
    if ai < ridge:
        return "cache"
    return "compute"


def bottleneck_from_ops_per_byte(ops: float) -> str:
    """Classify using experiment 3 ops_per_byte threshold (10 = boundary)."""
    if pd.isna(ops):
        return "unknown"
    if ops < 5:
        return "memory"
    if ops < 10:
        return "cache"
    return "compute"


# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------

def load_caret() -> pd.DataFrame:
    if not CARET_CSV.exists():
        print(f"  WARNING: CARET CSV not found: {CARET_CSV}")
        return pd.DataFrame()
    df = pd.read_csv(CARET_CSV)
    # Normalise node names (take last path segment for matching)
    df["node_short"] = df["node_name"].apply(
        lambda n: str(n).split("/")[-1])
    df = df.rename(columns={
        "latency_ms":          "caret_latency_ms",
        "percentage_of_total": "caret_pct_total",
    })
    df["caret_rank"] = range(1, len(df) + 1)
    df = df.set_index("node_short")
    return df[["caret_latency_ms", "caret_pct_total", "caret_rank"]]


def load_perf() -> pd.DataFrame:
    if not PERF_CSV.exists():
        print(f"  WARNING: perf CSV not found: {PERF_CSV}")
        return pd.DataFrame()
    df = pd.read_csv(PERF_CSV, index_col="node_name")
    df.index = df.index.map(lambda n: str(n).split("/")[-1])
    keep = {
        "ops_per_byte":                "perf_ops_per_byte",
        "overall_cache_hit_rate_%":    "perf_cache_hit_rate",
        "primary_bottleneck":          "perf_raw_bottleneck",
    }
    df = df[[c for c in keep if c in df.columns]].rename(columns=keep)
    if "perf_raw_bottleneck" in df.columns:
        df["perf_bottleneck"] = df["perf_raw_bottleneck"].apply(normalise_bottleneck)
    elif "perf_ops_per_byte" in df.columns:
        df["perf_bottleneck"] = df["perf_ops_per_byte"].apply(bottleneck_from_ops_per_byte)
    return df


def load_mperf() -> pd.DataFrame:
    if not MPERF_CSV.exists():
        print(f"  WARNING: miniperf roofline CSV not found: {MPERF_CSV}")
        return pd.DataFrame()
    df = pd.read_csv(MPERF_CSV, index_col="node_name")
    df.index = df.index.map(lambda n: str(n).split("/")[-1])
    rename = {
        "weighted_ai":             "mperf_arithmetic_intensity",
        "max_performance_gflops":  "mperf_peak_gflops",
        "dominant_bound":          "mperf_raw_bound",
        "n_hotspots":              "mperf_n_hotspots",
    }
    df = df[[c for c in rename if c in df.columns]].rename(columns=rename)

    # Classify from AI if explicit bound is missing
    if "mperf_raw_bound" in df.columns:
        df["mperf_bottleneck"] = df["mperf_raw_bound"].apply(normalise_bottleneck)
    elif "mperf_arithmetic_intensity" in df.columns:
        df["mperf_bottleneck"] = df["mperf_arithmetic_intensity"].apply(
            lambda x: bottleneck_from_ai(x, ridge=2.1))
    return df


# ---------------------------------------------------------------------------
# Agreement analysis
# ---------------------------------------------------------------------------

def compute_agreement(df: pd.DataFrame) -> pd.DataFrame:
    """
    Compute pairwise bottleneck agreement between methods.
    Returns a summary row with agreement rates.
    """
    results = []
    pairs = [
        ("perf_bottleneck",  "mperf_bottleneck",  "perf_vs_mperf"),
        ("perf_bottleneck",  "caret_rank",         "perf_uses_caret_top10"),
        ("mperf_bottleneck", "caret_rank",         "mperf_uses_caret_top10"),
    ]

    valid = df.dropna(subset=["perf_bottleneck", "mperf_bottleneck"], how="all")

    for col_a, col_b, label in pairs:
        if col_a not in valid.columns or col_b not in valid.columns:
            continue
        if col_b == "caret_rank":
            # Agreement metric: are nodes ranked top-10 by CARET also marked
            # memory/cache bound by the other method?
            top10 = valid[valid["caret_rank"] <= 10]
            bound_col = col_a
            if bound_col in top10.columns:
                n_mem_cache = top10[bound_col].isin(["memory", "cache"]).sum()
                pct = n_mem_cache / len(top10) * 100 if len(top10) > 0 else float("nan")
                results.append({
                    "comparison":            label,
                    "description":           f"% of CARET top-10 nodes labelled mem/cache by {col_a}",
                    "total_nodes":           len(top10),
                    "agreeing_nodes":        int(n_mem_cache),
                    "agreement_rate_%":      round(pct, 1),
                })
        else:
            sub = valid[[col_a, col_b]].dropna()
            agree = (sub[col_a] == sub[col_b]).sum()
            total = len(sub)
            pct = agree / total * 100 if total > 0 else float("nan")
            results.append({
                "comparison":       label,
                "description":      f"Nodes where {col_a} == {col_b}",
                "total_nodes":      total,
                "agreeing_nodes":   int(agree),
                "agreement_rate_%": round(pct, 1),
            })

    return pd.DataFrame(results)


# ---------------------------------------------------------------------------
# Markdown summary generation
# ---------------------------------------------------------------------------

def generate_markdown_summary(df: pd.DataFrame, agreement: pd.DataFrame) -> str:
    """Generate a human-readable markdown summary of the comparison."""
    lines = [
        "# Cross-Methodology Bottleneck Comparison Summary",
        "",
        "Auto-generated by `compare_methodologies.py`.",
        "",
        "## Per-Node Comparison Table",
        "",
        "| Node | CARET Rank | CARET Latency (ms) | perf Bottleneck | miniperf AI (FLOPs/B) | miniperf Bottleneck |",
        "|---|---|---|---|---|---|",
    ]

    sort_df = df.sort_values("caret_rank") if "caret_rank" in df.columns else df
    for node, row in sort_df.iterrows():
        rank   = f"{int(row['caret_rank'])}" if "caret_rank" in row and pd.notna(row["caret_rank"]) else "–"
        lat    = f"{row['caret_latency_ms']:.2f}" if "caret_latency_ms" in row and pd.notna(row["caret_latency_ms"]) else "–"
        pb     = row.get("perf_bottleneck", "–")
        ai     = f"{row['mperf_arithmetic_intensity']:.3f}" if "mperf_arithmetic_intensity" in row and pd.notna(row.get("mperf_arithmetic_intensity")) else "–"
        mb     = row.get("mperf_bottleneck", "–")
        lines.append(f"| `{node}` | {rank} | {lat} | {pb} | {ai} | {mb} |")

    lines += [
        "",
        "## Method Agreement Rates",
        "",
        "| Comparison | Total Nodes | Agreeing | Agreement Rate |",
        "|---|---|---|---|",
    ]

    for _, arow in agreement.iterrows():
        label = arow.get("comparison", "")
        total = int(arow.get("total_nodes", 0))
        agree = int(arow.get("agreeing_nodes", 0))
        rate  = f"{arow.get('agreement_rate_%', 0):.1f}%"
        lines.append(f"| {label} | {total} | {agree} | {rate} |")

    lines += [
        "",
        "## Interpretation",
        "",
        "- **High agreement between perf and miniperf** (>70%) supports the",
        "  validity of both measurement approaches.",
        "- **Nodes that appear in CARET top-10 AND are memory/cache-bound**",
        "  are the highest-priority optimization targets: they contribute",
        "  significantly to system latency *and* are underperforming relative",
        "  to the hardware compute ceiling.",
        "- **Nodes where methods disagree** warrant deeper investigation —",
        "  possible causes include vectorisation differences, profiling noise,",
        "  or workload sensitivity to rosbag replay timing.",
        "",
        "See `plot_comparison.py` for visualisations.",
    ]

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("Cross-Methodology Comparison")
    print("=" * 60)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    print("\n[1/4] Loading CARET data...")
    df_caret = load_caret()
    print(f"  Nodes: {len(df_caret)}")

    print("[2/4] Loading perf data...")
    df_perf = load_perf()
    print(f"  Nodes: {len(df_perf)}")

    print("[3/4] Loading miniperf data...")
    df_mperf = load_mperf()
    print(f"  Nodes: {len(df_mperf)}")

    # ── Merge on normalised node names ────────────────────────────────────
    frames = [f for f in [df_caret, df_perf, df_mperf] if not f.empty]
    if not frames:
        print("\nERROR: No data available from any experiment.")
        print("Run experiments 1, 3, and 4, then re-run this script.")
        sys.exit(1)

    df = frames[0]
    for f in frames[1:]:
        df = df.join(f, how="outer")

    # ── Save comparison table ────────────────────────────────────────────
    out_table = OUTPUT_DIR / "comparison_table.csv"
    df.to_csv(out_table)
    print(f"\n  Saved comparison table: {out_table} ({len(df)} nodes)")

    # ── Agreement analysis ────────────────────────────────────────────────
    print("\n[4/4] Computing bottleneck agreement...")
    agreement = compute_agreement(df)
    if not agreement.empty:
        out_agree = OUTPUT_DIR / "bottleneck_agreement.csv"
        agreement.to_csv(out_agree, index=False)
        print(f"  Saved: {out_agree}")
        print("\n  Agreement summary:")
        print(agreement.to_string(index=False))

    # ── Generate markdown summary ─────────────────────────────────────────
    md_text = generate_markdown_summary(df, agreement if not agreement.empty else pd.DataFrame())
    out_md = OUTPUT_DIR / "methodology_summary.md"
    out_md.write_text(md_text)
    print(f"\n  Saved: {out_md}")

    print("\n" + "=" * 60)
    print("Comparison complete!")
    print(f"Output: {OUTPUT_DIR}")
    print("=" * 60)
    print("\nNext step: python3 plot_comparison.py")


if __name__ == "__main__":
    main()
