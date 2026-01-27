#!/usr/bin/env python3
"""
Perf Analysis Script
=============================================================================
Analyzes perf data and computes derived metrics including:
- IPC (Instructions Per Cycle)
- Cache miss rates
- Branch misprediction rates
- MPKI (Misses Per Kilo-Instruction)

Generates visualizations comparing metrics across nodes.

Usage: python3 analyze_perf.py
=============================================================================
"""

import os
import sys
import csv
import yaml
from pathlib import Path
from collections import defaultdict

try:
    import pandas as pd
    import matplotlib.pyplot as plt
    import numpy as np
except ImportError as e:
    print(f"ERROR: Required package not found: {e}")
    print("Install with: pip install pandas matplotlib numpy")
    sys.exit(1)

SCRIPT_DIR = Path(__file__).parent


def load_config():
    """Load perf configuration."""
    config_path = SCRIPT_DIR / "perf_config.yaml"
    if not config_path.exists():
        return {}
    
    with open(config_path, 'r') as f:
        return yaml.safe_load(f)


def load_metrics():
    """Load all_metrics.csv."""
    csv_path = SCRIPT_DIR / "perf_data" / "all_metrics.csv"
    
    if not csv_path.exists():
        print(f"ERROR: Metrics CSV not found: {csv_path}")
        print("Run clean_perf_data.py first")
        sys.exit(1)
    
    return pd.read_csv(csv_path, index_col='node_name')


def safe_divide(a, b, default=0):
    """Safely divide, returning default if b is 0 or NaN."""
    if pd.isna(b) or b == 0:
        return default
    return a / b


def compute_derived_metrics(df, config):
    """Compute derived metrics based on config."""
    derived = pd.DataFrame(index=df.index)
    
    # IPC - Instructions Per Cycle
    if 'instructions' in df.columns and 'cpu-cycles' in df.columns:
        derived['IPC'] = df['instructions'] / df['cpu-cycles'].replace(0, np.nan)
    
    # Branch misprediction rate
    if 'branches' in df.columns and 'branch-misses' in df.columns:
        derived['branch_miss_rate_%'] = (df['branch-misses'] / df['branches'].replace(0, np.nan)) * 100
    
    # L1D cache miss rate
    if 'L1-dcache-loads' in df.columns and 'L1-dcache-load-misses' in df.columns:
        derived['L1D_miss_rate_%'] = (df['L1-dcache-load-misses'] / df['L1-dcache-loads'].replace(0, np.nan)) * 100
    
    # L1I cache miss rate
    if 'L1-icache-loads' in df.columns and 'L1-icache-load-misses' in df.columns:
        derived['L1I_miss_rate_%'] = (df['L1-icache-load-misses'] / df['L1-icache-loads'].replace(0, np.nan)) * 100
    
    # LLC miss rate
    if 'cache-references' in df.columns and 'cache-misses' in df.columns:
        derived['LLC_miss_rate_%'] = (df['cache-misses'] / df['cache-references'].replace(0, np.nan)) * 100
    
    # dTLB miss rate
    if 'dTLB-loads' in df.columns and 'dTLB-load-misses' in df.columns:
        derived['dTLB_miss_rate_%'] = (df['dTLB-load-misses'] / df['dTLB-loads'].replace(0, np.nan)) * 100
    
    # MPKI - Misses Per Kilo-Instruction
    if 'instructions' in df.columns:
        inst_k = df['instructions'] / 1000
        
        if 'L1-dcache-load-misses' in df.columns:
            derived['MPKI_L1D'] = df['L1-dcache-load-misses'] / inst_k.replace(0, np.nan)
        
        if 'L1-icache-load-misses' in df.columns:
            derived['MPKI_L1I'] = df['L1-icache-load-misses'] / inst_k.replace(0, np.nan)
        
        if 'cache-misses' in df.columns:
            derived['MPKI_LLC'] = df['cache-misses'] / inst_k.replace(0, np.nan)
        
        if 'branch-misses' in df.columns:
            derived['MPKI_branch'] = df['branch-misses'] / inst_k.replace(0, np.nan)
    
    # Branch density
    if 'instructions' in df.columns and 'branches' in df.columns:
        derived['branch_density_%'] = (df['branches'] / df['instructions'].replace(0, np.nan)) * 100
    
    # Memory intensity (loads per instruction)
    if 'instructions' in df.columns and 'L1-dcache-loads' in df.columns:
        derived['memory_intensity'] = df['L1-dcache-loads'] / df['instructions'].replace(0, np.nan)
    
    return derived


def save_derived_metrics(derived, output_path):
    """Save derived metrics to CSV."""
    derived.to_csv(output_path)
    print(f"Saved derived metrics to: {output_path}")


