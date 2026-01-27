#!/usr/bin/env python3
"""
Merge Latency with Node Info Script
=============================================================================
Merges CARET node latency CSV with node inventory CSV to create a complete
dataset with package/executable information needed for single node replayer.

Usage: python3 merge_latency_with_info.py [config.yaml]
=============================================================================
"""

import os
import sys
import csv
import yaml
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent


def load_config(config_path=None):
    """Load configuration file."""
    if config_path is None:
        config_path = SCRIPT_DIR / "config.yaml"
    
    if not config_path.exists():
        print(f"ERROR: Config file not found: {config_path}")
        sys.exit(1)
    
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)
    
    # Expand environment variables in paths
    for key in config:
        if isinstance(config[key], str) and '${' in config[key]:
            config[key] = os.path.expandvars(config[key])
    
    return config


def load_latency_csv(csv_path):
    """Load node latency CSV from CARET analysis."""
    if not Path(csv_path).exists():
        print(f"ERROR: Latency CSV not found: {csv_path}")
        print("Run CARET analysis scripts first:")
        print("  cd ../1_caret_tracing")
        print("  python3 export_node_latency.py")
        sys.exit(1)
    
    data = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append(row)
    
    print(f"Loaded {len(data)} nodes from latency CSV")
    return data


def load_inventory_csv(csv_path):
    """Load node inventory CSV from identify_nodes."""
    if not Path(csv_path).exists():
        print(f"ERROR: Node inventory CSV not found: {csv_path}")
        print("Run collect_node_info.sh while Autoware is running")
        sys.exit(1)
    
    data = {}
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Use node name as key
            node_name = row.get('Node Name', row.get('node_name', ''))
            if node_name:
                data[node_name] = {
                    'namespace': row.get('Namespace', row.get('namespace', '/')),
                    'package': row.get('Package', row.get('package', 'Unknown')),
                    'executable': row.get('Executable', row.get('executable', 'Unknown'))
                }
    
    print(f"Loaded {len(data)} nodes from inventory CSV")
    return data


def extract_node_name(full_path):
    """Extract node name from full path like /namespace/node_name."""
    if not full_path:
        return ''
    parts = full_path.strip('/').split('/')
    return parts[-1] if parts else full_path


def merge_data(latency_data, inventory_data):
    """Merge latency data with node inventory."""
    merged = []
    matched = 0
    unmatched = 0
    
    for row in latency_data:
        node_path = row.get('node_name', '')
        node_name = extract_node_name(node_path)
        
        # Try to find in inventory
        node_info = None
        
        # Try exact match first
        if node_name in inventory_data:
            node_info = inventory_data[node_name]
            matched += 1
        else:
            # Try partial match
            for inv_name, inv_data in inventory_data.items():
                if node_name in inv_name or inv_name in node_name:
                    node_info = inv_data
                    matched += 1
                    break
        
        if node_info is None:
            unmatched += 1
            node_info = {
                'namespace': '/',
                'package': 'Unknown',
                'executable': 'Unknown'
            }
        
        merged_row = {
            'node_name': node_path,
            'short_name': node_name,
            'namespace': node_info['namespace'],
            'package': node_info['package'],
            'executable': node_info['executable'],
            'latency_ms': row.get('latency_ms', '0'),
            'percentage_of_total': row.get('percentage_of_total', '0'),
            'percentage_of_longest_path': row.get('percentage_of_longest_path', '0'),
            'in_longest_path': row.get('in_longest_path', 'False')
        }
        merged.append(merged_row)
    
    print(f"\nMerge results:")
    print(f"  Matched: {matched}")
    print(f"  Unmatched: {unmatched}")
    
    return merged


def save_merged_csv(data, output_path):
    """Save merged data to CSV."""
    if not data:
        print("ERROR: No data to save")
        return
    
    fieldnames = list(data[0].keys())
    
    with open(output_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(data)
    
    print(f"\nSaved merged data to: {output_path}")


def main():
    """Main entry point."""
    print("=" * 60)
    print("Merge Latency with Node Info")
    print("=" * 60)
    
    # Load configuration
    config_path = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    config = load_config(config_path)
    
    # Resolve paths
    latency_csv = Path(SCRIPT_DIR) / config['node_latency_csv']
    inventory_csv = Path(SCRIPT_DIR) / config['node_inventory_csv']
    
    # Load data
    latency_data = load_latency_csv(latency_csv)
    inventory_data = load_inventory_csv(inventory_csv)
    
    # Merge
    merged_data = merge_data(latency_data, inventory_data)
    
    # Sort by latency (highest first)
    merged_data.sort(key=lambda x: float(x['latency_ms']), reverse=True)
    
    # Save
    output_path = SCRIPT_DIR / "merged_node_data.csv"
    save_merged_csv(merged_data, output_path)
    
    # Show top nodes
    print("\n" + "=" * 60)
    print("Top 10 nodes by latency:")
    print("=" * 60)
    print(f"{'Rank':<5} {'Package':<30} {'Executable':<25} {'Latency(ms)':<12}")
    print("-" * 72)
    for i, row in enumerate(merged_data[:10], 1):
        print(f"{i:<5} {row['package'][:29]:<30} {row['executable'][:24]:<25} {float(row['latency_ms']):>10.3f}")


if __name__ == '__main__':
    main()
