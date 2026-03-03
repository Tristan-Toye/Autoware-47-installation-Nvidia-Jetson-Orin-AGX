#!/usr/bin/env python3
"""
Parse miniperf Results into Structured CSVs
=============================================================================
Parses raw miniperf output from both the "roofline" and "snapshot" scenarios
into structured CSV files suitable for downstream analysis and plotting.

miniperf output format:
  - Roofline directories: contain a profile DB or text summary produced by
    `mperf show <dir>`, which prints a table with per-loop entries.
  - Stat files: contain a single ASCII table (like `perf stat`) per run.

Output files:
  results/miniperf_roofline.csv  — per-node arithmetic intensity + performance
  results/miniperf_stat.csv      — per-node snapshot counter values
  results/miniperf_summary.csv   — combined single-row-per-node summary

Usage: python3 parse_miniperf_results.py
=============================================================================
"""

import os
import re
import sys
import json
import csv
from pathlib import Path
from collections import defaultdict

try:
    import pandas as pd
    import numpy as np
    import yaml
except ImportError as e:
    print(f"ERROR: Required package not found: {e}")
    print("Install with: pip install pandas numpy pyyaml")
    sys.exit(1)

SCRIPT_DIR = Path(__file__).parent
CONFIG_FILE = SCRIPT_DIR / "miniperf_config.yaml"
DATA_DIR    = SCRIPT_DIR / "miniperf_data"
OUTPUT_DIR  = SCRIPT_DIR / "results"


# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------

def load_config():
    """Load miniperf_config.yaml."""
    with open(CONFIG_FILE, "r") as f:
        return yaml.safe_load(f)


# ---------------------------------------------------------------------------
# Roofline output parsing
# ---------------------------------------------------------------------------

# mperf show prints a table like:
#   | Loop / Function         | AI (FLOPs/B) | Perf (GFLOPs/s) | Bound    |
#   | some::namespace::foo    |     12.34    |      4.56       | Compute  |
ROOFLINE_TABLE_RE = re.compile(
    r"\|\s*(?P<name>[^|]+?)\s*\|"          # loop/function name
    r"\s*(?P<ai>[\d.]+(?:e[+-]?\d+)?)\s*\|"  # arithmetic intensity
    r"\s*(?P<perf>[\d.]+(?:e[+-]?\d+)?)\s*\|"  # performance GFLOPs/s
    r"(?:\s*(?P<bound>\w+)\s*\|)?",          # bound type (optional)
    re.IGNORECASE,
)

# Also handle JSON-style output if mperf supports it in newer versions
def parse_roofline_text(text: str, node_name: str) -> list[dict]:
    """Parse mperf show text output for roofline data."""
    rows = []

    lines = text.splitlines()
    found_table = False

    for line in lines:
        m = ROOFLINE_TABLE_RE.search(line)
        if m:
            found_table = True
            name = m.group("name").strip()
            # Skip header rows
            if re.match(r"Loop|Function|Name|---", name, re.IGNORECASE):
                continue
            ai   = float(m.group("ai"))
            perf = float(m.group("perf"))
            bound = (m.group("bound") or "unknown").strip()
            rows.append({
                "node_name":            node_name,
                "hotspot":              name,
                "arithmetic_intensity": ai,    # FLOPs / byte
                "performance_gflops":   perf,  # GFLOPs / s
                "bound":                bound,
            })

    if not found_table:
        # Fallback: try to find individual key: value lines
        ai_m   = re.search(r"arithmetic[_\s]intensity[:\s]+([\d.]+)", text, re.IGNORECASE)
        perf_m = re.search(r"performance[:\s]+([\d.]+)\s*[Gg]?FLOP", text, re.IGNORECASE)
        flops_m = re.search(r"flops[:\s]+([\d.e+\-]+)", text, re.IGNORECASE)
        bytes_m = re.search(r"bytes[:\s]+([\d.e+\-]+)", text, re.IGNORECASE)
        if ai_m and perf_m:
            rows.append({
                "node_name":            node_name,
                "hotspot":              "aggregate",
                "arithmetic_intensity": float(ai_m.group(1)),
                "performance_gflops":   float(perf_m.group(1)),
                "bound":                "unknown",
            })
        elif flops_m and bytes_m:
            flops = float(flops_m.group(1))
            byt   = float(bytes_m.group(1))
            ai    = flops / byt if byt > 0 else 0.0
            rows.append({
                "node_name":            node_name,
                "hotspot":              "aggregate",
                "arithmetic_intensity": ai,
                "performance_gflops":   0.0,  # needs wall time to compute
                "flops_total":          flops,
                "bytes_total":          byt,
                "bound":                "unknown",
            })

    return rows


