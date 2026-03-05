# Profiling the Remaining 9 Autoware Nodes

## Current State

The pipeline (CARET → isolation → perf → miniperf → comparison) has produced results for **6 of 15** CARET-ranked nodes. The 6 profiled are: `ndt_scan_matcher`, `ekf_localizer`, `multi_object_tracker`, `map_based_prediction`, `shape_estimation`, and `behavior_path_planner` (via `behavior_planning_container`).

---

## Group A — Have Container-Level perf/miniperf Data (4 nodes)

| CARET Node | Container with data | Latency | On longest path |
|---|---|---|---|
| `motion_velocity_planner` | `motion_planning_container` | 120 ms | Yes |
| `mission_planner` | `mission_planner_container` | 70 ms | No |
| `trajectory_follower_controller` | `control_container` | 30 ms | No |
| `velocity_smoother` | `velocity_smoother_container` | 20 ms | No |

These nodes were loaded as ROS 2 **component nodes** inside a container process. Perf stat and miniperf profiled the entire container, so the data includes overhead from the container runtime and potentially other co-loaded components.

## Group B — Completely Unprofiled (5 nodes)

| CARET Node | Package | Latency | On longest path |
|---|---|---|---|
| `lidar_centerpoint` | `lidar_centerpoint` | 150 ms | Yes |
| `euclidean_cluster` | `euclidean_cluster` | 100 ms | Yes |
| `autonomous_emergency_braking` | `autonomous_emergency_braking` | 60 ms | No |
| `occupancy_grid_map_node` | `probabilistic_occupancy_grid_map` | 50 ms | No |
| `pointcloud_concatenate_data` | `pointcloud_preprocessor` | 10 ms | No |

No isolation recordings, no perf data, no miniperf data.

---

## Profiling Options

### 1. Complete the Existing Pipeline (isolation → perf stat → miniperf roofline)

Most consistent approach — produces directly comparable results with the 6 already-profiled nodes.

**Steps for each node:**
1. Record with `ros2_single_node_replayer` (creates rosbag + run script)
2. Run `run_perf_clusters.sh <node>` for hardware counter data
3. Build instrumented binary with `build_instrumented_nodes.sh <node>` (Clang-19 + miniperf LLVM pass)
4. Run `run_miniperf_roofline.sh <node>` for FLOPs/byte roofline

**Works well for:** `euclidean_cluster`, `autonomous_emergency_braking`, `occupancy_grid_map_node`, `pointcloud_concatenate_data` — all CPU-bound nodes where existing scripts work out of the box.

**Problem node: `lidar_centerpoint`** — deep learning node that offloads inference to TensorRT/CUDA on the Orin's Ampere GPU. `perf stat` only captures the CPU side (pre/post-processing, message handling). miniperf's LLVM IR instrumentation cannot capture GPU kernel execution.

### 2. Reuse Container Data for Group A (Mapping Approach)

For the 4 container-hosted nodes, perf + miniperf data exists under the container name.

**Pros:**
- No additional experiments needed
- Can be done immediately in `compare_methodologies.py` by aliasing container names to CARET node names

**Cons:**
- Container data includes runtime overhead and any co-loaded components
- Accuracy depends on whether each container hosts a single node or multiple

**Recommendation:** Check which components are loaded per container. If each container hosts a single node (likely given the isolation setup), the data is valid — map it directly.

### 3. `perf record` + Flamegraphs (Function-Level Profiling)

Use `perf record` for call-stack sampling data and flamegraph generation.

```bash
perf record -F 999 -g --call-graph dwarf -- <node_command>
perf script | stackcollapse-perf.pl | flamegraph.pl > node_flamegraph.svg
```

**Gives you:** Function-level CPU time breakdown, call-chain visibility, works inside containers (filter by function symbols to isolate a specific component).

### 4. NVIDIA Nsight Systems (Essential for `lidar_centerpoint`)

The right tool for GPU-offloading nodes on the Jetson Orin.

```bash
nsys profile --trace=cuda,nvtx,osrt \
    --output=lidar_centerpoint_profile \
    -- <node_command>
```

**Gives you:** Unified CPU + GPU timeline, TensorRT engine execution visibility, CUDA API call overhead, CPU-GPU synchronization stalls.

**Pre-installed on JetPack** at `/opt/nvidia/nsight-systems/`.

For deeper GPU kernel analysis, follow up with **Nsight Compute** (`ncu`):

```bash
ncu --target-processes all --set full \
    --output=lidar_centerpoint_kernels \
    -- <node_command>
```

This gives a **GPU-side roofline model** — directly comparable to what miniperf provides for CPU.

### 5. `tegrastats` (Jetson-Specific Coarse Monitoring)

```bash
tegrastats --interval 100 --logfile node_tegrastats.log &
# ... run node ...
kill %1
```

**Gives you:** Per-core CPU utilization, GPU utilization, memory bandwidth usage, thermal, power draw. Low overhead, 100ms granularity.

### 6. ARM SPE (Statistical Profiling Extension)

The Cortex-A78AE cores support ARM SPE for hardware-sampled memory access tracing.

```bash
perf record -e arm_spe_0// -- <node_command>
perf report
```

**Gives you:** Per-load/store access latency, cache level serviced, TLB hit/miss. Identifies *why* cache misses happen (complements perf stat MPKI numbers).

**Caveat:** Check availability: `perf list | grep arm_spe`.

### 7. `ros2_tracing` (Alternative/Complement to CARET)

59 packages were not built with `caret-rclcpp`. `ros2_tracing` (LTTng-based) doesn't require special rclcpp builds.

```bash
ros2 trace -s my_session -e callback_start callback_end ...
```

**Gives you:** Callback execution times for all nodes, even those without caret-rclcpp.

---

## Recommended Strategy by Node

| Node | Priority | Approach |
|---|---|---|
| **lidar_centerpoint** | Highest (rank 1, longest path) | Nsight Systems + Nsight Compute for GPU roofline. Perf stat for CPU fraction. Skip miniperf. |
| **euclidean_cluster** | High (rank 6, longest path) | Full existing pipeline. Pure CPU PCL clustering. |
| **motion_velocity_planner** | Medium (rank 4, longest path) | Map `motion_planning_container` data. Optionally re-isolate. |
| **mission_planner** | Medium (rank 9) | Map `mission_planner_container` data. |
| **autonomous_emergency_braking** | Medium (rank 10) | Full existing pipeline. CPU-only safety module. |
| **occupancy_grid_map_node** | Lower (rank 11) | Full existing pipeline. CPU-based grid computation. |
| **trajectory_follower_controller** | Lower (rank 13) | Map `control_container` data. |
| **velocity_smoother** | Lower (rank 14) | Map `velocity_smoother_container` data. |
| **pointcloud_concatenate_data** | Lowest (rank 15) | Full existing pipeline if desired. Likely memory-bound. |

---

## Summary

- **Quickest wins:** Map the 4 container names to their CARET counterparts — fills 4/9 gaps immediately.
- **Standard pipeline:** For `euclidean_cluster`, `autonomous_emergency_braking`, `occupancy_grid_map_node`, `pointcloud_concatenate_data`.
- **Special treatment for `lidar_centerpoint`:** Requires Nsight Systems/Compute for GPU roofline.
- **Bonus:** Re-run CARET (or `ros2_tracing`) with real trace data to validate latency rankings.
