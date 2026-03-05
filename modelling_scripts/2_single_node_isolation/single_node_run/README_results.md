# Experiment 2: Single Node Isolation — Results

## Overview

Standalone Autoware nodes were isolated using
[ros2_single_node_replayer](https://github.com/sykwer/ros2_single_node_replayer).
For each node, the replayer recorded:

1. A **parameter snapshot** (`.yaml`) capturing the node's runtime configuration.
2. A **rosbag** containing every topic the node subscribes to, enabling offline
   replay without the full Autoware stack.

Recording used the 30-second sample rosbag played at **0.2x speed** (~150 s
wall-time per node) to ensure slow subscribers captured all messages.

## Recorded Nodes

| Node | Parameters File | Rosbag Size |
|---|---|---|
| `ndt_scan_matcher` | `localization__pose_estimator__ndt_scan_matcher.yaml` | 192 KB |
| `ekf_localizer` | `localization__pose_twist_fusion_filter__ekf_localizer.yaml` | 188 KB |
| `multi_object_tracker` | `perception__object_recognition__tracking__multi_object_tracker.yaml` | 200 KB |
| `map_based_prediction` | `perception__object_recognition__prediction__map_based_prediction.yaml` | 380 KB |
| `shape_estimation` | `perception__object_recognition__detection__clustering__shape_estimation.yaml` | 228 KB (latest) |
| `velocity_smoother` | `planning__scenario_planning__velocity_smoother.yaml` | 228 KB |

### Nodes NOT Recorded

| Node | Reason |
|---|---|
| `lidar_centerpoint` | Runs inside a component container; not discoverable as a standalone process |
| `behavior_path_planner` | Component container |
| `motion_velocity_planner` | Component container |
| `euclidean_cluster` | Component container |
| `mission_planner` | Component container |
| `autonomous_emergency_braking` | Component container |
| `occupancy_grid_map_node` | Component container |
| `trajectory_follower_controller` | Component container |
| `pointcloud_concatenate_data` | Component container |

## Directory Structure

```
single_node_run/
├── <node_name>/
│   ├── <namespace>_<node>.yaml     # Node parameter dump
│   └── rosbag2_<timestamp>/        # Recorded input topics
│       ├── metadata.yaml
│       └── rosbag2_<timestamp>_0.db3
```

## How to Use the Recordings

Each recorded node can be replayed in isolation for targeted profiling:

```bash
# Terminal 1: Start the node with its saved parameters
source /opt/ros/humble/setup.bash
source ~/Autoware-47-installation-Nvidia-Jetson-Orin-AGX/autoware/install/setup.bash
ros2 run <package> <executable> --ros-args --params-file <node>.yaml

# Terminal 2: Play back the recorded inputs
ros2 bag play single_node_run/<node>/rosbag2_*/

# Terminal 3 (optional): Profile the running node
perf stat -e instructions,cpu-cycles,cache-misses,cache-references -p <PID>
```

## Limitations

- Only 6 of 15 target nodes could be isolated. The remaining 9 nodes run inside
  ROS2 component containers, where multiple nodes share a single process and
  cannot be individually addressed by `ros2_single_node_replayer`.
- Container-hosted nodes were instead profiled at the process level using
  `perf stat` in Experiment 3.
