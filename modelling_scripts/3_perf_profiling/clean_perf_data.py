#!/usr/bin/env python3
"""
Clean Perf Data Script
=============================================================================
Parses raw perf stat output files and creates unified CSV files.

Usage: python3 clean_perf_data.py
=============================================================================
"""

import os
import re
import csv
import sys
from pathlib import Path
from collections import defaultdict

SCRIPT_DIR = Path(__file__).parent


def parse_perf_output(file_path):
    """
    Parse a perf stat output file.
    
    Returns:
        dict: metric_name -> value
    """
    metrics = {}
    
    if not file_path.exists():
        return metrics
    
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Pattern for perf stat output lines
    # Examples:
    #   1,234,567,890      instructions
    #   1234567890         cpu-cycles
    #   123,456            L1-dcache-loads      # 12.34% of all cache refs
    #   <not supported>    some-metric
    
    patterns = [
        # Standard format with commas: "1,234,567  metric-name"
        r'^\s*([\d,]+)\s+(\S+)',
        # Format with unit and comment: "1234567 metric-name    # 12.34% of something"
        r'^\s*([\d,]+)\s+(\S+)\s+#',
        # Not supported format
        r'^\s*<not supported>\s+(\S+)',
        # Format with percentage: "1234567 metric ( 12.34%)"
        r'^\s*([\d,]+)\s+(\S+)\s+\(\s*[\d.]+%\s*\)',
    ]
    
    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('#') or line.startswith('Performance'):
            continue
        
        # Try to parse the line
        for pattern in patterns:
            match = re.match(pattern, line)
            if match:
                groups = match.groups()
                if len(groups) >= 2:
                    value_str = groups[0].replace(',', '')
                    metric_name = groups[1]
                    try:
                        value = int(value_str)
                        metrics[metric_name] = value
                    except ValueError:
                        try:
                            value = float(value_str)
                            metrics[metric_name] = value
                        except ValueError:
                            pass
                elif len(groups) == 1:
                    # Not supported metric
                    metrics[groups[0]] = None
                break
    
    return metrics


def collect_all_metrics(raw_dir):
    """
    Collect metrics from all nodes and clusters.
    
    Returns:
        dict: node_name -> {metric_name: value}
        set: all metric names
    """
    all_data = {}
    all_metrics = set()
    
    if not raw_dir.exists():
        print(f"ERROR: Raw data directory not found: {raw_dir}")
        return all_data, all_metrics
    
    for node_dir in raw_dir.iterdir():
        if not node_dir.is_dir():
            continue
        
        node_name = node_dir.name
        node_metrics = {}
        
        for cluster_file in node_dir.glob("*.txt"):
            metrics = parse_perf_output(cluster_file)
            node_metrics.update(metrics)
            all_metrics.update(metrics.keys())
        
        if node_metrics:
            all_data[node_name] = node_metrics
            print(f"  {node_name}: {len(node_metrics)} metrics")
    
    return all_data, all_metrics


def save_all_metrics_csv(all_data, all_metrics, output_path):
    """Save all metrics for all nodes to a single CSV."""
    
    if not all_data:
        print("No data to save")
        return
    
    # Sort metrics alphabetically
    sorted_metrics = sorted(all_metrics)
    
    # Create CSV with node as rows, metrics as columns
    fieldnames = ['node_name'] + sorted_metrics
    
    with open(output_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        
        for node_name in sorted(all_data.keys()):
            row = {'node_name': node_name}
            for metric in sorted_metrics:
                value = all_data[node_name].get(metric)
                row[metric] = value if value is not None else ''
            writer.writerow(row)
    
    print(f"\nSaved all metrics to: {output_path}")


def save_node_csv(node_name, metrics, output_dir):
    """Save per-node CSV with metrics as rows."""
    
    output_path = output_dir / f"node_{node_name}.csv"
    
    with open(output_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['metric', 'value', 'formatted'])
        
        for metric in sorted(metrics.keys()):
            value = metrics[metric]
            if value is None:
                formatted = 'N/A'
            elif isinstance(value, int):
                formatted = f'{value:,}'
            else:
                formatted = f'{value:,.2f}'
            writer.writerow([metric, value if value is not None else '', formatted])
    
    return output_path


def main():
    """Main entry point."""
    print("=" * 60)
    print("Clean Perf Data")
    print("=" * 60)
    
    raw_dir = SCRIPT_DIR / "perf_data" / "raw"
    output_dir = SCRIPT_DIR / "perf_data"
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"\nReading raw data from: {raw_dir}")
    
    # Collect all metrics
    all_data, all_metrics = collect_all_metrics(raw_dir)
    
    if not all_data:
        print("\nNo data found. Run run_perf_clusters.sh first.")
        sys.exit(1)
    
    print(f"\nTotal nodes: {len(all_data)}")
    print(f"Total unique metrics: {len(all_metrics)}")
    
    # Save combined CSV
    save_all_metrics_csv(all_data, all_metrics, output_dir / "all_metrics.csv")
    
    # Save per-node CSVs
    print("\nSaving per-node CSVs...")
    for node_name, metrics in all_data.items():
        path = save_node_csv(node_name, metrics, output_dir)
        print(f"  {path.name}")
    
    print("\n" + "=" * 60)
    print("Data cleaning complete!")
    print("=" * 60)
    print(f"\nOutput directory: {output_dir}")
    print("\nNext: python3 analyze_perf.py")


if __name__ == '__main__':
    main()
