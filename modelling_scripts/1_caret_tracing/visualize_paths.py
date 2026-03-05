#!/usr/bin/env python3
"""
Autoware Node Path Analysis & Unified DAG Visualization
========================================================
Enumerates all dataflow paths through the 15 CARET-profiled Autoware nodes,
ranks them by cumulative latency, and produces:
  1. A ranked bar chart of all paths (longest → shortest)
  2. Individual path diagrams showing node latency contributions
  3. A unified unidirectional DAG from a single SENSOR_INPUT node
     to a single VEHICLE_OUTPUT node

The node graph is constructed from the known Autoware Universe ROS 2
topic-level dataflow for the 15 nodes identified in the CARET experiment.
"""

import csv
import os
import textwrap
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import networkx as nx
import numpy as np

SCRIPT_DIR = Path(__file__).resolve().parent
RESULTS_DIR = SCRIPT_DIR / "results"
GRAPHS_DIR = SCRIPT_DIR / "graphs"
LATENCY_CSV = RESULTS_DIR / "node_latency_ranking.csv"

GRAPHS_DIR.mkdir(parents=True, exist_ok=True)

# ── Colour palette by Autoware subsystem ────────────────────────────────────
SUBSYSTEM_COLOURS = {
    "sensing":      "#4FC3F7",
    "localization": "#81C784",
    "perception":   "#FFB74D",
    "planning":     "#CE93D8",
    "control":      "#EF5350",
    "safety":       "#FF8A65",
    "io":           "#90A4AE",
}

NODE_SUBSYSTEM = {
    "SENSOR_INPUT":                "io",
    "pointcloud_concatenate_data": "sensing",
    "ndt_scan_matcher":            "localization",
    "ekf_localizer":               "localization",
    "lidar_centerpoint":           "perception",
    "euclidean_cluster":           "perception",
    "shape_estimation":            "perception",
    "multi_object_tracker":        "perception",
    "map_based_prediction":        "perception",
    "occupancy_grid_map_node":     "perception",
    "mission_planner":             "planning",
    "behavior_path_planner":       "planning",
    "motion_velocity_planner":     "planning",
    "velocity_smoother":           "control",
    "trajectory_follower_controller": "control",
    "autonomous_emergency_braking": "safety",
    "VEHICLE_OUTPUT":              "io",
}

# ── Autoware dataflow edges (topic-level dependencies) ──────────────────────
# Each tuple is (source, target).  These represent the ROS 2 topic-level
# dataflow between the 15 CARET nodes, plus virtual SENSOR_INPUT/VEHICLE_OUTPUT.
EDGES = [
    ("SENSOR_INPUT", "pointcloud_concatenate_data"),

    # Sensing → downstream consumers
    ("pointcloud_concatenate_data", "ndt_scan_matcher"),
    ("pointcloud_concatenate_data", "lidar_centerpoint"),
    ("pointcloud_concatenate_data", "euclidean_cluster"),
    ("pointcloud_concatenate_data", "occupancy_grid_map_node"),

    # Localization chain
    ("ndt_scan_matcher", "ekf_localizer"),

    # Perception – detection branch 1 (DNN)
    ("lidar_centerpoint", "multi_object_tracker"),

    # Perception – detection branch 2 (clustering)
    ("euclidean_cluster", "shape_estimation"),
    ("shape_estimation", "multi_object_tracker"),

    # Perception – tracking → prediction
    ("multi_object_tracker", "map_based_prediction"),

    # Localization feeds planning
    ("ekf_localizer", "behavior_path_planner"),

    # Localization feeds mission planner (current pose for route)
    ("ekf_localizer", "mission_planner"),

    # Prediction feeds planning and safety
    ("map_based_prediction", "behavior_path_planner"),
    ("map_based_prediction", "autonomous_emergency_braking"),

    # Occupancy grid feeds planning
    ("occupancy_grid_map_node", "behavior_path_planner"),

    # Mission planner feeds behavior planner (route)
    ("mission_planner", "behavior_path_planner"),

    # Planning chain
    ("behavior_path_planner", "motion_velocity_planner"),

    # Control chain
    ("motion_velocity_planner", "velocity_smoother"),
    ("velocity_smoother", "trajectory_follower_controller"),

    # Localization feeds safety (ego pose)
    ("ekf_localizer", "autonomous_emergency_braking"),

    # Outputs
    ("trajectory_follower_controller", "VEHICLE_OUTPUT"),
    ("autonomous_emergency_braking", "VEHICLE_OUTPUT"),
]


