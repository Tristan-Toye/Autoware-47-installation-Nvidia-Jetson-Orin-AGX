#!/usr/bin/env python3
"""
Compute Architecture-Agnostic Metrics
=============================================================================
Computes architecture-independent performance metrics including:
- Data transfer metrics (bytes per instruction, bandwidth)
- Arithmetic intensity (operations per byte)
- Working set size estimation
- Roofline model positioning

These metrics are useful for comparing performance across different architectures.

Usage: python3 compute_agnostic_metrics.py
=============================================================================
"""

import os
import sys
from pathlib import Path

try:
    import pandas as pd
    import numpy as np
    import matplotlib.pyplot as plt
except ImportError as e:
    print(f"ERROR: Required package not found: {e}")
    print("Install with: pip install pandas numpy matplotlib")
    sys.exit(1)

SCRIPT_DIR = Path(__file__).parent

# Constants for estimation
CACHE_LINE_SIZE = 64  # bytes (typical for ARM/x86)
WORD_SIZE = 8  # bytes (64-bit)


def load_metrics():
    """Load all_metrics.csv."""
    csv_path = SCRIPT_DIR / "perf_data" / "all_metrics.csv"
    
    if not csv_path.exists():
        print(f"ERROR: Metrics CSV not found: {csv_path}")
        print("Run clean_perf_data.py first")
        sys.exit(1)
    
    return pd.read_csv(csv_path, index_col='node_name')


def compute_agnostic_metrics(df):
    """
    Compute architecture-agnostic metrics.
    
    These metrics abstract away architecture-specific details to enable
    cross-platform comparison.
    """
    agnostic = pd.DataFrame(index=df.index)
    
    # =========================================================================
    # Data Transfer Metrics
    # =========================================================================
    
    # Bytes loaded from memory per instruction (estimated)
    # Uses LLC misses as proxy for memory accesses
    if 'cache-misses' in df.columns and 'instructions' in df.columns:
        # Each LLC miss causes a cache line transfer from memory
        bytes_from_memory = df['cache-misses'] * CACHE_LINE_SIZE
        agnostic['bytes_per_instruction'] = bytes_from_memory / df['instructions'].replace(0, np.nan)
    
    # Data transfer ratio (L1 to LLC)
    if 'L1-dcache-loads' in df.columns and 'cache-references' in df.columns:
        agnostic['l1_to_llc_ratio'] = df['L1-dcache-loads'] / df['cache-references'].replace(0, np.nan)
    
    # Memory bandwidth utilization (relative)
    if 'cache-misses' in df.columns and 'cpu-cycles' in df.columns:
        # Bytes transferred per cycle (relative measure)
        agnostic['bytes_per_cycle'] = (df['cache-misses'] * CACHE_LINE_SIZE) / df['cpu-cycles'].replace(0, np.nan)
    
    # =========================================================================
    # Arithmetic Intensity (Dual-Estimate Roofline)
    # =========================================================================
    # See METRICS_DEFINITIONS.md for the full rationale.
    #
    # If FP counters (r0075/ASE_SPEC, r0076/VFP_SPEC) are available, compute
    # real FLOPs-based AI.  Otherwise fall back to instruction-based OI.

    has_fp = 'r0075' in df.columns and 'r0076' in df.columns
    has_ll_miss = 'armv8_cortex_a78/ll_cache_miss_rd/' in df.columns

    if has_fp and has_ll_miss:
        ase = df['r0075'].fillna(0)
        vfp = df['r0076'].fillna(0)
        ll_miss = df['armv8_cortex_a78/ll_cache_miss_rd/'].fillna(0)
        bytes_dram = ll_miss * CACHE_LINE_SIZE

        flops_conservative = vfp + ase * 4     # FP32, no FMA
        flops_fma = vfp + ase * 8              # FP32 + FMA=2 ops

        agnostic['flops_per_byte_conservative'] = flops_conservative / bytes_dram.replace(0, np.nan)
        agnostic['flops_per_byte_fma'] = flops_fma / bytes_dram.replace(0, np.nan)

        total_instr = df.get('armv8_cortex_a78/inst_retired/', df.get('instructions', pd.Series(dtype=float)))
        if total_instr is not None:
            total_instr = total_instr.fillna(0)
            agnostic['fp_fraction'] = (vfp + ase) / total_instr.replace(0, np.nan)
            fp_total = vfp + ase
            agnostic['simd_fraction'] = ase / fp_total.replace(0, np.nan)
    elif 'instructions' in df.columns and 'cache-misses' in df.columns:
        bytes_transferred = df['cache-misses'] * CACHE_LINE_SIZE
        agnostic['ops_per_byte'] = df['instructions'] / bytes_transferred.replace(0, np.nan)

    # Compute-to-memory ratio
    if 'instructions' in df.columns and 'L1-dcache-loads' in df.columns:
        agnostic['compute_memory_ratio'] = df['instructions'] / df['L1-dcache-loads'].replace(0, np.nan)
    
    # =========================================================================
    # Working Set Estimation
    # =========================================================================
    
    # Working set size estimate based on TLB behavior
    # Each TLB miss indicates access to a new page (4KB typical)
    PAGE_SIZE = 4096
    
    if 'dTLB-load-misses' in df.columns:
        # Unique pages accessed (rough estimate)
        agnostic['estimated_data_pages'] = df['dTLB-load-misses']
        agnostic['estimated_data_working_set_KB'] = (df['dTLB-load-misses'] * PAGE_SIZE) / 1024
    
    if 'iTLB-load-misses' in df.columns:
        agnostic['estimated_code_pages'] = df['iTLB-load-misses']
        agnostic['estimated_code_working_set_KB'] = (df['iTLB-load-misses'] * PAGE_SIZE) / 1024
    
    # =========================================================================
    # Cache Efficiency Metrics
    # =========================================================================
    
    # Reuse ratio (higher = better cache utilization)
    if 'L1-dcache-loads' in df.columns and 'L1-dcache-load-misses' in df.columns:
        hits = df['L1-dcache-loads'] - df['L1-dcache-load-misses']
        agnostic['l1d_reuse_ratio'] = hits / df['L1-dcache-load-misses'].replace(0, np.nan)
    
    # Overall cache efficiency (hits vs misses at all levels)
    if 'cache-references' in df.columns and 'cache-misses' in df.columns:
        agnostic['overall_cache_hit_rate_%'] = ((df['cache-references'] - df['cache-misses']) / 
                                                df['cache-references'].replace(0, np.nan)) * 100
    
    # =========================================================================
    # Instruction Mix Metrics
    # =========================================================================
    
    # Branch proportion (higher = more control-flow intensive)
    if 'branches' in df.columns and 'instructions' in df.columns:
        agnostic['branch_proportion_%'] = (df['branches'] / df['instructions'].replace(0, np.nan)) * 100
    
    # Memory operation proportion
    if 'L1-dcache-loads' in df.columns and 'instructions' in df.columns:
        agnostic['memory_op_proportion_%'] = (df['L1-dcache-loads'] / df['instructions'].replace(0, np.nan)) * 100
    
    return agnostic


