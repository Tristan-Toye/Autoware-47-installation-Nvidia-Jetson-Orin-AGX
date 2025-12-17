# Autoware ROS2 Nodes Documentation

This document provides comprehensive documentation for all nodes in the Autoware ROS2 autonomous driving system, organized by functional categories.

## Table of Contents

- [ADAPI (Autoware API) Nodes](#adapi-autoware-api-nodes)
- [Control Nodes](#control-nodes)
- [Localization Nodes](#localization-nodes)
- [Map Nodes](#map-nodes)
- [Perception Nodes](#perception-nodes)
- [Planning Nodes](#planning-nodes)
- [Sensing Nodes](#sensing-nodes)
- [System Nodes](#system-nodes)
- [Utility Nodes](#utility-nodes)
- [CARET & Perf Automation](#caret--perf-automation)

---

## CARET & Perf Automation

Helper scripts under `experiments/` orchestrate CARET tracing, perf collection, and visualization pipelines. See `experiments/README.md` for detailed documentation.

- **Collect traces:** `experiments/run_caret_trace.sh --map /path/to/map --vehicle lexus --sensor aip_xx1 --runs 2 --duration 90 --session-prefix aw_trace --export-csv caretdb/node_metrics.csv`  
  Launches `ros2 launch caret_autoware_launch autoware.launch.xml` with the configured arguments, records traces under `~/.ros/tracing/<session>`, and (optionally) appends per-callback metrics to a CSV by invoking `experiments/parse_caret_trace.py`.

- **Parse traces to CSV:** `experiments/parse_caret_trace.py ~/.ros/tracing/aw_trace_* --output caretdb/node_metrics.csv --append --layer-map configs/layer_map.json`  
  Uses `caret_analyze` to aggregate mean/min/max/std latency plus callback frequency per node. Provide an optional layer-map (JSON or CSV `substring,layer`) to label nodes for later plotting.

- **Visualize CARET output:** `experiments/plot_latency_distribution.py caretdb/node_metrics.csv --group-by layer --metric mean_latency_ms --title "Layer latencies" --output plots/layer_latency.png`

- **Run perf on a node (optional CARET counts):** `experiments/run_node_perf.sh --metric-group cache --runs 3 --enable-caret --session lidar_centerpoint_perf -- ros2 run autoware_lidar_centerpoint lidar_centerpoint_node_exe`  
  Enforces ≤8 hardware counters, records raw `perf stat -x,` outputs under `perf_results/<session>/`, logs metadata (command, metrics, runs), and—when `--enable-caret` is passed—starts `ros2 caret record` to capture callback execution counts for the isolated node.

- **Parse perf outputs & plot:** `experiments/parse_perf_results.py perf_results/lidar_centerpoint_perf --output perfdb/metrics.csv --plot plots/perf_bar.png --metric value`  
  Reads every `perf_run_*.txt`, normalizes the CSV, and optionally renders a bar chart (mean metric per event) via matplotlib.

---

## ADAPI (Autoware API) Nodes

### /adapi/container

- **Link**: [Autoware Documentation - AD API](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-interfaces/ad-api/)

- **Algorithms**: Container node for managing ADAPI components lifecycle and communications

- **Summary**: Provides a containerized environment for managing multiple ADAPI nodes efficiently. Acts as a lifecycle manager and coordination point for various Autonomous Driving API components, ensuring proper initialization, execution order, and resource management across different API services.

### /adapi/node/autoware_state

- **Link**: [Autoware Documentation - AD API State](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-interfaces/ad-api/features/autoware_state/)

- **Algorithms**: State machine management for Autoware system states

- **Summary**: Manages the overall state of the Autoware system, tracking transitions between states like Initializing, WaitingForRoute, Planning, WaitingForEngage, Driving, ArrivedGoal, and Emergency. Provides state information to external applications and ensures proper state transitions based on system conditions.

### /adapi/node/diagnostics

- **Link**: [Autoware Documentation - AD API](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-interfaces/ad-api/)

- **Algorithms**: Diagnostic data aggregation and reporting

- **Summary**: Collects, processes, and exposes diagnostic information from various Autoware components through the AD API interface. Provides a unified view of system health, warnings, and errors to external monitoring systems and user interfaces.

### /adapi/node/fail_safe

- **Link**: [Autoware Documentation - Fail Safe](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-interfaces/ad-api/features/fail_safe/)

- **Algorithms**: Fail-safe trigger detection and response coordination

- **Summary**: Monitors system safety conditions and coordinates fail-safe responses when critical issues are detected. Manages transitions to safe states and communicates safety status through the AD API, ensuring the vehicle can safely handle emergency situations.

### /adapi/node/heartbeat

- **Link**: [Autoware Documentation - AD API](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-interfaces/ad-api/)

- **Algorithms**: Periodic heartbeat signal generation and monitoring

- **Summary**: Generates and monitors heartbeat signals to indicate system liveness. Provides health check mechanisms for external systems to verify that Autoware is running and responsive, enabling timely detection of system freezes or crashes.

### /adapi/node/interface

- **Link**: [Autoware Documentation - AD API](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-interfaces/ad-api/)

- **Algorithms**: API interface handling and request routing

- **Summary**: Serves as the main interface node for the Autoware AD API, handling incoming API requests and routing them to appropriate internal services. Provides abstraction between external applications and internal Autoware components.

### /adapi/node/localization

- **Link**: [Autoware Documentation - AD API Localization](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-interfaces/ad-api/features/localization/)

- **Algorithms**: Localization status monitoring and initialization management

- **Summary**: Exposes localization functionality through the AD API, including pose initialization services and localization status monitoring. Enables external applications to set initial poses and monitor localization health.

### /adapi/node/motion

- **Link**: [Autoware Documentation - AD API Motion](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-interfaces/ad-api/features/motion/)

- **Algorithms**: Motion state management and control interface

- **Summary**: Provides motion control interfaces through the AD API, managing vehicle motion states including engage/disengage commands, accepting/rejecting start requests, and monitoring motion status. Acts as the bridge between high-level motion commands and lower-level control systems.

### /adapi/node/operation_mode

- **Link**: [Autoware Documentation - AD API Operation Mode](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-interfaces/ad-api/features/operation_mode/)

- **Algorithms**: Operation mode state machine management

- **Summary**: Manages operation mode transitions (Autonomous, Local, Remote, Stop, etc.) and exposes operation mode control through the AD API. Ensures safe transitions between different operational modes and provides mode status to external systems.

### /adapi/node/routing

- **Link**: [Autoware Documentation - AD API Routing](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-interfaces/ad-api/features/routing/)

- **Algorithms**: Route request handling and route state management

- **Summary**: Provides routing services through the AD API, accepting goal poses and waypoints from external applications and managing route planning requests. Monitors route planning status and exposes route information to external systems.

---

## Control Nodes

### /control/autonomous_emergency_braking

- **Link**: [GitHub - Autonomous Emergency Braking](https://github.com/autowarefoundation/autoware.universe/tree/main/control/autoware_autonomous_emergency_braking)

- **Algorithms**: Collision prediction using time-to-collision (TTC) calculations, emergency braking command generation

- **Summary**: Monitors predicted object trajectories and generates emergency braking commands when imminent collisions are detected. Calculates time-to-collision for all perceived objects and triggers emergency braking when TTC falls below safety thresholds, providing a last-resort safety mechanism.

### /control/autoware_operation_mode_transition_manager

- **Link**: [GitHub - Operation Mode Transition Manager](https://github.com/autowarefoundation/autoware.universe/tree/main/control/autoware_operation_mode_transition_manager)

- **Algorithms**: State machine for operation mode transitions, safety condition checking

- **Summary**: Manages safe transitions between different operation modes (Stop, Autonomous, Local, Remote). Validates transition requests against safety conditions and system states, ensuring the vehicle only transitions to autonomous mode when all prerequisites are met.

### /control/autoware_shift_decider

- **Link**: [GitHub - Shift Decider](https://github.com/autowarefoundation/autoware.universe/tree/main/control/autoware_shift_decider)

- **Algorithms**: Gear shift logic based on trajectory analysis, drive/reverse decision making

- **Summary**: Determines appropriate gear shifts (Drive, Reverse, Park) based on planned trajectory direction and vehicle state. Analyzes the reference trajectory to decide when the vehicle should move forward, backward, or remain in park.

### /control/collision_detector

- **Link**: [GitHub - Collision Detector](https://github.com/autowarefoundation/autoware.universe/tree/main/control/autoware_collision_detector)

- **Algorithms**: Collision prediction using vehicle and object trajectories, polygonal overlap detection

- **Summary**: Monitors vehicle trajectory and predicted object paths to detect potential collisions. Checks for overlaps between vehicle footprint and object polygons along future trajectories, issuing warnings when collisions are imminent.

### /control/control_validator

- **Link**: [GitHub - Control Validator](https://github.com/autowarefoundation/autoware.universe/tree/main/control/autoware_control_validator)

- **Algorithms**: Control command validation against kinematic limits, command sanity checking

- **Summary**: Validates control commands before sending to vehicle interface. Checks commands against vehicle kinematic limits, rate limits, and safety bounds. Rejects invalid commands and publishes diagnostics to prevent unsafe control actions.

### /control/external_cmd_converter

- **Link**: [GitHub - External Command Converter](https://github.com/autowarefoundation/autoware.universe/tree/main/vehicle/autoware_external_cmd_converter)

- **Algorithms**: Command format conversion, unit transformation

- **Summary**: Converts external control commands from various formats into Autoware's internal control command format. Handles unit conversions, coordinate transformations, and message type conversions to enable integration with different control interfaces.

### /control/external_cmd_selector

- **Link**: [GitHub - External Command Selector](https://github.com/autowarefoundation/autoware.universe/tree/main/control/autoware_external_cmd_selector)

- **Algorithms**: Command source selection based on priority and validity

- **Summary**: Selects between multiple external command sources (remote control, emergency stop, manual intervention) based on priority rules and command validity. Ensures smooth transitions between different control sources while maintaining safety.

### /control/trajectory_follower/controller_node_exe

- **Link**: [GitHub - Trajectory Follower](https://github.com/autowarefoundation/autoware.universe/tree/main/control/autoware_trajectory_follower_node)

- **Algorithms**: MPC (Model Predictive Control) for lateral control, PID control for longitudinal control

- **Summary**: Main trajectory following controller that generates steering and acceleration commands to follow the planned trajectory. Uses MPC to predict vehicle behavior and optimize control inputs, while PID controllers handle longitudinal speed tracking.

### /control/trajectory_follower/lane_departure_checker_node

- **Link**: [GitHub - Lane Departure Checker](https://github.com/autowarefoundation/autoware.universe/tree/main/control/autoware_lane_departure_checker)

- **Algorithms**: Vehicle footprint projection, lane boundary checking

- **Summary**: Monitors vehicle position relative to lane boundaries and detects potential lane departures. Projects vehicle footprint along predicted trajectory and checks for boundary violations, issuing warnings when lane departure is imminent.

### /control/vehicle_cmd_gate

- **Link**: [GitHub - Vehicle Command Gate](https://github.com/autowarefoundation/autoware.universe/tree/main/control/autoware_vehicle_cmd_gate)

- **Algorithms**: Command gating based on system state, emergency command prioritization

- **Summary**: Acts as final gatekeeper for control commands before vehicle interface. Manages command flow based on operation mode, emergency states, and external command sources. Ensures only valid, safe commands reach the vehicle interface.

---

## Localization Nodes

### /localization/localization_error_monitor

- **Link**: [GitHub - Localization Error Monitor](https://github.com/autowarefoundation/autoware.universe/tree/main/localization/autoware_localization_error_monitor)

- **Algorithms**: Error ellipse calculation from covariance, threshold-based monitoring

- **Summary**: Monitors localization accuracy by analyzing pose covariance and comparing multiple localization sources. Calculates error ellipses and issues warnings when localization uncertainty exceeds acceptable thresholds.

### /localization/pose_estimator/ndt_scan_matcher

- **Link**: [GitHub - NDT Scan Matcher](https://github.com/autowarefoundation/autoware.universe/tree/main/localization/autoware_ndt_scan_matcher)

- **Algorithms**: Normal Distributions Transform (NDT) algorithm, Newton's method optimization, Monte Carlo initial pose estimation, Covariance estimation (Laplace approximation, Multi-NDT)

- **Summary**: Estimates vehicle pose by matching LiDAR point clouds to a pre-built map using NDT algorithm. NDT represents the map as a set of normal distributions and finds the transformation that maximizes the likelihood of the scan matching the map. Supports dynamic map loading, regularization using GNSS, and real-time covariance estimation. Handles initial pose estimation via Monte Carlo sampling.

### /localization/pose_twist_fusion_filter/ekf_localizer

- **Link**: [GitHub - EKF Localizer](https://github.com/autowarefoundation/autoware.universe/tree/main/localization/autoware_ekf_localizer)

- **Algorithms**: Extended Kalman Filter (EKF), 2D vehicle dynamics model, Mahalanobis distance gating, Time delay compensation, Automatic yaw bias estimation

- **Summary**: Fuses multiple pose and twist measurements using an Extended Kalman Filter to produce robust, smooth pose and velocity estimates. Implements time delay compensation for handling varying input latencies, automatic yaw bias estimation for sensor mounting error correction, and smooth measurement updates to prevent estimation jumps. Uses Mahalanobis distance gates for outlier detection and supports vertical correction for slope handling.

### /localization/pose_twist_fusion_filter/pose_instability_detector

- **Link**: [GitHub - Pose Instability Detector](https://github.com/autowarefoundation/autoware.universe/tree/main/localization/autoware_pose_instability_detector)

- **Algorithms**: Pose differential analysis, threshold-based stability detection

- **Summary**: Monitors pose estimates for sudden jumps or instabilities that could indicate localization failures. Analyzes pose changes over time and issues warnings when pose deltas exceed expected bounds based on vehicle dynamics.

### /localization/pose_twist_fusion_filter/stop_filter

- **Link**: [GitHub - Stop Filter](https://github.com/autowarefoundation/autoware.universe/tree/main/localization/autoware_stop_filter)

- **Algorithms**: Low-speed filtering, zero-velocity detection and correction

- **Summary**: Filters pose and velocity estimates when vehicle is stopped or moving at very low speeds. Prevents pose drift and velocity noise when the vehicle is stationary by detecting stop conditions and applying appropriate filtering.

### /localization/pose_twist_fusion_filter/twist2accel

- **Link**: [GitHub - Twist2Accel](https://github.com/autowarefoundation/autoware.universe/tree/main/localization/autoware_twist2accel)

- **Algorithms**: Numerical differentiation with filtering

- **Summary**: Calculates acceleration by differentiating velocity (twist) measurements. Applies filtering to reduce noise in acceleration estimates, providing smooth acceleration data for control and prediction modules.

### /localization/twist_estimator/gyro_odometer

- **Link**: [GitHub - Gyro Odometer](https://github.com/autowarefoundation/autoware.universe/tree/main/localization/autoware_gyro_odometer)

- **Algorithms**: IMU and wheel odometry fusion, yaw rate integration

- **Summary**: Estimates vehicle twist (linear and angular velocities) by fusing IMU gyroscope data with wheel odometry. Provides robust velocity estimates particularly useful when GNSS or other absolute positioning is unavailable.

### /localization/util/pose_initializer

- **Link**: [GitHub - Pose Initializer](https://github.com/autowarefoundation/autoware.universe/tree/main/localization/autoware_pose_initializer)

- **Algorithms**: GNSS-based initialization, map matching, user-provided pose handling

- **Summary**: Provides multiple methods for initializing vehicle pose including GNSS-based initialization, manual pose input via RViz, and automatic initialization using map matching. Manages initialization requests and coordinates with localization nodes.

---

## Map Nodes

### /map/lanelet2_map_loader

- **Link**: [GitHub - Lanelet2 Map Loader](https://github.com/autowarefoundation/autoware.universe/tree/main/map/autoware_lanelet2_map_loader)

- **Algorithms**: Lanelet2 map parsing, map data serialization

- **Summary**: Loads Lanelet2 format HD maps from files and publishes them to other Autoware components. Lanelet2 provides rich semantic information about lanes, traffic rules, and map features essential for planning and decision-making.

### /map/lanelet2_map_visualization

- **Link**: [GitHub - Lanelet2 Map Visualization](https://github.com/autowarefoundation/autoware.universe/tree/main/map/autoware_lanelet2_map_visualization)

- **Algorithms**: Map to marker conversion, visualization message generation

- **Summary**: Converts Lanelet2 map data into visualization markers for RViz display. Enables visualization of lanes, stop lines, crosswalks, traffic lights, and other map features to aid in debugging and monitoring.

### /map/map_hash_generator

- **Link**: [GitHub - Map Hash Generator](https://github.com/autowarefoundation/autoware.universe/tree/main/map/autoware_map_hash_generator)

- **Algorithms**: Hash calculation for map verification

- **Summary**: Generates hash values for map files to verify map integrity and detect changes. Ensures the correct map is loaded and prevents issues from corrupted or mismatched map files.

### /map/map_projection_loader

- **Link**: [GitHub - Map Projection Loader](https://github.com/autowarefoundation/autoware.universe/tree/main/map/autoware_map_projection_loader)

- **Algorithms**: Geographic coordinate system configuration

- **Summary**: Loads and configures map projection parameters for coordinate transformations between geographic (lat/lon) and local Cartesian coordinates. Essential for proper GNSS integration and map alignment.

### /map/pointcloud_map_loader

- **Link**: [GitHub - Pointcloud Map Loader](https://github.com/autowarefoundation/autoware.universe/tree/main/map/autoware_pointcloud_map_loader)

- **Algorithms**: PCD file loading, differential map loading, spatial indexing

- **Summary**: Loads point cloud maps for localization. Supports both static loading of entire maps and dynamic differential loading for large maps. Provides map portions to NDT scan matcher based on vehicle position, enabling handling of arbitrarily large maps.

### /map/vector_map_tf_generator

- **Link**: [GitHub - Vector Map TF Generator](https://github.com/autowarefoundation/autoware.universe/tree/main/map/autoware_vector_map_tf_generator)

- **Algorithms**: Map coordinate frame transformation generation

- **Summary**: Generates TF transformations for map coordinate frames. Publishes the relationship between map frame and other reference frames, ensuring consistent coordinate system usage across all components.

---

## Perception Nodes

### /perception/object_recognition/detection/centerpoint/lidar_centerpoint

- **Link**: [GitHub - LiDAR CenterPoint](https://github.com/autowarefoundation/autoware.universe/tree/main/perception/autoware_lidar_centerpoint)

- **Algorithms**: CenterPoint deep learning architecture, 3D object detection using voxelized point clouds, center-based detection

- **Summary**: Detects 3D objects from LiDAR point clouds using the CenterPoint neural network. CenterPoint represents objects as center points in bird's-eye view, predicting object centers, sizes, orientations, and velocities. Achieves high-performance 3D object detection for cars, pedestrians, cyclists, and other classes.

### /perception/object_recognition/detection/clustering/euclidean_cluster

- **Link**: [GitHub - Euclidean Cluster](https://github.com/autowarefoundation/autoware.universe/tree/main/perception/autoware_euclidean_cluster)

- **Algorithms**: Euclidean distance-based clustering, DBSCAN-like clustering

- **Summary**: Groups point cloud points into clusters based on Euclidean distance thresholds. Used for segmenting point clouds into distinct objects, particularly useful for detecting objects not covered by learning-based detectors or as a preprocessing step.

### /perception/object_recognition/detection/clustering/shape_estimation

- **Link**: [GitHub - Shape Estimation](https://github.com/autowarefoundation/autoware.universe/tree/main/perception/autoware_shape_estimation)

- **Algorithms**: PCA (Principal Component Analysis), L-shape fitting, bounding box estimation

- **Summary**: Estimates object shapes and oriented bounding boxes from point cloud clusters. Uses PCA for initial orientation estimation and L-shape fitting for vehicles, providing accurate object dimensions and poses for tracking and prediction.

### /perception/object_recognition/tracking/multi_object_tracker

- **Link**: [GitHub - Multi Object Tracker](https://github.com/autowarefoundation/autoware.universe/tree/main/perception/autoware_multi_object_tracker)

- **Algorithms**: Data association using muSSP (min-cost max-flow), Extended Kalman Filter (EKF) tracking, Mahalanobis distance gating, Multi-model tracking for pedestrians/bicycles

- **Summary**: Tracks detected objects over time, assigning unique IDs and estimating velocities. Uses muSSP solver for efficient data association between detections and existing tracks. Implements separate EKF models for different object classes (pedestrian, bicycle, car, large vehicle) and runs multiple models simultaneously for ambiguous classes to ensure robust tracking during class transitions.

### /perception/object_recognition/prediction/map_based_prediction

- **Link**: [GitHub - Map Based Prediction](https://github.com/autowarefoundation/autoware.universe/tree/main/perception/autoware_map_based_prediction)

- **Algorithms**: Lanelet-based path prediction, physics-based motion models, multiple hypothesis generation

- **Summary**: Predicts future trajectories of tracked objects using map information and motion models. Generates multiple hypothesis paths considering lane following, lane changes, and turn behaviors based on lanelet connectivity and object dynamics.

### /perception/traffic_light_recognition/traffic_light_arbiter

- **Link**: [GitHub - Traffic Light Arbiter](https://github.com/autowarefoundation/autoware.universe/tree/main/perception/autoware_traffic_light_arbiter)

- **Algorithms**: Multi-source fusion, confidence-based arbitration

- **Summary**: Combines traffic light recognition results from multiple cameras or sources, arbitrating between potentially conflicting detections. Selects most reliable traffic light states based on confidence scores and consistency checks.

### /perception/occupancy_grid_map/occupancy_grid_map_node

- **Link**: [GitHub - Occupancy Grid Map](https://github.com/autowarefoundation/autoware.universe/tree/main/perception/autoware_probabilistic_occupancy_grid_map)

- **Algorithms**: Probabilistic occupancy mapping, Bayesian update, pointcloud projection to 2D grid

- **Summary**: Generates 2D occupancy grid maps from point clouds and object detections. Uses probabilistic methods to represent space occupancy, useful for goal planning, obstacle detection in unstructured areas, and visualization.

---

## Planning Nodes

### /planning/mission_planning/mission_planner

- **Link**: [GitHub - Mission Planner](https://github.com/autowarefoundation/autoware.universe/tree/main/planning/autoware_mission_planner_universe)

- **Algorithms**: Dijkstra's shortest path on lanelet routing graph, goal validation using vehicle footprint, route section creation

- **Summary**: Calculates routes from current position to goal pose following waypoints on the Lanelet2 map. Uses Lanelet2's routing graph with Dijkstra's algorithm to find shortest paths. Performs goal validation checking goal pose angle and vehicle footprint against lanelet boundaries. Supports rerouting for route changes, emergency scenarios, and goal modifications. Does not consider dynamic objects or temporary road closures.

### /planning/scenario_planning/lane_driving/behavior_planning/behavior_path_planner

- **Link**: [GitHub - Behavior Path Planner](https://github.com/autowarefoundation/autoware.universe/tree/main/planning/behavior_path_planner/autoware_behavior_path_planner)

- **Algorithms**: Constant-jerk lateral shift profiles, Multiple scene modules (avoidance, lane change, goal planning, etc.), RSS-inspired safety checking, Static and dynamic drivable area expansion

- **Summary**: Main behavior planning module responsible for generating safe paths, drivable areas, and turn signals. Manages multiple scene modules including lane following, static/dynamic obstacle avoidance, lane changes, start/goal planning. Uses constant-jerk profiles for smooth lateral path shifts. Implements RSS-inspired collision assessment for safety verification. Generates static drivable areas based on lanelets and dynamic expansion for large vehicles. Supports modular architecture allowing activation of different behavior modules based on driving scenarios.

### /planning/scenario_planning/lane_driving/motion_planning/motion_velocity_planner

- **Link**: [GitHub - Motion Velocity Planner](https://github.com/autowarefoundation/autoware.universe/tree/main/planning/motion_velocity_planner)

- **Algorithms**: Velocity optimization considering multiple constraints, time-elastic-band smoothing, obstacle stop planning

- **Summary**: Plans velocity profiles for the path generated by behavior planner. Considers multiple velocity constraints including curvature limits, obstacle stops, traffic lights, crosswalks, and stop signs. Optimizes velocity to be smooth while respecting all constraints.

### /planning/scenario_planning/scenario_selector

- **Link**: [GitHub - Scenario Selector](https://github.com/autowarefoundation/autoware.universe/tree/main/planning/autoware_scenario_selector)

- **Algorithms**: Rule-based scenario selection, state machine management

- **Summary**: Selects appropriate planning scenario (lane driving, parking, emergency) based on vehicle state and environment. Manages transitions between scenarios and routes planning requests to appropriate scenario planners.

### /planning/scenario_planning/velocity_smoother

- **Link**: [GitHub - Velocity Smoother](https://github.com/autowarefoundation/autoware.universe/tree/main/planning/autoware_velocity_smoother)

- **Algorithms**: Jerk-limited velocity optimization, L2 smoothing

- **Summary**: Smooths velocity profiles to improve ride comfort while maintaining safety and efficiency. Limits jerk and acceleration to comfortable levels while respecting velocity constraints from upstream planners.

### /planning/planning_validator

- **Link**: [GitHub - Planning Validator](https://github.com/autowarefoundation/autoware.universe/tree/main/planning/planning_validator/autoware_planning_validator)

- **Algorithms**: Trajectory validation against kinematic limits, collision checking, consistency validation

- **Summary**: Validates planned trajectories before execution, checking for kinematic feasibility, potential collisions, and consistency issues. Rejects invalid plans and publishes diagnostics to prevent execution of unsafe or infeasible trajectories.

---

## Sensing Nodes

### /sensing/gnss/gnss_poser

- **Link**: [GitHub - GNSS Poser](https://github.com/autowarefoundation/autoware.universe/tree/main/sensing/autoware_gnss_poser)

- **Algorithms**: GNSS coordinate transformation, altitude correction

- **Summary**: Converts GNSS measurements into pose estimates in map coordinates. Handles coordinate transformations from WGS84 to local map coordinates and provides altitude corrections. Outputs pose with covariance for fusion with other localization sources.

### /sensing/imu/imu_corrector

- **Link**: [GitHub - IMU Corrector](https://github.com/autowarefoundation/autoware.universe/tree/main/sensing/autoware_imu_corrector)

- **Algorithms**: Bias correction, coordinate frame transformation, gravity compensation

- **Summary**: Corrects IMU measurements for known biases, performs coordinate transformations, and compensates for gravitational effects. Provides calibrated IMU data for localization and control modules.

### /sensing/lidar/concatenate_data

- **Link**: [GitHub - Concatenate Data](https://github.com/autowarefoundation/autoware.universe/tree/main/sensing/autoware_pointcloud_concatenate_filter)

- **Algorithms**: Point cloud synchronization and concatenation

- **Summary**: Synchronizes and concatenates point clouds from multiple LiDAR sensors into a single unified point cloud. Handles timing synchronization and coordinate frame transformations to produce a complete 360-degree view.

### /sensing/vehicle_velocity_converter

- **Link**: [GitHub - Vehicle Velocity Converter](https://github.com/autowarefoundation/autoware.universe/tree/main/sensing/autoware_vehicle_velocity_converter)

- **Algorithms**: Velocity message format conversion

- **Summary**: Converts vehicle velocity information between different message formats used by vehicle interface and localization modules. Provides standardized velocity data for consumption by various Autoware components.

---

## System Nodes

### /system/aggregator

- **Link**: [GitHub - Diagnostic Aggregator](https://github.com/autowarefoundation/autoware.universe/tree/main/system/autoware_diagnostic_aggregator)

- **Algorithms**: Diagnostic message aggregation, hierarchical organization

- **Summary**: Aggregates diagnostic messages from all system components into hierarchical categories. Provides overall system health status and enables easy monitoring of component states through organized diagnostic reports.

### /system/component_state_monitor/component

- **Link**: [GitHub - Component State Monitor](https://github.com/autowarefoundation/autoware.universe/tree/main/system/autoware_component_state_monitor)

- **Algorithms**: Topic availability monitoring, update rate checking

- **Summary**: Monitors availability and update rates of critical topics and nodes. Detects stale topics, missing nodes, or components not publishing at expected rates, issuing diagnostics when problems are detected.

### /system/mrm_handler

- **Link**: [GitHub - MRM Handler](https://github.com/autowarefoundation/autoware.universe/tree/main/system/autoware_mrm_handler)

- **Algorithms**: Minimal Risk Maneuver decision making, emergency state management

- **Summary**: Handles Minimal Risk Maneuver (MRM) execution when system failures are detected. Decides appropriate emergency responses (comfortable stop, emergency stop, emergency pull over) based on failure severity and coordinates MRM execution.

### /system/mrm_comfortable_stop_operator

- **Link**: [GitHub - MRM Comfortable Stop](https://github.com/autowarefoundation/autoware.universe/tree/main/system/autoware_mrm_comfortable_stop_operator)

- **Algorithms**: Comfortable deceleration profile generation

- **Summary**: Executes comfortable stop MRM by generating gentle deceleration profiles. Brings vehicle to stop with passenger comfort considerations when non-critical failures occur.

### /system/mrm_emergency_stop_operator

- **Link**: [GitHub - MRM Emergency Stop](https://github.com/autowarefoundation/autoware.universe/tree/main/system/autoware_mrm_emergency_stop_operator)

- **Algorithms**: Emergency deceleration command generation

- **Summary**: Executes emergency stop MRM by commanding maximum safe deceleration. Used for critical failures requiring immediate vehicle stop regardless of passenger comfort.

---

## Utility Nodes

### /robot_state_publisher

- **Link**: [ROS2 robot_state_publisher](https://github.com/ros/robot_state_publisher/tree/ros2)

- **Algorithms**: URDF parsing, kinematic tree computation, TF broadcasting

- **Summary**: Standard ROS2 node that publishes the robot's kinematic tree as TF transformations. Reads vehicle URDF description and publishes static and dynamic transforms between different robot coordinate frames, enabling proper coordinate transformations throughout the system.

### /trajectory_relay

- **Link**: Autoware internal utility

- **Algorithms**: Message relay and topic remapping

- **Summary**: Relays trajectory messages between different parts of the planning stack, potentially performing message type conversions or filtering. Acts as a bridge between planning modules with different interfaces.

---

## Additional Default ADAPI Nodes

### /default_adapi/helpers/autoware_initial_pose_adaptor

- **Link**: [GitHub - Default ADAPI](https://github.com/autowarefoundation/autoware.universe/tree/main/system/autoware_default_adapi_universe)

- **Algorithms**: Pose message adaptation between AD API and localization formats

- **Summary**: Adapts initial pose messages between the AD API format and the format expected by localization nodes. Enables external applications to set initial poses through the AD API.

### /default_adapi/helpers/autoware_routing_adaptor

- **Link**: [GitHub - Default ADAPI](https://github.com/autowarefoundation/autoware.universe/tree/main/system/autoware_default_adapi_universe)

- **Algorithms**: Routing request format adaptation

- **Summary**: Adapts routing requests between AD API format and mission planner format. Handles conversion of goal poses and waypoints from external applications into formats used by mission planner.

### /default_adapi/helpers/autoware_automatic_pose_initializer

- **Link**: [GitHub - Default ADAPI](https://github.com/autowarefoundation/autoware.universe/tree/main/system/autoware_default_adapi_universe)

- **Algorithms**: Automatic pose initialization logic, GNSS-based initial pose estimation

- **Summary**: Provides automatic pose initialization functionality, attempting to determine initial vehicle pose using GNSS and map matching when manual initialization is not provided.

---

## Control Evaluator and Analytics

### /control/control_evaluator

- **Link**: [GitHub - Control Evaluator](https://github.com/autowarefoundation/autoware.universe/tree/main/evaluator/autoware_control_evaluator)

- **Algorithms**: Lateral/longitudinal error calculation, control performance metrics

- **Summary**: Evaluates control performance by comparing actual vehicle motion with planned trajectory. Calculates lateral errors, heading errors, and longitudinal tracking errors, publishing metrics for monitoring and analysis.

### /planning/planning_evaluator

- **Link**: [GitHub - Planning Evaluator](https://github.com/autowarefoundation/autoware.universe/tree/main/evaluator/autoware_planning_evaluator)

- **Algorithms**: Trajectory quality metrics, planning performance analysis

- **Summary**: Evaluates planning performance by analyzing generated trajectories. Calculates metrics such as trajectory smoothness, deviation from reference paths, computational performance, and planning success rates.

---

## Notes

This documentation is generated based on Autoware version 47 (Jazzy distribution). Node configurations and features may vary depending on the specific Autoware installation and launch configurations.

For the most up-to-date and detailed information about specific nodes, please refer to:
- [Autoware Documentation](https://autowarefoundation.github.io/autoware-documentation/)
- [Autoware Universe GitHub Repository](https://github.com/autowarefoundation/autoware.universe)
- [Autoware Core GitHub Repository](https://github.com/autowarefoundation/autoware.core)

Each node's README in the source code provides detailed parameter descriptions, interface specifications, and implementation details.

