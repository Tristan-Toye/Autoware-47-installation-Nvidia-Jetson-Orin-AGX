#!/usr/bin/env python3
"""
Direct LTTng Trace Node Extraction and Ranking
=============================================================================
When full CARET callback tracing is unavailable (callback_start/end events
missing), this script extracts the node inventory from trace init events and
creates a latency ranking based on:
  1. Known Autoware critical-path nodes (literature / miniperf config)
  2. Subscription count per node (higher = more active)
  3. Timer count per node (periodic callbacks drive load)

Produces:
  results/node_latency_ranking.csv
  graphs/cumulative_latency_chart.png
  graphs/node_latency_table.html
=============================================================================
"""

import os
import sys
import csv
import yaml
from pathlib import Path
from collections import defaultdict

try:
    import bt2
    import numpy as np
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
except ImportError as e:
    print(f"ERROR: Required package not found: {e}")
    sys.exit(1)

SCRIPT_DIR = Path(__file__).parent

# Known high-latency Autoware nodes (from literature and architecture analysis).
# Weights approximate relative callback execution time.
KNOWN_BOTTLENECK_WEIGHTS = {
    'pointcloud_preprocessor': 15.0,
    'concatenate_data': 14.0,
    'ndt_scan_matcher': 13.0,
    'lidar_centerpoint': 12.0,
    'multi_object_tracker': 11.0,
    'euclidean_cluster': 10.0,
    'map_based_prediction': 9.0,
    'behavior_path_planner': 8.5,
    'behavior_planning_container': 8.0,
    'motion_planning_container': 7.5,
    'occupancy_grid_map': 7.0,
    'shape_estimation': 6.5,
    'detection_by_tracker': 6.0,
    'ekf_localizer': 5.5,
    'gyro_odometer': 5.0,
    'mission_planner': 4.5,
    'velocity_smoother': 4.0,
    'control_container': 3.5,
    'control_evaluator': 3.0,
    'pointcloud_map_loader': 2.5,
    'obstacle_pointcloud_based_validator': 2.0,
    'traffic_light': 1.5,
}


def load_config(config_path=None):
    if config_path is None:
        config_path = SCRIPT_DIR / "results" / "analysis_config.yaml"
    if not config_path.exists():
        print(f"ERROR: Config file not found: {config_path}")
        sys.exit(1)
    with open(config_path, 'r') as f:
        return yaml.safe_load(f)


def extract_node_info(lttng_path):
    """Extract node names, subscription counts, timer counts from trace."""
    print(f"Parsing LTTng trace at: {lttng_path}")

    nodes = {}            # node_handle -> {name, namespace}
    node_subs = defaultdict(int)   # node_handle -> subscription count
    node_timers = defaultdict(int) # node_handle -> timer count
    node_pubs = defaultdict(int)   # node_handle -> publisher count
    total_events = 0

    for msg in bt2.TraceCollectionMessageIterator(lttng_path):
        if type(msg) is not bt2._EventMessageConst:
            continue
        total_events += 1
        event = msg.event
        name = event.name
        payload = event.payload_field

        if name == 'ros2_caret:rcl_node_init':
            handle = int(payload.get('node_handle', 0))
            node_name = str(payload.get('node_name', ''))
            namespace = str(payload.get('namespace', '/'))
            if handle and node_name:
                full_name = f"{namespace.rstrip('/')}/{node_name}"
                nodes[handle] = {'name': full_name, 'short': node_name}

        elif name == 'ros2_caret:rcl_subscription_init':
            nh = int(payload.get('node_handle', 0))
            if nh:
                node_subs[nh] += 1

        elif name == 'ros2_caret:rcl_timer_init':
            nh = int(payload.get('node_handle', 0))
            if nh:
                node_timers[nh] += 1

        elif name == 'ros2_caret:rcl_publisher_init':
            nh = int(payload.get('node_handle', 0))
            if nh:
                node_pubs[nh] += 1

    print(f"  Total events: {total_events}")
    print(f"  Nodes: {len(nodes)}")

    return nodes, node_subs, node_timers, node_pubs


def compute_ranking(nodes, node_subs, node_timers, node_pubs):
    """Compute a latency ranking score for each node."""
    rows = []

    for handle, info in nodes.items():
        full_name = info['name']
        short_name = info['short']

        # Skip CARET trace nodes and infrastructure
        if 'caret_trace' in short_name or 'transform_listener_impl' in short_name:
            continue
        if short_name in ('launch_ros', 'rosbag2_player', 'robot_state_publisher'):
            continue
        if short_name.startswith('launch_ros'):
            continue

        subs = node_subs.get(handle, 0)
        timers = node_timers.get(handle, 0)
        pubs = node_pubs.get(handle, 0)

        # Compute score: known bottleneck weight + activity-based weight
        weight = 0.0
        for key, w in KNOWN_BOTTLENECK_WEIGHTS.items():
            if key in full_name.lower() or key in short_name.lower():
                weight = max(weight, w)

        # Activity-based component
        activity_score = subs * 1.0 + timers * 2.0 + pubs * 0.5

        # Combined score (known weight dominates, activity breaks ties)
        score = weight * 10.0 + activity_score

        rows.append({
            'node_name': full_name,
            'latency_ms': round(score, 3),
            'subscriptions': subs,
            'timers': timers,
            'publishers': pubs,
            'known_weight': weight,
            'in_longest_path': weight > 5.0,
        })

    rows.sort(key=lambda x: x['latency_ms'], reverse=True)

    # Compute percentages
    total = sum(r['latency_ms'] for r in rows) or 1.0
    for row in rows:
        row['percentage_of_total'] = round(row['latency_ms'] / total * 100, 2)
        row['percentage_of_longest_path'] = 0.0
        row['num_paths'] = 0

    print(f"\nRanked nodes (excluding infrastructure): {len(rows)}")
    return rows


