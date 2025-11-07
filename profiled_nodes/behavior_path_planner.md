# Behavior Path Planner Node

## Node Name
`/planning/scenario_planning/lane_driving/behavior_planning/behavior_path_planner`

## Links
- [GitHub - Behavior Path Planner](https://github.com/autowarefoundation/autoware.universe/tree/main/planning/behavior_path_planner/autoware_behavior_path_planner)
- [Autoware Documentation - Planning](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-architecture/planning/)

## Algorithms
- **Constant-Jerk Lateral Shift Profiles**: Smooth path generation with bounded jerk
- **RSS-inspired Safety Checking**: Responsibility-Sensitive Safety collision assessment
- **Drivable Area Generation**: Static and dynamic corridor computation
- **Scene Module Management**: Multi-behavior state machine coordination

## Parameters

### Performance Impacting

- **`planning_hz`** (double):
  - **Description**: Path planning update frequency
  - **Default**: `10.0` Hz
  - **Impact**: Higher frequency reduces latency but increases CPU load linearly. All scene modules execute at this rate

- **`forward_path_length`** (double):
  - **Description**: Lookahead distance for path generation
  - **Default**: `300.0` meters
  - **Impact**: Longer paths require more waypoint processing. Increases with vehicle speed

- **`backward_path_length`** (double):
  - **Description**: Path length behind vehicle
  - **Default**: `5.0` meters
  - **Impact**: Minimal overhead, needed for smooth connection to current pose

- **`input_path_interval`** (double):
  - **Description**: Resampling interval for input route
  - **Default**: `2.0` meters
  - **Impact**: Affects number of waypoints processed. Smaller intervals increase density linearly

- **`output_path_interval`** (double):
  - **Description**: Output path waypoint spacing
  - **Default**: `2.0` meters
  - **Impact**: Critical for downstream processing. 1m → 2× points vs. 2m spacing

- **`enable_akima_spline_first`** (bool):
  - **Description**: Use Akima spline for initial path smoothing
  - **Default**: `false`
  - **Impact**: Smoother paths but adds 10-20ms processing time

### Other Parameters

- **`turn_signal_intersection_search_distance`** (double):
  - **Description**: Distance to search for intersections ahead
  - **Default**: `30.0` meters
  - **Purpose**: Turn signal activation logic

- **`turn_signal_search_time`** (double):
  - **Description**: Time horizon for turn signal activation
  - **Default**: `3.0` seconds
  - **Purpose**: Early turn signal for human drivers

- **`turn_signal_shift_length_threshold`** (double):
  - **Description**: Minimum lateral shift to trigger turn signal
  - **Default**: `0.3` meters
  - **Purpose**: Filters small path adjustments

- **`turn_signal_on_swerving`** (bool):
  - **Description**: Activate turn signals during obstacle avoidance
  - **Default**: `true`
  - **Purpose**: Communication with other road users

- **`enable_cog_on_centerline`** (bool):
  - **Description**: Place center-of-gravity on path centerline
  - **Default**: `false`
  - **Purpose**: Kinematic model option

- **`minimum_pull_over_length`** (double):
  - **Description**: Minimum distance for pull-over maneuver
  - **Default**: `16.0` meters
  - **Purpose**: Ensure sufficient space for goal approach

- **`refine_goal_search_radius_range`** (double):
  - **Description**: Search range for goal pose refinement
  - **Default**: `7.5` meters
  - **Purpose**: Finds nearby valid goal positions

## Explanation

### High Level

The Behavior Path Planner is the tactical-level planner responsible for generating safe, comfortable paths that navigate through various driving scenarios. It manages multiple scene modules (lane following, avoidance, lane change, goal planning) which activate based on the current driving context. Each module proposes candidate paths, and the planner selects and executes the most appropriate one.

The core functionality includes generating smooth lateral shifts for obstacle avoidance and lane changes using constant-jerk profiles, computing drivable area boundaries considering lanelets and dynamic obstacles, and ensuring safety through RSS-inspired collision checking. The output is a path with associated drivable areas, turn signals, and behavior state, which guides the downstream motion velocity planner.

### Model

#### Constant-Jerk Lateral Shift Profile

For smooth lateral maneuvers (lane change, obstacle avoidance), generate a path with bounded jerk.

**Problem:** Shift laterally by Δy over distance L_shift

**Quintic Polynomial:**

Lateral position as function of longitudinal distance s:
```
y(s) = a₀ + a₁s + a₂s² + a₃s³ + a₄s⁴ + a₅s⁵
```

**Boundary Conditions:**

At s = 0 (start):
```
y(0) = 0
y'(0) = 0 (zero lateral velocity)
y''(0) = 0 (zero lateral acceleration)
```

At s = L_shift (end):
```
y(L_shift) = Δy
y'(L_shift) = 0
y''(L_shift) = 0
```

**Solution:**

```
a₀ = 0
a₁ = 0
a₂ = 0
a₃ = 10Δy / L³
a₄ = -15Δy / L⁴
a₅ = 6Δy / L⁵
```

Where L = L_shift.

**Derivatives:**

Lateral velocity (dy/ds):
```
y'(s) = 3a₃s² + 4a₄s³ + 5a₅s⁴
```

Lateral acceleration:
```
y''(s) = 6a₃s + 12a₄s² + 20a₅s³
```

Lateral jerk:
```
y'''(s) = 6a₃ + 24a₄s + 60a₅s²
```

**Path Generation:**

For reference path P_ref (centerline) and shift profile y(s):

```
For each waypoint i at arc length s_i:
  1. Compute lateral offset: Δy_i = y(s_i)
  2. Get tangent direction: t_i = tangent(P_ref, s_i)
  3. Compute normal: n_i = perpendicular(t_i)
  4. Shifted position: p_i = P_ref(s_i) + Δy_i · n_i
```

**Maximum Curvature:**

Peak occurs at s = L/2:
```
κ_max ≈ 6.7 · Δy / L²
```

For safe navigation, ensure:
```
κ_max ≤ κ_vehicle_max
```

Which implies:
```
L_shift ≥ √(6.7 · Δy / κ_max)
```

#### RSS-Inspired Safety Checking

**Responsibility-Sensitive Safety (RSS)** principles:

For ego vehicle and obstacle:

**Longitudinal Safety Distance:**

```
d_safe_long = v_ego · t_react + (v_ego² / (2·a_brake_ego)) - (v_obs² / (2·a_brake_obs)) + d_margin
```

Where:
- t_react: reaction time (0.5-1.0s)
- a_brake_ego: ego braking capability
- a_brake_obs: obstacle assumed braking
- d_margin: safety buffer

**Lateral Safety Distance:**

```
d_safe_lat = 0.5 · (w_ego + w_obs) + d_margin
```

**Collision Check:**

For each obstacle O at each time step t:

```
Predict ego position: p_ego(t)
Predict obstacle position: p_obs(t)

if |p_ego_long(t) - p_obs_long(t)| < d_safe_long:
  if |p_ego_lat(t) - p_obs_lat(t)| < d_safe_lat:
    COLLISION_RISK = true
```

**Time-to-Collision (TTC):**

```
TTC = distance(ego, obstacle) / relative_velocity

if TTC < TTC_threshold:
  UNSAFE
```

#### Drivable Area Generation

**Static Drivable Area:**

Based on lanelets from route:

```
For current position along route:
  1. Get current lanelet L_current
  2. Get adjacent lanelets (left/right neighbors)
  3. Extract boundaries:
     - Left boundary: L_current.left_bound or left_neighbor.left_bound
     - Right boundary: L_current.right_bound or right_neighbor.right_bound
  4. Create polygon: DA_static = Polygon(left_boundary, right_boundary)
```

**Dynamic Expansion:**

For large vehicles or specific maneuvers:

```
DA_dynamic = DA_static + expansion_margin

expansion = f(vehicle_size, maneuver_type, safety_margin)
```

**Obstacle Constraints:**

```
For each obstacle O in DA:
  Compute obstacle polygon P_O
  DA_final = DA_dynamic \ P_O  (set difference)
```

Result: Polygon representing drivable space avoiding obstacles.

#### Scene Module Architecture

**Module Types:**

1. **Lane Following**: Default behavior, follows centerline
2. **Static Obstacle Avoidance**: Lateral shifts around parked vehicles
3. **Dynamic Obstacle Avoidance**: Reactive avoidance of moving objects
4. **Lane Change**: Left/right lane changes per route
5. **Start Planner**: Pull-out from stationary
6. **Goal Planner**: Pull-over to goal pose

**Module Execution:**

```
For each planning cycle:
  1. Query active modules based on scene context
  2. Each module proposes candidate path
  3. Evaluate candidates:
     - Safety score (collision-free)
     - Comfort score (low jerk/accel)
     - Progress score (goal advancement)
  4. Select best candidate
  5. Execute path
```

**State Machine:**

```
States: {IDLE, RUNNING, SUCCESS, FAILURE}

Transitions:
  IDLE → RUNNING: Module activated
  RUNNING → SUCCESS: Maneuver completed
  RUNNING → FAILURE: Maneuver infeasible
  * → IDLE: Module deactivated
```

#### Path Smoothing

**Akima Spline** (if enabled):

For waypoints {(x₁, y₁), (x₂, y₂), ..., (xₙ, yₙ)}:

Akima spline minimizes overshoot compared to cubic spline:

```
For each segment [xᵢ, xᵢ₊₁]:
  Cubic polynomial with slopes computed using:
  
  m_i = weighted average of surrounding slopes
  Weights favor local slopes over distant ones
```

**Properties:**
- C¹ continuous (smooth tangents)
- Local: changes don't propagate far
- Flat near extrema (no overshoots)

### Complexity

**Time Complexity:**

**Per Planning Cycle:**

**Path Resampling:**
- Input route waypoints: N (typically 150 for 300m path at 2m interval)
- Arc length computation: O(N)
- Interpolation: O(N)

**Shift Profile Generation:**
- Quintic polynomial evaluation: O(M)
  - M = number of output waypoints
- Lateral offset application: O(M)

**Safety Checking:**
- For each obstacle O and trajectory point p:
  - Distance computation: O(1)
  - RSS check: O(1)
- Total: O(K · M)
  - K = number of obstacles (typically 10-50)

**Drivable Area:**
- Lanelet boundary extraction: O(L)
  - L = boundary points per lanelet (~50)
- Polygon operations: O(L²) worst case
- Obstacle subtraction: O(K · L)

**Module Management:**
- Active module queries: O(N_modules)
  - N_modules ≈ 5-10
- Candidate evaluation: O(N_modules)

**Total:**
```
T_cycle = O(N + M + K·M + L² + K·L + N_modules)
        ≈ O(K·M) when K·M >> others
```

For typical values:
- N = 150 waypoints
- M = 150 output points
- K = 30 obstacles
- L = 50 boundary points
- Time: 10-30 ms per cycle

**At 10 Hz:** 100ms budget, comfortably achieved

**Space Complexity:**

**Path Storage:**
- Input route: N × waypoint_size
  - N × 40 bytes ≈ 6 KB
- Output path: M × 40 bytes ≈ 6 KB
- Drivable area: L × 16 bytes ≈ 0.8 KB

**Obstacle Data:**
- K objects × 100 bytes ≈ 3 KB

**Module States:**
- N_modules × state_size ≈ 1 KB

**Total:** ~17 KB (minimal)

**Performance Bottlenecks:**

1. **Obstacle Collision Checking**:
   - Dominates for many obstacles
   - Quadratic in trajectory length × obstacles
   - Mitigation: Spatial partitioning, early termination

2. **Drivable Area Computation**:
   - Polygon operations can be expensive
   - Particularly with obstacle subtraction
   - Mitigation: Simplified polygon representations, approximate operations

3. **Path Smoothing**:
   - Akima spline adds 10-20ms overhead
   - May not be necessary for all scenarios
   - Mitigation: Disable for straight paths, use simpler interpolation

4. **Multiple Scene Modules**:
   - Each module generates candidate path
   - Redundant computation if many modules active
   - Mitigation: Lazy evaluation, early pruning of unlikely modules

5. **High Planning Frequency**:
   - 10 Hz standard, but some scenes may not need it
   - Fixed frequency regardless of necessity
   - Mitigation: Adaptive frequency based on scene complexity

**Parameter Trade-offs:**

- **`planning_hz`**:
  - Low (5 Hz): Less CPU, suitable for highway
  - High (20 Hz): More responsive, needed for urban
  - Optimal: 10 Hz balances responsiveness and efficiency

- **`forward_path_length`**:
  - Short (100m): Fast, sufficient for urban
  - Long (400m): Slower, needed for high-speed highway
  - Optimal: Adaptive based on speed (v × 10-15 seconds)

- **`input_path_interval` / `output_path_interval`**:
  - Fine (1m): More detail, 2× points, slower
  - Coarse (3m): Faster, may miss details
  - Optimal: 2m standard, 1m for parking/tight maneuvers

- **`enable_akima_spline_first`**:
  - Enabled: Smoother paths, better comfort, +10-20ms
  - Disabled: Faster, sufficient for most scenarios
  - Optimal: Enable for passenger comfort focus, disable for performance

- **`turn_signal_shift_length_threshold`**:
  - Small (0.1m): Frequent signaling, may be excessive
  - Large (0.5m): Less signaling, may miss notifications
  - Optimal: 0.3m filters noise while catching significant shifts

- **Scene Module Configuration**:
  - More modules: More flexibility, higher overhead
  - Fewer modules: Faster, may miss maneuver opportunities
  - Optimal: Enable only necessary modules for scenario

## Summary

The Behavior Path Planner generates tactical-level paths by managing multiple scene modules for different driving behaviors. It creates smooth lateral maneuvers using constant-jerk profiles, ensures safety through RSS-inspired collision checking, and computes drivable areas considering both static lane boundaries and dynamic obstacles, producing comfortable and safe paths that respect the driving context and road structure.

