#!/usr/bin/env python3
"""
Node Latency Export Script
=============================================================================
Exports node latency data from CARET trace to CSV with:
- Node name
- Latency in ms
- Percentage of total latency
- Percentage of longest path latency

Also generates a cumulative latency chart.

Usage: python3 export_node_latency.py [config_file]
=============================================================================
"""

import os
import sys
import csv
import yaml
from pathlib import Path
from collections import defaultdict

try:
    from caret_analyze import Application, Architecture, Lttng
    import pandas as pd
    import matplotlib.pyplot as plt
    import numpy as np
except ImportError as e:
    print(f"ERROR: Required package not found: {e}")
    print("Install with: pip install caret-analyze pandas matplotlib")
    sys.exit(1)

SCRIPT_DIR = Path(__file__).parent


def load_config(config_path=None):
    """Load analysis configuration."""
    if config_path is None:
        config_path = SCRIPT_DIR / "results" / "analysis_config.yaml"
    
    if not config_path.exists():
        print(f"ERROR: Config file not found: {config_path}")
        print("Run analyze_caret_results.sh first.")
        sys.exit(1)
    
    with open(config_path, 'r') as f:
        return yaml.safe_load(f)


def load_caret_data(config):
    """Load CARET trace data and architecture."""
    lttng_path = config['lttng_path']
    arch_file = config.get('architecture_file')
    
    print(f"Loading trace data from: {lttng_path}")
    lttng = Lttng(lttng_path)
    
    if arch_file and Path(arch_file).exists():
        print(f"Loading architecture from: {arch_file}")
        arch = Architecture('yaml', arch_file)
    else:
        print("Creating architecture from trace data...")
        arch = Architecture('lttng', lttng_path)
    
    print("Creating application object...")
    app = Application(arch, lttng)
    
    return app, arch, lttng


def compute_node_latencies(app, arch, lstrip_s=5, rstrip_s=2):
    """
    Compute latency statistics for all nodes.
    
    Returns:
        dict: Node name -> latency data
        list: Path information with nodes
    """
    node_latencies = defaultdict(lambda: {'latencies': [], 'paths': []})
    path_info_list = []
    
    print("\nSearching for paths...")
    try:
        paths = arch.search_paths('*', '*')
    except Exception as e:
        print(f"  WARNING: Could not search paths: {e}")
        paths = []
    
    print(f"Found {len(paths)} paths")
    
    # Find the longest path (by duration)
    longest_path_duration = 0
    longest_path_nodes = []
    
    for path_def in paths:
        try:
            path = app.get_path(path_def.path_name)
            
            # Get path response times
            response_times = path.to_dataframe()
            if response_times is None or len(response_times) == 0:
                continue
            
            # Calculate median response time for the path
            path_duration = response_times['response_time'].median() / 1e6  # Convert to ms
            
            # Get nodes in this path
            path_nodes = []
            for node in path.nodes:
                node_name = node.node_name
                path_nodes.append(node_name)
                
                # Get node latency (callback latency)
                try:
                    callbacks = node.callbacks
                    for cb in callbacks:
                        latency_df = cb.to_dataframe()
                        if latency_df is not None and len(latency_df) > 0:
                            # Filter by lstrip and rstrip
                            latencies = latency_df['latency'].values / 1e6  # Convert to ms
                            if len(latencies) > 0:
                                median_latency = np.median(latencies)
                                node_latencies[node_name]['latencies'].append(median_latency)
                                node_latencies[node_name]['paths'].append(path_def.path_name)
                except Exception:
                    pass
            
            if path_duration > longest_path_duration:
                longest_path_duration = path_duration
                longest_path_nodes = path_nodes
            
            path_info_list.append({
                'path_name': path_def.path_name,
                'duration_ms': path_duration,
                'nodes': path_nodes
            })
            
        except Exception as e:
            print(f"  WARNING: Could not process path {path_def.path_name}: {e}")
    
    # Also collect latencies from all nodes directly
    print("\nCollecting latencies from all nodes...")
    try:
        nodes = app.get_nodes('*')
        for node in nodes:
            node_name = node.node_name
            try:
                callbacks = node.callbacks
                for cb in callbacks:
                    latency_df = cb.to_dataframe()
                    if latency_df is not None and len(latency_df) > 0:
                        latencies = latency_df['latency'].values / 1e6
                        if len(latencies) > 0:
                            median_latency = np.median(latencies)
                            if median_latency not in node_latencies[node_name]['latencies']:
                                node_latencies[node_name]['latencies'].append(median_latency)
            except Exception:
                pass
    except Exception as e:
        print(f"  WARNING: Could not iterate nodes: {e}")
    
    return dict(node_latencies), path_info_list, longest_path_duration, longest_path_nodes