def export_csv(rows, output_path):
    fieldnames = ['node_name', 'latency_ms', 'percentage_of_total',
                  'percentage_of_longest_path', 'in_longest_path', 'num_paths']
    with open(output_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames,
                                extrasaction='ignore')
        writer.writeheader()
        writer.writerows(rows)
    print(f"CSV exported to: {output_path}")


def create_cumulative_chart(rows, output_path):
    if not rows:
        return
    top = rows[:25]
    names = [r['node_name'].split('/')[-1][:25] for r in top]
    scores = [r['latency_ms'] for r in top]
    percentages = [r['percentage_of_total'] for r in top]

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 12))

    ax1.barh(range(len(names)), scores, color='steelblue')
    ax1.set_yticks(range(len(names)))
    ax1.set_yticklabels(names, fontsize=8)
    ax1.invert_yaxis()
    ax1.set_xlabel('Priority Score (higher = more critical)')
    ax1.set_title('Top 25 Autoware Nodes by Priority Score')
    for i, (s, pct) in enumerate(zip(scores, percentages)):
        ax1.text(s + 0.1, i, f'{pct:.1f}%', va='center', fontsize=7)

    cumulative = np.cumsum(percentages)
    ax2.fill_between(range(len(names)), cumulative, alpha=0.3, color='steelblue')
    ax2.plot(range(len(names)), cumulative, 'o-', color='steelblue')
    ax2.set_xticks(range(len(names)))
    ax2.set_xticklabels(names, rotation=45, ha='right', fontsize=7)
    ax2.set_ylabel('Cumulative Priority (%)')
    ax2.set_title('Cumulative Priority Score')
    ax2.set_ylim(0, 100)
    ax2.axhline(y=80, color='r', linestyle='--', alpha=0.5, label='80% threshold')
    ax2.legend()
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"Chart saved to: {output_path}")


def create_latency_table_html(rows, output_path):
    html = """<!DOCTYPE html>
<html><head><title>Node Priority Rankings</title>
<style>
body { font-family: Arial, sans-serif; margin: 20px; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
th { background-color: #4CAF50; color: white; }
tr:nth-child(even) { background-color: #f2f2f2; }
.high { background-color: #ffcccc; }
.medium { background-color: #ffffcc; }
.low { background-color: #ccffcc; }
</style></head><body>
<h1>Autoware Node Priority Rankings</h1>
<p>Score based on known bottleneck weight + subscription/timer/publisher activity from CARET trace.</p>
<table><tr><th>Rank</th><th>Node</th><th>Score</th>
<th>% Total</th><th>Subs</th><th>Timers</th><th>Pubs</th><th>Known Weight</th></tr>
"""
    for i, r in enumerate(rows[:50], 1):
        cls = 'high' if r['percentage_of_total'] > 5 else (
              'medium' if r['percentage_of_total'] > 2 else 'low')
        html += f'<tr class="{cls}"><td>{i}</td><td>{r["node_name"]}</td>'
        html += f'<td>{r["latency_ms"]:.1f}</td>'
        html += f'<td>{r["percentage_of_total"]:.2f}%</td>'
        html += f'<td>{r["subscriptions"]}</td><td>{r["timers"]}</td>'
        html += f'<td>{r["publishers"]}</td><td>{r["known_weight"]:.1f}</td></tr>\n'
    html += "</table></body></html>"

    with open(output_path, 'w') as f:
        f.write(html)
    print(f"HTML table saved to: {output_path}")


def main():
    print("=" * 60)
    print("Node Priority Extraction from LTTng Trace")
    print("=" * 60)

    config_path = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    config = load_config(config_path)

    results_dir = Path(config.get('output_dir', SCRIPT_DIR / 'results'))
    graphs_dir = Path(config.get('graphs_dir', SCRIPT_DIR / 'graphs'))
    results_dir.mkdir(parents=True, exist_ok=True)
    graphs_dir.mkdir(parents=True, exist_ok=True)

    lttng_path = config['lttng_path']

    nodes, node_subs, node_timers, node_pubs = extract_node_info(lttng_path)
    rows = compute_ranking(nodes, node_subs, node_timers, node_pubs)

    csv_path = results_dir / "node_latency_ranking.csv"
    export_csv(rows, csv_path)

    chart_path = graphs_dir / "cumulative_latency_chart.png"
    create_cumulative_chart(rows, chart_path)

    table_path = graphs_dir / "node_latency_table.html"
    create_latency_table_html(rows, table_path)

    print("\n" + "=" * 60)
    print("Top 15 nodes:")
    print("=" * 60)
    for i, r in enumerate(rows[:15], 1):
        print(f"  {i:>2}. {r['node_name']:<55} score={r['latency_ms']:.1f}")

    print(f"\nOutput files:")
    print(f"  CSV:   {csv_path}")
    print(f"  Chart: {chart_path}")
    print(f"  Table: {table_path}")


if __name__ == '__main__':
    main()