def parse_all_roofline() -> pd.DataFrame:
    """Walk miniperf_data/<node>/roofline_summary.txt and collect roofline rows."""
    all_rows = []

    if not DATA_DIR.exists():
        print(f"WARNING: Data directory not found: {DATA_DIR}")
        return pd.DataFrame()

    for node_dir in sorted(DATA_DIR.iterdir()):
        if not node_dir.is_dir():
            continue
        node_name = node_dir.name

        # Prefer the roofline_summary.txt written by the shell script
        summary_files = list(node_dir.glob("roofline_summary.txt"))
        # Also look for any mperf output logs
        mperf_logs    = list(node_dir.glob("mperf_rep*.log"))

        texts_to_parse = []
        for f in summary_files + mperf_logs:
            texts_to_parse.append(f.read_text(errors="replace"))

        # Try mperf show on the profile directories if no text found
        if not texts_to_parse:
            profile_dirs = [d for d in node_dir.iterdir()
                            if d.is_dir() and "roofline" in d.name]
            for pd_dir in profile_dirs:
                # Attempt to parse any JSON/text inside the profile directory
                for json_file in pd_dir.glob("**/*.json"):
                    try:
                        data = json.loads(json_file.read_text())
                        texts_to_parse.append(str(data))
                    except Exception:
                        pass
                for txt_file in pd_dir.glob("**/*.txt"):
                    texts_to_parse.append(txt_file.read_text(errors="replace"))

        for text in texts_to_parse:
            rows = parse_roofline_text(text, node_name)
            all_rows.extend(rows)

    if not all_rows:
        print("  No roofline data found. Have you run run_miniperf_roofline.sh?")
        return pd.DataFrame()

    df = pd.DataFrame(all_rows)
    return df


# ---------------------------------------------------------------------------
# Stat output parsing
# ---------------------------------------------------------------------------

# mperf stat table columns (from README example):
# | Counter | Value | Info | Scaling | Description |
STAT_ROW_RE = re.compile(
    r"\|\s*(?P<counter>[^|]+?)\s*\|"
    r"\s*(?P<value>[\d,\.]+(?:\s*\w+)?)\s*\|"
    r"\s*(?P<info>[^|]*?)\s*\|"
    r"\s*(?P<scaling>[\d.]+)\s*\|"
    r"\s*(?P<description>[^|]+?)\s*\|",
)

NUMERIC_RE = re.compile(r"[\d,]+")


def parse_stat_text(text: str, node_name: str) -> dict:
    """Parse a single mperf stat output block into a flat dict."""
    node_metrics = {"node_name": node_name}
    count = 0

    for line in text.splitlines():
        m = STAT_ROW_RE.search(line)
        if not m:
            continue
        counter = m.group("counter").strip()
        raw_val = m.group("value").strip()
        # Skip header rows
        if re.match(r"Counter|---", counter, re.IGNORECASE):
            continue
        # Parse numeric value (strip commas, take first number)
        nums = NUMERIC_RE.findall(raw_val.replace(",", ""))
        if nums:
            node_metrics[counter] = float(nums[0])
            count += 1

    if count == 0:
        return {}
    return node_metrics


def parse_all_stat() -> pd.DataFrame:
    """Walk miniperf_data/<node>/stat_*.txt files and aggregate."""
    node_reps = defaultdict(list)

    if not DATA_DIR.exists():
        return pd.DataFrame()

    for node_dir in sorted(DATA_DIR.iterdir()):
        if not node_dir.is_dir():
            continue
        node_name = node_dir.name
        stat_files = sorted(node_dir.glob("stat_rep*.txt")) or sorted(node_dir.glob("stat_*.txt"))

        for sf in stat_files:
            row = parse_stat_text(sf.read_text(errors="replace"), node_name)
            if row:
                node_reps[node_name].append(row)

    if not node_reps:
        print("  No stat data found. Have you run run_miniperf_stat.sh?")
        return pd.DataFrame()

    # Average across repetitions per node
    rows = []
    for node_name, reps in node_reps.items():
        df_reps = pd.DataFrame(reps).set_index("node_name")
        avg = df_reps.mean(numeric_only=True)
        avg["node_name"] = node_name
        avg["stat_repetitions"] = len(reps)
        rows.append(avg)

    return pd.DataFrame(rows).set_index("node_name")