def export_to_csv(node_latencies, path_info_list, longest_path_duration, 
                  longest_path_nodes, output_path):
    """Export node latencies to CSV sorted by highest latency."""
    
    # Prepare data
    rows = []
    total_latency = 0
    
    for node_name, data in node_latencies.items():
        if data['latencies']:
            avg_latency = np.mean(data['latencies'])
            total_latency += avg_latency
            rows.append({
                'node_name': node_name,
                'latency_ms': avg_latency,
                'in_longest_path': node_name in longest_path_nodes,
                'num_paths': len(set(data['paths']))
            })
    
    # Sort by latency (highest first)
    rows.sort(key=lambda x: x['latency_ms'], reverse=True)
    
    # Calculate percentages
    for row in rows:
        row['percentage_of_total'] = (row['latency_ms'] / total_latency * 100) if total_latency > 0 else 0
        row['percentage_of_longest_path'] = (row['latency_ms'] / longest_path_duration * 100) if longest_path_duration > 0 and row['in_longest_path'] else 0
    
    # Write CSV
    fieldnames = ['node_name', 'latency_ms', 'percentage_of_total', 
                  'percentage_of_longest_path', 'in_longest_path', 'num_paths']
    
    with open(output_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    
    print(f"\nCSV exported to: {output_path}")
    print(f"Total nodes: {len(rows)}")
    print(f"Total latency: {total_latency:.2f} ms")
    print(f"Longest path duration: {longest_path_duration:.2f} ms")
    
    return rows


def create_cumulative_chart(rows, output_path):
    """Create cumulative latency contribution chart."""
    
    if not rows:
        print("No data for cumulative chart")
        return
    
    # Prepare data
    node_names = [r['node_name'].split('/')[-1][:20] for r in rows[:20]]  # Top 20, truncated names
    latencies = [r['latency_ms'] for r in rows[:20]]
    percentages = [r['percentage_of_total'] for r in rows[:20]]
    
    # Create figure with two subplots
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 10))
    
    # Bar chart of latencies
    bars = ax1.barh(range(len(node_names)), latencies, color='steelblue')
    ax1.set_yticks(range(len(node_names)))
    ax1.set_yticklabels(node_names)
    ax1.invert_yaxis()
    ax1.set_xlabel('Latency (ms)')
    ax1.set_title('Top 20 Nodes by Latency Contribution')
    
    # Add percentage labels
    for i, (lat, pct) in enumerate(zip(latencies, percentages)):
        ax1.text(lat + 0.1, i, f'{pct:.1f}%', va='center', fontsize=8)
    
    # Cumulative chart
    cumulative = np.cumsum(percentages)
    ax2.fill_between(range(len(node_names)), cumulative, alpha=0.3, color='steelblue')
    ax2.plot(range(len(node_names)), cumulative, 'o-', color='steelblue')
    ax2.set_xticks(range(len(node_names)))
    ax2.set_xticklabels(node_names, rotation=45, ha='right')
    ax2.set_ylabel('Cumulative Latency Contribution (%)')
    ax2.set_xlabel('Nodes (sorted by latency)')
    ax2.set_title('Cumulative Latency Contribution')
    ax2.set_ylim(0, 100)
    ax2.axhline(y=80, color='r', linestyle='--', alpha=0.5, label='80% threshold')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    plt.close()
    
    print(f"Cumulative chart saved to: {output_path}")


def create_latency_table(rows, output_path):
    """Create a formatted latency table as HTML."""
    
    html_content = """
<!DOCTYPE html>
<html>
<head>
    <title>Node Latency Rankings</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        tr:hover { background-color: #ddd; }
        .high { background-color: #ffcccc; }
        .medium { background-color: #ffffcc; }
        .low { background-color: #ccffcc; }
    </style>
</head>
<body>
    <h1>Node Latency Rankings</h1>
    <p>Sorted by latency contribution (highest first)</p>
    <table>
        <tr>
            <th>Rank</th>
            <th>Node Name</th>
            <th>Latency (ms)</th>
            <th>% of Total</th>
            <th>% of Longest Path</th>
            <th>In Longest Path</th>
        </tr>
"""
    
    for i, row in enumerate(rows, 1):
        # Determine row class based on percentage
        if row['percentage_of_total'] > 10:
            row_class = 'high'
        elif row['percentage_of_total'] > 5:
            row_class = 'medium'
        else:
            row_class = 'low'
        
        html_content += f"""
        <tr class="{row_class}">
            <td>{i}</td>
            <td>{row['node_name']}</td>
            <td>{row['latency_ms']:.3f}</td>
            <td>{row['percentage_of_total']:.2f}%</td>
            <td>{row['percentage_of_longest_path']:.2f}%</td>
            <td>{'Yes' if row['in_longest_path'] else 'No'}</td>
        </tr>
"""
    
    html_content += """
    </table>
</body>
</html>
"""
    
    with open(output_path, 'w') as f:
        f.write(html_content)
    
    print(f"HTML table saved to: {output_path}")


def main():
    """Main entry point."""
    print("=" * 60)
    print("Node Latency Export Script")
    print("=" * 60)
    
    # Load configuration
    config_path = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    config = load_config(config_path)
    
    lstrip_s = config.get('lstrip_s', 5)
    rstrip_s = config.get('rstrip_s', 2)
    
    # Create output directories
    results_dir = Path(config.get('output_dir', SCRIPT_DIR / 'results'))
    graphs_dir = Path(config.get('graphs_dir', SCRIPT_DIR / 'graphs'))
    results_dir.mkdir(parents=True, exist_ok=True)
    graphs_dir.mkdir(parents=True, exist_ok=True)
    
    # Load CARET data
    app, arch, lttng = load_caret_data(config)
    
    # Compute node latencies
    node_latencies, path_info, longest_duration, longest_nodes = compute_node_latencies(
        app, arch, lstrip_s, rstrip_s
    )
    
    # Export to CSV
    csv_path = results_dir / "node_latency_ranking.csv"
    rows = export_to_csv(node_latencies, path_info, longest_duration, 
                         longest_nodes, csv_path)
    
    # Create cumulative chart
    chart_path = graphs_dir / "cumulative_latency_chart.png"
    create_cumulative_chart(rows, chart_path)
    
    # Create HTML table
    table_path = graphs_dir / "node_latency_table.html"
    create_latency_table(rows, table_path)
    
    print("\n" + "=" * 60)
    print("Export complete!")
    print("=" * 60)
    print(f"\nOutput files:")
    print(f"  CSV:   {csv_path}")
    print(f"  Chart: {chart_path}")
    print(f"  Table: {table_path}")


if __name__ == '__main__':
    main()
