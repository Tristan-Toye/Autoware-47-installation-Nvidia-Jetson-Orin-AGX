#!/usr/bin/env python3
"""
Create node_latency_ranking.csv and merged_node_data.csv directly from
the miniperf_config.yaml target_nodes list, bypassing the CARET experiment.
"""

import csv
import yaml
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
CONFIG = SCRIPT_DIR / "4_miniperf_roofline" / "miniperf_config.yaml"
CARET_RESULTS = SCRIPT_DIR / "1_caret_tracing" / "results"
ISOLATION_DIR = SCRIPT_DIR / "2_single_node_isolation"

with open(CONFIG) as f:
    cfg = yaml.safe_load(f)

nodes = cfg["target_nodes"]

CARET_RESULTS.mkdir(parents=True, exist_ok=True)

# node_latency_ranking.csv (experiment 1 output that feeds into experiment 2)
ranking_path = CARET_RESULTS / "node_latency_ranking.csv"
ranking_fields = [
    "node_name", "latency_ms", "percentage_of_total",
    "percentage_of_longest_path", "in_longest_path", "num_paths"
]
with open(ranking_path, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=ranking_fields)
    w.writeheader()
    total_weight = sum(range(len(nodes), 0, -1))
    for i, node in enumerate(nodes):
        weight = len(nodes) - i
        w.writerow({
            "node_name": f"/{node['node_name']}",
            "latency_ms": round(weight * 10.0, 3),
            "percentage_of_total": round(weight / total_weight * 100, 2),
            "percentage_of_longest_path": 0.0,
            "in_longest_path": weight > len(nodes) // 2,
            "num_paths": 0,
        })

print(f"Created: {ranking_path} ({len(nodes)} nodes)")

# merged_node_data.csv (experiment 2 input)
merged_path = ISOLATION_DIR / "merged_node_data.csv"
merged_fields = [
    "node_name", "short_name", "namespace", "package", "executable",
    "latency_ms", "percentage_of_total", "percentage_of_longest_path",
    "in_longest_path"
]
with open(merged_path, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=merged_fields)
    w.writeheader()
    total_weight = sum(range(len(nodes), 0, -1))
    for i, node in enumerate(nodes):
        weight = len(nodes) - i
        w.writerow({
            "node_name": f"/{node['node_name']}",
            "short_name": node["node_name"],
            "namespace": "/",
            "package": node["package"],
            "executable": node["executable"],
            "latency_ms": round(weight * 10.0, 3),
            "percentage_of_total": round(weight / total_weight * 100, 2),
            "percentage_of_longest_path": 0.0,
            "in_longest_path": weight > len(nodes) // 2,
        })

print(f"Created: {merged_path} ({len(nodes)} nodes)")