# ---------------------------------------------------------------------------
# Roofline aggregate: dominant hotspot per node
# ---------------------------------------------------------------------------

def aggregate_roofline(df_roofline: pd.DataFrame) -> pd.DataFrame:
    """
    For each node, compute aggregate roofline metrics:
      - weighted_ai    : FLOP-weighted arithmetic intensity across hotspots
      - max_perf       : peak performance hotspot (GFLOPs/s)
      - dominant_bound : most common bound classification
    """
    if df_roofline.empty:
        return pd.DataFrame()

    agg_rows = []
    for node_name, grp in df_roofline.groupby("node_name"):
        # Weighted average AI by performance (hotspots that run faster contribute more)
        if "performance_gflops" in grp.columns and grp["performance_gflops"].sum() > 0:
            weights = grp["performance_gflops"]
            w_ai = (grp["arithmetic_intensity"] * weights).sum() / weights.sum()
        else:
            w_ai = grp["arithmetic_intensity"].mean()

        max_perf = grp["performance_gflops"].max() if "performance_gflops" in grp.columns else 0.0
        dominant_bound = grp["bound"].mode()[0] if "bound" in grp.columns else "unknown"
        n_hotspots = len(grp)

        agg_rows.append({
            "node_name":            node_name,
            "weighted_ai":          w_ai,
            "max_performance_gflops": max_perf,
            "dominant_bound":       dominant_bound,
            "n_hotspots":           n_hotspots,
        })

    return pd.DataFrame(agg_rows).set_index("node_name")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("Parse miniperf Results")
    print("=" * 60)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # ── Roofline data ──────────────────────────────────────────────────────
    print("\n[1/3] Parsing roofline outputs...")
    df_roofline = parse_all_roofline()
    if not df_roofline.empty:
        out = OUTPUT_DIR / "miniperf_roofline.csv"
        df_roofline.to_csv(out, index=False)
        print(f"  Saved: {out}  ({len(df_roofline)} hotspot rows)")

        df_agg = aggregate_roofline(df_roofline)
        if not df_agg.empty:
            out_agg = OUTPUT_DIR / "miniperf_roofline_agg.csv"
            df_agg.to_csv(out_agg)
            print(f"  Saved: {out_agg}  ({len(df_agg)} nodes)")
    else:
        print("  No roofline data (run run_miniperf_roofline.sh first)")

    # ── Stat data ──────────────────────────────────────────────────────────
    print("\n[2/3] Parsing stat outputs...")
    df_stat = parse_all_stat()
    if not df_stat.empty:
        out = OUTPUT_DIR / "miniperf_stat.csv"
        df_stat.to_csv(out)
        print(f"  Saved: {out}  ({len(df_stat)} nodes)")
        # Derive IPC if available
        if "cycles" in df_stat.columns and "instructions" in df_stat.columns:
            df_stat["ipc"] = df_stat["instructions"] / df_stat["cycles"].replace(0, float("nan"))
            print(f"  Derived IPC for {df_stat['ipc'].notna().sum()} nodes")
    else:
        print("  No stat data (run run_miniperf_stat.sh first)")

    # ── Combined summary ────────────────────────────────────────────────────
    print("\n[3/3] Building combined summary...")
    frames = []
    if not df_roofline.empty:
        df_agg = aggregate_roofline(df_roofline)
        if not df_agg.empty:
            frames.append(df_agg)
    if not df_stat.empty:
        keep_cols = [c for c in ["ipc", "cycles", "instructions",
                                  "llc_misses", "llc_references",
                                  "branch_misses", "stalled_cycles_backend"]
                     if c in df_stat.columns]
        if keep_cols:
            frames.append(df_stat[keep_cols])

    if frames:
        df_summary = pd.concat(frames, axis=1).dropna(how="all")
        out = OUTPUT_DIR / "miniperf_summary.csv"
        df_summary.to_csv(out)
        print(f"  Saved: {out}  ({len(df_summary)} nodes)")
        print("\n  Summary preview:")
        print(df_summary.to_string())
    else:
        print("  No data available for summary.")

    print("\n" + "=" * 60)
    print("Parsing complete!")
    print(f"Output: {OUTPUT_DIR}")
    print("=" * 60)
    print("\nNext step: python3 plot_roofline.py")


if __name__ == "__main__":
    main()