def load_latencies() -> dict[str, float]:
    """Load per-node latency from CARET CSV. Virtual nodes get 0 ms."""
    latencies = {"SENSOR_INPUT": 0.0, "VEHICLE_OUTPUT": 0.0}
    with open(LATENCY_CSV) as f:
        reader = csv.DictReader(f)
        for row in reader:
            name = row["node_name"].strip().lstrip("/")
            latencies[name] = float(row["latency_ms"])
    return latencies


def build_graph() -> nx.DiGraph:
    G = nx.DiGraph()
    G.add_edges_from(EDGES)
    return G


def enumerate_paths(G: nx.DiGraph, latencies: dict) -> list[dict]:
    """Find all simple paths from SENSOR_INPUT to VEHICLE_OUTPUT."""
    paths = []
    for path_nodes in nx.all_simple_paths(G, "SENSOR_INPUT", "VEHICLE_OUTPUT"):
        total = sum(latencies.get(n, 0.0) for n in path_nodes)
        paths.append({
            "nodes": path_nodes,
            "total_ms": total,
            "node_latencies": [latencies.get(n, 0.0) for n in path_nodes],
        })
    paths.sort(key=lambda p: p["total_ms"], reverse=True)
    for i, p in enumerate(paths):
        p["rank"] = i + 1
    return paths


def short_label(name: str, max_len: int = 18) -> str:
    if name in ("SENSOR_INPUT", "VEHICLE_OUTPUT"):
        return name
    return name[:max_len]


# ── FIGURE 1: Ranked bar chart of all paths ─────────────────────────────────

def plot_ranked_paths(paths: list[dict]):
    n = len(paths)
    fig, ax = plt.subplots(figsize=(14, max(6, n * 0.55)))

    y_pos = np.arange(n)
    bars = ax.barh(
        y_pos,
        [p["total_ms"] for p in paths],
        color=[plt.cm.RdYlGn_r(i / max(n - 1, 1)) for i in range(n)],
        edgecolor="white",
        height=0.7,
    )

    for i, p in enumerate(paths):
        inner_nodes = [n for n in p["nodes"] if n not in ("SENSOR_INPUT", "VEHICLE_OUTPUT")]
        label = " → ".join(short_label(n, 14) for n in inner_nodes)
        ax.text(
            p["total_ms"] + 5, i, f'{p["total_ms"]:.0f} ms',
            va="center", fontsize=8, fontweight="bold",
        )
        ax.text(
            5, i, label,
            va="center", fontsize=6.5, color="white", fontweight="bold",
            clip_on=True,
        )

    ax.set_yticks(y_pos)
    ax.set_yticklabels([f"Path {p['rank']}" for p in paths], fontsize=9)
    ax.invert_yaxis()
    ax.set_xlabel("Cumulative Path Latency (ms)", fontsize=11)
    ax.set_title("All Dataflow Paths Through Autoware (Ranked Longest → Shortest)", fontsize=13, fontweight="bold")
    ax.axvline(x=paths[0]["total_ms"], color="red", linestyle="--", alpha=0.3, label="Longest path")
    ax.legend(fontsize=9)

    fig.tight_layout()
    out = GRAPHS_DIR / "path_ranking.png"
    fig.savefig(out, dpi=180)
    plt.close(fig)
    print(f"  [1/3] Saved ranked path chart → {out}")


# ── FIGURE 2: Stacked latency breakdown per path ────────────────────────────