RIDGE_CONSERVATIVE = 0.5156   # 105.6 GFLOPs/s / 204.8 GB/s
RIDGE_FMA = 2.0625            # 422.4 GFLOPs/s / 204.8 GB/s


def classify_bottleneck(row):
    """
    Classify the primary bottleneck for a node.

    If FP-based AI is available, use the roofline ridge points.
    Otherwise fall back to the legacy instruction-based heuristic.
    """
    # FP-based classification (preferred)
    has_fp = pd.notna(row.get('flops_per_byte_conservative'))
    if has_fp:
        ai_c = row['flops_per_byte_conservative']
        ai_f = row['flops_per_byte_fma']
        bound_c = 'memory' if ai_c < RIDGE_CONSERVATIVE else 'compute'
        bound_f = 'memory' if ai_f < RIDGE_FMA else 'compute'
        if bound_c == bound_f:
            return bound_c
        return 'ambiguous'

    # Legacy fallback (instruction-based)
    bottlenecks = []
    if pd.notna(row.get('ops_per_byte')):
        if row['ops_per_byte'] < 10:
            bottlenecks.append('memory')
    if pd.notna(row.get('branch_proportion_%')):
        if row['branch_proportion_%'] > 20:
            bottlenecks.append('branches')
    if pd.notna(row.get('overall_cache_hit_rate_%')):
        if row['overall_cache_hit_rate_%'] < 90:
            bottlenecks.append('cache')
    if not bottlenecks:
        return 'compute'
    return ', '.join(bottlenecks)


def save_agnostic_metrics(agnostic, output_path):
    """Save agnostic metrics to CSV."""
    # Add bottleneck classification
    agnostic['primary_bottleneck'] = agnostic.apply(classify_bottleneck, axis=1)
    
    agnostic.to_csv(output_path)
    print(f"Saved agnostic metrics to: {output_path}")