def plot_ipc_comparison(derived, output_dir):
    """Create IPC comparison bar chart."""
    if 'IPC' not in derived.columns:
        return
    
    fig, ax = plt.subplots(figsize=(12, 6))
    
    data = derived['IPC'].dropna().sort_values(ascending=True)
    
    colors = plt.cm.RdYlGn(data / data.max())
    bars = ax.barh(range(len(data)), data, color=colors)
    
    ax.set_yticks(range(len(data)))
    ax.set_yticklabels([name[:30] for name in data.index])
    ax.set_xlabel('Instructions Per Cycle (IPC)')
    ax.set_title('IPC Comparison Across Nodes')
    ax.axvline(x=data.mean(), color='red', linestyle='--', alpha=0.7, label=f'Mean: {data.mean():.2f}')
    ax.legend()
    
    plt.tight_layout()
    plt.savefig(output_dir / 'ipc_comparison.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("  Saved: ipc_comparison.png")


def plot_cache_miss_rates(derived, output_dir):
    """Create cache miss rate comparison."""
    miss_cols = [col for col in derived.columns if 'miss_rate' in col]
    if not miss_cols:
        return
    
    data = derived[miss_cols].dropna(how='all')
    if data.empty:
        return
    
    fig, ax = plt.subplots(figsize=(14, 8))
    
    x = np.arange(len(data.index))
    width = 0.8 / len(miss_cols)
    
    for i, col in enumerate(miss_cols):
        offset = (i - len(miss_cols)/2 + 0.5) * width
        ax.bar(x + offset, data[col], width, label=col.replace('_', ' ').replace('%', ''))
    
    ax.set_xticks(x)
    ax.set_xticklabels([name[:20] for name in data.index], rotation=45, ha='right')
    ax.set_ylabel('Miss Rate (%)')
    ax.set_title('Cache Miss Rates by Node')
    ax.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
    ax.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'cache_miss_rates.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("  Saved: cache_miss_rates.png")


def plot_mpki_comparison(derived, output_dir):
    """Create MPKI comparison heatmap."""
    mpki_cols = [col for col in derived.columns if col.startswith('MPKI')]
    if not mpki_cols:
        return
    
    data = derived[mpki_cols].dropna(how='all')
    if data.empty:
        return
    
    fig, ax = plt.subplots(figsize=(10, 8))
    
    im = ax.imshow(data.values, cmap='YlOrRd', aspect='auto')
    
    ax.set_xticks(range(len(mpki_cols)))
    ax.set_xticklabels([col.replace('MPKI_', '') for col in mpki_cols])
    ax.set_yticks(range(len(data.index)))
    ax.set_yticklabels([name[:25] for name in data.index])
    
    plt.colorbar(im, ax=ax, label='MPKI')
    ax.set_title('Misses Per Kilo-Instruction (MPKI) Heatmap')
    
    # Add text annotations
    for i in range(len(data.index)):
        for j in range(len(mpki_cols)):
            val = data.iloc[i, j]
            if not pd.isna(val):
                ax.text(j, i, f'{val:.1f}', ha='center', va='center', fontsize=8,
                       color='white' if val > data.values.max()/2 else 'black')
    
    plt.tight_layout()
    plt.savefig(output_dir / 'mpki_heatmap.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("  Saved: mpki_heatmap.png")


def plot_memory_intensity(derived, output_dir):
    """Create memory intensity vs IPC scatter plot."""
    if 'IPC' not in derived.columns or 'memory_intensity' not in derived.columns:
        return
    
    data = derived[['IPC', 'memory_intensity']].dropna()
    if data.empty:
        return
    
    fig, ax = plt.subplots(figsize=(10, 8))
    
    scatter = ax.scatter(data['memory_intensity'], data['IPC'], 
                         c=data['IPC'], cmap='viridis', s=100, alpha=0.7)
    
    for name, row in data.iterrows():
        ax.annotate(name[:15], (row['memory_intensity'], row['IPC']), 
                   fontsize=8, alpha=0.7)
    
    ax.set_xlabel('Memory Intensity (loads/instruction)')
    ax.set_ylabel('IPC')
    ax.set_title('Memory Intensity vs IPC')
    ax.grid(True, alpha=0.3)
    plt.colorbar(scatter, ax=ax, label='IPC')
    
    plt.tight_layout()
    plt.savefig(output_dir / 'memory_intensity_vs_ipc.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("  Saved: memory_intensity_vs_ipc.png")


def print_summary(df, derived):
    """Print summary statistics."""
    print("\n" + "=" * 60)
    print("Summary Statistics")
    print("=" * 60)
    
    if 'IPC' in derived.columns:
        print(f"\nIPC:")
        print(f"  Mean:  {derived['IPC'].mean():.3f}")
        print(f"  Min:   {derived['IPC'].min():.3f}")
        print(f"  Max:   {derived['IPC'].max():.3f}")
    
    miss_cols = [col for col in derived.columns if 'miss_rate' in col]
    if miss_cols:
        print(f"\nCache Miss Rates (mean):")
        for col in miss_cols:
            print(f"  {col}: {derived[col].mean():.2f}%")
    
    mpki_cols = [col for col in derived.columns if col.startswith('MPKI')]
    if mpki_cols:
        print(f"\nMPKI (mean):")
        for col in mpki_cols:
            print(f"  {col}: {derived[col].mean():.2f}")


def main():
    """Main entry point."""
    print("=" * 60)
    print("Perf Analysis")
    print("=" * 60)
    
    config = load_config()
    
    # Load raw metrics
    print("\nLoading metrics...")
    df = load_metrics()
    print(f"Loaded {len(df)} nodes with {len(df.columns)} metrics")
    
    # Compute derived metrics
    print("\nComputing derived metrics...")
    derived = compute_derived_metrics(df, config)
    print(f"Computed {len(derived.columns)} derived metrics")
    
    # Save derived metrics
    output_dir = SCRIPT_DIR / "perf_data"
    save_derived_metrics(derived, output_dir / "derived_metrics.csv")
    
    # Create visualizations
    viz_dir = output_dir / "visualizations"
    viz_dir.mkdir(parents=True, exist_ok=True)
    
    print("\nGenerating visualizations...")
    plot_ipc_comparison(derived, viz_dir)
    plot_cache_miss_rates(derived, viz_dir)
    plot_mpki_comparison(derived, viz_dir)
    plot_memory_intensity(derived, viz_dir)
    
    # Print summary
    print_summary(df, derived)
    
    print("\n" + "=" * 60)
    print("Analysis complete!")
    print("=" * 60)
    print(f"\nOutput:")
    print(f"  Derived metrics: {output_dir / 'derived_metrics.csv'}")
    print(f"  Visualizations:  {viz_dir}")


if __name__ == '__main__':
    main()