def plot_path_breakdown(paths: list[dict], latencies: dict):
    n = len(paths)
    all_nodes_ordered = []
    for p in paths:
        for node in p["nodes"]:
            if node not in all_nodes_ordered and node not in ("SENSOR_INPUT", "VEHICLE_OUTPUT"):
                all_nodes_ordered.append(node)

    fig, ax = plt.subplots(figsize=(16, max(6, n * 0.55)))
    y_pos = np.arange(n)

    for p_idx, p in enumerate(paths):
        left = 0.0
        for node, lat in zip(p["nodes"], p["node_latencies"]):
            if node in ("SENSOR_INPUT", "VEHICLE_OUTPUT"):
                continue
            subsys = NODE_SUBSYSTEM.get(node, "io")
            colour = SUBSYSTEM_COLOURS[subsys]
            ax.barh(p_idx, lat, left=left, height=0.65, color=colour, edgecolor="white", linewidth=0.5)
            if lat > 25:
                ax.text(
                    left + lat / 2, p_idx,
                    f"{short_label(node, 12)}\n{lat:.0f}ms",
                    ha="center", va="center", fontsize=5.5, fontweight="bold", color="black",
                )
            left += lat

    ax.set_yticks(y_pos)
    ax.set_yticklabels([f"Path {p['rank']} ({p['total_ms']:.0f} ms)" for p in paths], fontsize=8)
    ax.invert_yaxis()
    ax.set_xlabel("Cumulative Latency (ms)", fontsize=11)
    ax.set_title("Per-Node Latency Contribution in Each Path", fontsize=13, fontweight="bold")

    legend_handles = [
        mpatches.Patch(color=SUBSYSTEM_COLOURS[s], label=s.capitalize())
        for s in ["sensing", "localization", "perception", "planning", "control", "safety"]
    ]
    ax.legend(handles=legend_handles, loc="lower right", fontsize=8, ncol=3)

    fig.tight_layout()
    out = GRAPHS_DIR / "path_latency_breakdown.png"
    fig.savefig(out, dpi=180)
    plt.close(fig)
    print(f"  [2/3] Saved latency breakdown  → {out}")


# ── FIGURE 3: Unified unidirectional DAG ────────────────────────────────────

def _layered_positions(G: nx.DiGraph) -> dict:
    """
    Compute x/y positions using topological layers.
    Nodes in the same layer are spread vertically.
    """
    topo_order = list(nx.topological_sort(G))
    layer_of = {}
    for node in topo_order:
        preds = list(G.predecessors(node))
        if not preds:
            layer_of[node] = 0
        else:
            layer_of[node] = max(layer_of[p] for p in preds) + 1

    layers: dict[int, list[str]] = {}
    for node, layer in layer_of.items():
        layers.setdefault(layer, []).append(node)

    max_layer = max(layers.keys())
    pos = {}
    for layer_idx, nodes in layers.items():
        x = layer_idx / max(max_layer, 1) * 10
        n_nodes = len(nodes)
        for j, node in enumerate(nodes):
            y = -(j - (n_nodes - 1) / 2) * 1.8
            pos[node] = (x, y)
    return pos


def plot_unified_dag(G: nx.DiGraph, latencies: dict, paths: list[dict]):
    fig, ax = plt.subplots(figsize=(22, 12))
    pos = _layered_positions(G)

    node_colours = []
    node_sizes = []
    labels = {}
    for node in G.nodes():
        subsys = NODE_SUBSYSTEM.get(node, "io")
        node_colours.append(SUBSYSTEM_COLOURS[subsys])
        lat = latencies.get(node, 0.0)
        if node in ("SENSOR_INPUT", "VEHICLE_OUTPUT"):
            node_sizes.append(1800)
            labels[node] = node.replace("_", "\n")
        else:
            node_sizes.append(800 + lat * 12)
            labels[node] = f"{node}\n({lat:.0f} ms)"

    # Find the longest path for highlighting
    longest_path_nodes = set(paths[0]["nodes"]) if paths else set()
    longest_path_edges = set()
    if paths:
        lp = paths[0]["nodes"]
        for i in range(len(lp) - 1):
            longest_path_edges.add((lp[i], lp[i + 1]))

    edge_colours = []
    edge_widths = []
    edge_styles = []
    for u, v in G.edges():
        if (u, v) in longest_path_edges:
            edge_colours.append("#D32F2F")
            edge_widths.append(3.0)
            edge_styles.append("solid")
        else:
            edge_colours.append("#78909C")
            edge_widths.append(1.5)
            edge_styles.append("solid")

    nx.draw_networkx_edges(
        G, pos, ax=ax,
        edge_color=edge_colours, width=edge_widths,
        arrows=True, arrowsize=18, arrowstyle="-|>",
        connectionstyle="arc3,rad=0.08",
        min_source_margin=20, min_target_margin=20,
    )
    nx.draw_networkx_nodes(
        G, pos, ax=ax,
        node_color=node_colours, node_size=node_sizes,
        edgecolors="white", linewidths=2,
    )
    nx.draw_networkx_labels(
        G, pos, labels, ax=ax,
        font_size=7, font_weight="bold",
    )

    # Edge latency annotations: show the target node's latency on the edge
    edge_labels = {}
    for u, v in G.edges():
        lat = latencies.get(v, 0.0)
        if lat > 0 and v != "VEHICLE_OUTPUT":
            edge_labels[(u, v)] = f"+{lat:.0f}"
    nx.draw_networkx_edge_labels(
        G, pos, edge_labels, ax=ax,
        font_size=6, font_color="#546E7A", label_pos=0.35,
    )

    legend_handles = [
        mpatches.Patch(color=SUBSYSTEM_COLOURS[s], label=s.capitalize())
        for s in ["io", "sensing", "localization", "perception", "planning", "control", "safety"]
    ]
    legend_handles.append(
        mpatches.Patch(color="#D32F2F", label=f"Longest path ({paths[0]['total_ms']:.0f} ms)")
    )
    ax.legend(handles=legend_handles, loc="upper left", fontsize=9, ncol=2,
              framealpha=0.9, edgecolor="gray")

    ax.set_title(
        "Autoware Unified Node Architecture — Unidirectional DAG\n"
        f"(SENSOR_INPUT → VEHICLE_OUTPUT, {G.number_of_nodes()} nodes, "
        f"{G.number_of_edges()} edges, {len(paths)} paths)",
        fontsize=14, fontweight="bold",
    )
    ax.axis("off")
    fig.tight_layout()

    out = GRAPHS_DIR / "unified_dag.png"
    fig.savefig(out, dpi=180, bbox_inches="tight")
    plt.close(fig)
    print(f"  [3/3] Saved unified DAG        → {out}")


