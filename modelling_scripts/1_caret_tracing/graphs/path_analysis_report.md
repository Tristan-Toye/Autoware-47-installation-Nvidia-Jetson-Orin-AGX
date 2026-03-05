# Autoware Dataflow Path Analysis

Total paths found: **8** (from SENSOR\_INPUT → VEHICLE\_OUTPUT)

## All Paths Ranked by Cumulative Latency

### Path 1 — 630 ms

`pointcloud_concatenate_data` → `ndt_scan_matcher` → `ekf_localizer` → `mission_planner` → `behavior_path_planner` → `motion_velocity_planner` → `velocity_smoother` → `trajectory_follower_controller`

| Node | Latency (ms) | Cumulative (ms) |
|---|---|---|
| `pointcloud_concatenate_data` | 10 | 10 |
| `ndt_scan_matcher` | 140 | 150 |
| `ekf_localizer` | 110 | 260 |
| `mission_planner` | 70 | 330 |
| `behavior_path_planner` | 130 | 460 |
| `motion_velocity_planner` | 120 | 580 |
| `velocity_smoother` | 20 | 600 |
| `trajectory_follower_controller` | 30 | 630 |

### Path 2 — 630 ms

`pointcloud_concatenate_data` → `lidar_centerpoint` → `multi_object_tracker` → `map_based_prediction` → `behavior_path_planner` → `motion_velocity_planner` → `velocity_smoother` → `trajectory_follower_controller`

| Node | Latency (ms) | Cumulative (ms) |
|---|---|---|
| `pointcloud_concatenate_data` | 10 | 10 |
| `lidar_centerpoint` | 150 | 160 |
| `multi_object_tracker` | 90 | 250 |
| `map_based_prediction` | 80 | 330 |
| `behavior_path_planner` | 130 | 460 |
| `motion_velocity_planner` | 120 | 580 |
| `velocity_smoother` | 20 | 600 |
| `trajectory_follower_controller` | 30 | 630 |

### Path 3 — 620 ms

`pointcloud_concatenate_data` → `euclidean_cluster` → `shape_estimation` → `multi_object_tracker` → `map_based_prediction` → `behavior_path_planner` → `motion_velocity_planner` → `velocity_smoother` → `trajectory_follower_controller`

| Node | Latency (ms) | Cumulative (ms) |
|---|---|---|
| `pointcloud_concatenate_data` | 10 | 10 |
| `euclidean_cluster` | 100 | 110 |
| `shape_estimation` | 40 | 150 |
| `multi_object_tracker` | 90 | 240 |
| `map_based_prediction` | 80 | 320 |
| `behavior_path_planner` | 130 | 450 |
| `motion_velocity_planner` | 120 | 570 |
| `velocity_smoother` | 20 | 590 |
| `trajectory_follower_controller` | 30 | 620 |

### Path 4 — 560 ms

`pointcloud_concatenate_data` → `ndt_scan_matcher` → `ekf_localizer` → `behavior_path_planner` → `motion_velocity_planner` → `velocity_smoother` → `trajectory_follower_controller`

| Node | Latency (ms) | Cumulative (ms) |
|---|---|---|
| `pointcloud_concatenate_data` | 10 | 10 |
| `ndt_scan_matcher` | 140 | 150 |
| `ekf_localizer` | 110 | 260 |
| `behavior_path_planner` | 130 | 390 |
| `motion_velocity_planner` | 120 | 510 |
| `velocity_smoother` | 20 | 530 |
| `trajectory_follower_controller` | 30 | 560 |

### Path 5 — 390 ms

`pointcloud_concatenate_data` → `lidar_centerpoint` → `multi_object_tracker` → `map_based_prediction` → `autonomous_emergency_braking`

| Node | Latency (ms) | Cumulative (ms) |
|---|---|---|
| `pointcloud_concatenate_data` | 10 | 10 |
| `lidar_centerpoint` | 150 | 160 |
| `multi_object_tracker` | 90 | 250 |
| `map_based_prediction` | 80 | 330 |
| `autonomous_emergency_braking` | 60 | 390 |

### Path 6 — 380 ms

`pointcloud_concatenate_data` → `euclidean_cluster` → `shape_estimation` → `multi_object_tracker` → `map_based_prediction` → `autonomous_emergency_braking`

| Node | Latency (ms) | Cumulative (ms) |
|---|---|---|
| `pointcloud_concatenate_data` | 10 | 10 |
| `euclidean_cluster` | 100 | 110 |
| `shape_estimation` | 40 | 150 |
| `multi_object_tracker` | 90 | 240 |
| `map_based_prediction` | 80 | 320 |
| `autonomous_emergency_braking` | 60 | 380 |

### Path 7 — 360 ms

`pointcloud_concatenate_data` → `occupancy_grid_map_node` → `behavior_path_planner` → `motion_velocity_planner` → `velocity_smoother` → `trajectory_follower_controller`

| Node | Latency (ms) | Cumulative (ms) |
|---|---|---|
| `pointcloud_concatenate_data` | 10 | 10 |
| `occupancy_grid_map_node` | 50 | 60 |
| `behavior_path_planner` | 130 | 190 |
| `motion_velocity_planner` | 120 | 310 |
| `velocity_smoother` | 20 | 330 |
| `trajectory_follower_controller` | 30 | 360 |

### Path 8 — 320 ms

`pointcloud_concatenate_data` → `ndt_scan_matcher` → `ekf_localizer` → `autonomous_emergency_braking`

| Node | Latency (ms) | Cumulative (ms) |
|---|---|---|
| `pointcloud_concatenate_data` | 10 | 10 |
| `ndt_scan_matcher` | 140 | 150 |
| `ekf_localizer` | 110 | 260 |
| `autonomous_emergency_braking` | 60 | 320 |

## Graphs

- `path_ranking.png` — bar chart of all paths ranked longest → shortest
- `path_latency_breakdown.png` — stacked latency breakdown per path
- `unified_dag.png` — full unidirectional DAG from SENSOR_INPUT to VEHICLE_OUTPUT