def plot_arithmetic_intensity(agnostic, output_dir):
    """Create arithmetic intensity visualization (dual-estimate if available)."""
    from matplotlib.patches import Patch

    # Prefer FP-based AI; fall back to legacy ops_per_byte
    if 'flops_per_byte_conservative' in agnostic.columns:
        col_c = 'flops_per_byte_conservative'
        col_f = 'flops_per_byte_fma'
        data_c = agnostic[col_c].dropna().sort_values(ascending=True)
        data_f = agnostic[col_f].reindex(data_c.index)
        if data_c.empty:
            return

        fig, ax = plt.subplots(figsize=(14, 8))
        y = np.arange(len(data_c))
        ax.barh(y - 0.2, data_c, height=0.35, color='#42A5F5', label='Conservative (x4)')
        ax.barh(y + 0.2, data_f, height=0.35, color='#AB47BC', label='FMA-adjusted (x8)')
        ax.set_yticks(y)
        ax.set_yticklabels([n[:30] for n in data_c.index])
        ax.axvline(x=RIDGE_CONSERVATIVE, color='#42A5F5', ls='--', alpha=0.7,
                    label=f'Ridge conservative ({RIDGE_CONSERVATIVE:.3f})')
        ax.axvline(x=RIDGE_FMA, color='#AB47BC', ls='--', alpha=0.7,
                    label=f'Ridge FMA ({RIDGE_FMA:.3f})')
        ax.set_xlabel('Arithmetic Intensity (FLOPs / byte)')
        ax.set_title('Arithmetic Intensity by Node (Dual Estimate)')
        ax.legend(loc='lower right', fontsize=9)
        ax.set_xscale('log')
    elif 'ops_per_byte' in agnostic.columns:
        data = agnostic['ops_per_byte'].dropna().sort_values(ascending=True)
        if data.empty:
            return
        fig, ax = plt.subplots(figsize=(12, 8))
        colors = ['#ff6b6b' if v < 10 else '#4ecdc4' for v in data]
        ax.barh(range(len(data)), data, color=colors)
        ax.set_yticks(range(len(data)))
        ax.set_yticklabels([n[:30] for n in data.index])
        ax.set_xlabel('Operational Intensity (instructions / byte)')
        ax.set_title('Instruction-Based Operational Intensity (legacy, no FP counters)')
        ax.axvline(x=10, color='gray', ls='--', alpha=0.7, label='Heuristic boundary')
        ax.legend(handles=[
            Patch(facecolor='#ff6b6b', label='Memory-bound (< 10)'),
            Patch(facecolor='#4ecdc4', label='Compute-bound (>= 10)')
        ], loc='lower right')
        ax.set_xscale('log')
    else:
        return

    plt.tight_layout()
    plt.savefig(output_dir / 'arithmetic_intensity.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("  Saved: arithmetic_intensity.png")


def plot_working_set(agnostic, output_dir):
    """Create working set size visualization."""
    cols = ['estimated_data_working_set_KB', 'estimated_code_working_set_KB']
    available_cols = [c for c in cols if c in agnostic.columns]
    
    if not available_cols:
        return
    
    data = agnostic[available_cols].dropna(how='all')
    if data.empty:
        return
    
    fig, ax = plt.subplots(figsize=(12, 8))
    
    x = np.arange(len(data.index))
    width = 0.35
    
    if 'estimated_data_working_set_KB' in data.columns:
        ax.barh(x - width/2, data['estimated_data_working_set_KB'], width, 
               label='Data', color='steelblue')
    
    if 'estimated_code_working_set_KB' in data.columns:
        ax.barh(x + width/2, data['estimated_code_working_set_KB'], width,
               label='Code', color='coral')
    
    ax.set_yticks(x)
    ax.set_yticklabels([name[:25] for name in data.index])
    ax.set_xlabel('Estimated Working Set (KB)')
    ax.set_title('Estimated Working Set Size by Node')
    ax.legend()
    ax.set_xscale('log')
    
    # Add cache size reference lines
    cache_sizes = [32, 256, 1024, 4096]  # L1, L2, L3 typical sizes in KB
    cache_names = ['L1 (32KB)', 'L2 (256KB)', 'L3 (1MB)', 'L3 (4MB)']
    for size, name in zip(cache_sizes, cache_names):
        ax.axvline(x=size, color='gray', linestyle=':', alpha=0.5)
        ax.text(size, len(data.index)-0.5, name, fontsize=8, alpha=0.7)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'working_set_size.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("  Saved: working_set_size.png")


def plot_bottleneck_distribution(agnostic, output_dir):
    """Create bottleneck classification pie chart."""
    if 'primary_bottleneck' not in agnostic.columns:
        return
    
    counts = agnostic['primary_bottleneck'].value_counts()
    
    fig, ax = plt.subplots(figsize=(10, 8))
    
    colors = {
        'compute': '#4ecdc4',
        'memory': '#ff6b6b',
        'cache': '#ffe66d',
        'branches': '#95e1d3',
    }
    
    pie_colors = [colors.get(k.split(',')[0].strip(), '#cccccc') for k in counts.index]
    
    wedges, texts, autotexts = ax.pie(counts, labels=counts.index, autopct='%1.1f%%',
                                       colors=pie_colors, startangle=90)
    ax.set_title('Primary Bottleneck Distribution')
    
    plt.tight_layout()
    plt.savefig(output_dir / 'bottleneck_distribution.png', dpi=150, bbox_inches='tight')
    plt.close()
    print("  Saved: bottleneck_distribution.png")


def print_analysis_summary(agnostic):
    """Print analysis summary."""
    print("\n" + "=" * 60)
    print("Architecture-Agnostic Analysis Summary")
    print("=" * 60)
    
    if 'flops_per_byte_conservative' in agnostic.columns:
        ai_c = agnostic['flops_per_byte_conservative'].dropna()
        ai_f = agnostic['flops_per_byte_fma'].dropna()
        print(f"\nArithmetic Intensity (FLOPs-based):")
        print(f"  Conservative (x4): mean={ai_c.mean():.4f}, "
              f"memory-bound={int((ai_c < RIDGE_CONSERVATIVE).sum())}, "
              f"compute-bound={int((ai_c >= RIDGE_CONSERVATIVE).sum())}")
        print(f"  FMA-adjusted (x8): mean={ai_f.mean():.4f}, "
              f"memory-bound={int((ai_f < RIDGE_FMA).sum())}, "
              f"compute-bound={int((ai_f >= RIDGE_FMA).sum())}")
        if 'fp_fraction' in agnostic.columns:
            fp = agnostic['fp_fraction'].dropna()
            print(f"  FP/SIMD fraction:  mean={fp.mean():.4f} ({fp.mean()*100:.1f}% of instructions)")
    elif 'ops_per_byte' in agnostic.columns:
        ai = agnostic['ops_per_byte'].dropna()
        memory_bound = (ai < 10).sum()
        compute_bound = (ai >= 10).sum()
        print(f"\nArithmetic Intensity (instruction-based, legacy):")
        print(f"  Memory-bound nodes: {memory_bound}")
        print(f"  Compute-bound nodes: {compute_bound}")
        print(f"  Mean ops/byte: {ai.mean():.2f}")
    
    if 'primary_bottleneck' in agnostic.columns:
        print(f"\nBottleneck Distribution:")
        for bottleneck, count in agnostic['primary_bottleneck'].value_counts().items():
            print(f"  {bottleneck}: {count}")
    
    if 'estimated_data_working_set_KB' in agnostic.columns:
        ws = agnostic['estimated_data_working_set_KB'].dropna()
        print(f"\nData Working Set:")
        print(f"  Mean: {ws.mean():.1f} KB")
        print(f"  Max:  {ws.max():.1f} KB")


def main():
    """Main entry point."""
    print("=" * 60)
    print("Architecture-Agnostic Metrics Computation")
    print("=" * 60)
    
    # Load raw metrics
    print("\nLoading metrics...")
    df = load_metrics()
    print(f"Loaded {len(df)} nodes")
    
    # Compute agnostic metrics
    print("\nComputing architecture-agnostic metrics...")
    agnostic = compute_agnostic_metrics(df)
    print(f"Computed {len(agnostic.columns)} metrics")
    
    # Save to CSV
    output_dir = SCRIPT_DIR / "perf_data"
    save_agnostic_metrics(agnostic, output_dir / "agnostic_metrics.csv")
    
    # Create visualizations
    viz_dir = output_dir / "visualizations"
    viz_dir.mkdir(parents=True, exist_ok=True)
    
    print("\nGenerating visualizations...")
    plot_arithmetic_intensity(agnostic, viz_dir)
    plot_working_set(agnostic, viz_dir)
    plot_bottleneck_distribution(agnostic, viz_dir)
    
    # Print summary
    print_analysis_summary(agnostic)
    
    print("\n" + "=" * 60)
    print("Analysis complete!")
    print("=" * 60)
    print(f"\nOutput:")
    print(f"  Agnostic metrics: {output_dir / 'agnostic_metrics.csv'}")
    print(f"  Visualizations:   {viz_dir}")


if __name__ == '__main__':
    main()