# ── Markdown report ─────────────────────────────────────────────────────────

def write_path_report(paths: list[dict]):
    out = GRAPHS_DIR / "path_analysis_report.md"
    lines = [
        "# Autoware Dataflow Path Analysis",
        "",
        f"Total paths found: **{len(paths)}** "
        "(from SENSOR\\_INPUT → VEHICLE\\_OUTPUT)",
        "",
        "## All Paths Ranked by Cumulative Latency",
        "",
    ]
    for p in paths:
        inner = [n for n in p["nodes"] if n not in ("SENSOR_INPUT", "VEHICLE_OUTPUT")]
        chain = " → ".join(f"`{n}`" for n in inner)
        lines.append(f"### Path {p['rank']} — {p['total_ms']:.0f} ms")
        lines.append("")
        lines.append(chain)
        lines.append("")
        lines.append("| Node | Latency (ms) | Cumulative (ms) |")
        lines.append("|---|---|---|")
        cum = 0.0
        for node, lat in zip(p["nodes"], p["node_latencies"]):
            if node in ("SENSOR_INPUT", "VEHICLE_OUTPUT"):
                continue
            cum += lat
            lines.append(f"| `{node}` | {lat:.0f} | {cum:.0f} |")
        lines.append("")

    lines.append("## Graphs")
    lines.append("")
    lines.append("- `path_ranking.png` — bar chart of all paths ranked longest → shortest")
    lines.append("- `path_latency_breakdown.png` — stacked latency breakdown per path")
    lines.append("- `unified_dag.png` — full unidirectional DAG from SENSOR_INPUT to VEHICLE_OUTPUT")

    out.write_text("\n".join(lines))
    print(f"  [+]   Saved report              → {out}")


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  Autoware Path Analysis & DAG Visualization")
    print("=" * 60)
    print()

    latencies = load_latencies()
    print(f"Loaded latencies for {len(latencies)} nodes")

    G = build_graph()
    print(f"Graph: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges")
    assert nx.is_directed_acyclic_graph(G), "Graph contains cycles!"

    paths = enumerate_paths(G, latencies)
    print(f"Found {len(paths)} paths from SENSOR_INPUT → VEHICLE_OUTPUT")
    print()

    for p in paths:
        inner = [n for n in p["nodes"] if n not in ("SENSOR_INPUT", "VEHICLE_OUTPUT")]
        short = " → ".join(short_label(n, 16) for n in inner)
        print(f"  Path {p['rank']:2d}  {p['total_ms']:6.0f} ms  {short}")
    print()

    plot_ranked_paths(paths)
    plot_path_breakdown(paths, latencies)
    plot_unified_dag(G, latencies, paths)
    write_path_report(paths)

    print()
    print("Done. All outputs in:", GRAPHS_DIR)


if __name__ == "__main__":
    main()
