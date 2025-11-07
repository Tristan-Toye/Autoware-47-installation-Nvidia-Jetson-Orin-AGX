# Autonomous Emergency Braking Node

## Node Name
`/control/autonomous_emergency_braking`

## Links
- [GitHub - Autonomous Emergency Braking](https://github.com/autowarefoundation/autoware.universe/tree/main/control/autoware_autonomous_emergency_braking)
- [Autoware Documentation - Control](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-architecture/control/)

## Algorithms
- **Time-to-Collision (TTC) Calculation**: Collision risk assessment
- **RSS Safe Distance**: Responsibility-Sensitive Safety distance computation
- **Polygonal Collision Detection**: Geometric overlap checking
- **Emergency Deceleration Command**: Maximum braking force generation

## Parameters

### Performance Impacting

- **`use_predicted_trajectory`** (bool):
  - **Description**: Use predicted object paths vs. current velocity
  - **Default**: `true`
  - **Impact**: Predicted trajectories require more computation but improve accuracy for turning/curving objects

- **`use_imu_path`** (bool):
  - **Description**: Use IMU for ego trajectory prediction
  - **Default**: `false`
  - **Impact**: IMU-based prediction adds sensor fusion overhead but improves accuracy during high dynamics

- **`check_all_predicted_path`** (bool):
  - **Description**: Check all hypothesis paths vs. most likely
  - **Default**: `false`
  - **Impact**: Checking all paths is more conservative but 2-5× slower with multiple hypotheses

- **`publish_debug_markers`** (bool):
  - **Description**: Publish visualization markers
  - **Default**: `false`
  - **Impact**: Adds 20-30% overhead for marker generation and publishing

### Other Parameters

- **`detection_range_min_height`** (double):
  - **Description**: Minimum object height for consideration
  - **Default**: `0.0` meters
  - **Purpose**: Filters ground-level noise

- **`detection_range_max_height_margin`** (double):
  - **Description**: Height margin above vehicle
  - **Default**: `0.0` meters
  - **Purpose**: Filters overhead objects

- **`vru_collision_time_margin`** (double):
  - **Description**: Additional time margin for vulnerable road users
  - **Default**: `2.0` seconds
  - **Purpose**: More conservative braking for pedestrians/cyclists

- **`vehicle_collision_time_margin`** (double):
  - **Description**: Time margin for vehicles
  - **Default**: `1.0` seconds
  - **Purpose**: Collision warning threshold

- **`path_footprint_extra_margin`** (double):
  - **Description**: Additional footprint expansion for collision checking
  - **Default**: `1.0` meters
  - **Purpose**: Conservative safety margin

- **`imu_prediction_time_horizon`** (double):
  - **Description**: Prediction time using IMU
  - **Default**: `1.5` seconds
  - **Purpose**: Ego trajectory extrapolation

- **`imu_prediction_time_interval`** (double):
  - **Description**: Time step for IMU predictions
  - **Default**: `0.1` seconds
  - **Purpose**: Prediction resolution

- **`min_object_velocity`** (double):
  - **Description**: Minimum velocity to consider object as moving
  - **Default**: `1.0` m/s
  - **Purpose**: Filters stationary object noise

- **`obstacle_velocity_threshold_from_cruise`** (double):
  - **Description**: Relative velocity threshold for cruise scenarios
  - **Default**: `-3.0` m/s
  - **Purpose**: Ignores objects moving away

- **`collision_keeping_sec`** (double):
  - **Description**: Time to maintain emergency brake after collision risk ends
  - **Default**: `0.5` seconds
  - **Purpose**: Hysteresis to prevent oscillation

## Explanation

### High Level

The Autonomous Emergency Braking (AEB) system is a safety-critical last-resort mechanism that detects imminent collisions and commands maximum braking to avoid or mitigate impact. It continuously monitors predicted object trajectories, computes time-to-collision (TTC), and activates when TTC falls below safety thresholds. Unlike normal trajectory following, AEB overrides all other commands and applies maximum safe deceleration.

The system operates independently from planning, checking whether the current ego trajectory will intersect with any object within a critical time window. It uses both geometric collision detection (polygon overlap) and physics-based TTC calculations, preferring conservative assumptions. AEB activation is rare but essential, catching scenarios where planning fails or unexpected obstacles appear.

### Model

#### Time-to-Collision (TTC) Calculation

**Definition:**

Time until collision assuming constant velocities:
```
TTC = distance / relative_velocity
```

**Relative Velocity:**

For ego vehicle and object:
```
v_rel = v_ego - v_object · cos(θ)
```

Where θ is the angle between ego heading and object velocity vector.

**Distance Computation:**

Closest point on ego path to object:
```
d_min = min{||p_ego(t) - p_object|| | t ∈ [0, T]}
```

**TTC:**
```
if v_rel > 0:  // approaching
  TTC = d_min / v_rel
else:
  TTC = ∞  // diverging
```

#### RSS Safe Distance

**Longitudinal Safe Distance:**

Following RSS principles:
```
d_safe = v_ego · t_react + 
         (v_ego² - v_object²) / (2 · min(a_brake_ego, a_brake_object)) + 
         d_margin
```

Where:
- t_react: reaction time (default: 0.5s for AEB since no human reaction needed)
- a_brake_ego: ego braking capability
- a_brake_object: assumed object braking
- d_margin: safety buffer

**Collision Condition:**

```
if distance < d_safe AND v_rel > 0:
  COLLISION_IMMINENT = true
```

#### Trajectory Prediction

**Ego Trajectory:**

**Without IMU (kinematic prediction):**

Constant velocity model:
```
p_ego(t) = p_current + v_ego · t · [cos(ψ), sin(ψ)]ᵀ
```

**With IMU:**

Include angular velocity:
```
x(t) = x₀ + ∫₀ᵗ v(τ) · cos(ψ(τ)) dτ
y(t) = y₀ + ∫₀ᵗ v(τ) · sin(ψ(τ)) dτ
ψ(t) = ψ₀ + ∫₀ᵗ ω(τ) dτ
```

Where ω is yaw rate from IMU.

**Object Trajectory:**

If use_predicted_trajectory enabled:
```
Use prediction module outputs (multiple hypotheses)
```

Else:
```
Constant velocity: p_object(t) = p₀ + v_object · t
```

#### Polygonal Collision Detection

**Vehicle Footprint:**

Rectangular polygon:
```
Footprint = Rectangle(center, length, width, heading)

Vertices = [
  center + R(heading) · [length/2, width/2]ᵀ,
  center + R(heading) · [-length/2, width/2]ᵀ,
  center + R(heading) · [-length/2, -width/2]ᵀ,
  center + R(heading) · [length/2, -width/2]ᵀ
]
```

With margin expansion:
```
Footprint_safe = Expand(Footprint, path_footprint_extra_margin)
```

**Collision Check:**

For each time step t:
```
Ego_polygon(t) = FootprintAt(ego_trajectory, t)
Object_polygon(t) = FootprintAt(object_trajectory, t)

if Intersect(Ego_polygon(t), Object_polygon(t)):
  collision_time = t
  return COLLISION
```

**Separating Axis Theorem (SAT):**

Efficient polygon intersection test:

```
For each edge axis in both polygons:
  Project both polygons onto axis
  if projections don't overlap:
    return NO_COLLISION

return COLLISION (all axes have overlap)
```

Complexity: O(n + m) for n-sided and m-sided polygons

#### Emergency Brake Decision Logic

**State Machine:**

```
States: {SAFE, WARNING, EMERGENCY}

Transitions:
  SAFE → WARNING: TTC < TTC_warning
  WARNING → EMERGENCY: TTC < TTC_emergency
  EMERGENCY → WARNING: TTC > TTC_emergency + hysteresis
  WARNING → SAFE: TTC > TTC_warning + hysteresis
```

**TTC Thresholds:**

```
TTC_warning = vehicle_collision_time_margin  (1.0s for vehicles)
TTC_warning_vru = vru_collision_time_margin   (2.0s for VRUs)
TTC_emergency = 0.5 · TTC_warning
```

**Brake Command:**

```
if state == EMERGENCY:
  a_cmd = -a_max_brake  // maximum deceleration
  jerk = jerk_max       // maximum jerk for fastest response
elif state == WARNING:
  a_cmd = -a_comfortable  // prepare for emergency
else:
  a_cmd = 0  // no intervention
```

**Hysteresis:**

Prevent oscillation:
```
if collision detected:
  emergency_timer = collision_keeping_sec

if emergency_timer > 0:
  maintain EMERGENCY state
  emergency_timer -= dt
```

#### Multi-Object Processing

**For each detected object O:**

```
1. Filter by height: min_height < O.height < max_height
2. Filter by velocity: O.velocity > min_object_velocity
3. Compute relative velocity
4. Check if approaching: v_rel > obstacle_velocity_threshold
5. Predict trajectories
6. Compute TTC
7. Check geometric collision
8. Update minimum TTC
```

**Global Decision:**

```
TTC_min = min{TTC(O) | O in relevant_objects}

if TTC_min < TTC_emergency:
  ACTIVATE_AEB()
```

### Complexity

**Time Complexity:**

**Per Object:**

**Trajectory Prediction:**
- Ego trajectory: O(T/Δt)
  - T = prediction horizon (1.5s)
  - Δt = time step (0.1s)
  - ~15 points
- Object trajectory: O(T/Δt)
  - Same complexity

**Collision Check:**
- Per time step: O((n + m))
  - SAT for two polygons
  - n, m = vertices (typically 4 each)
- All time steps: O(T/Δt · (n + m))
  - ~15 × 8 = 120 operations

**TTC Computation:**
- Distance: O(T/Δt) to find minimum
- Division: O(1)

**Per Object Total:** O(T/Δt · (n + m)) ≈ O(120) operations

**All Objects:**

K objects:
```
T_total = K · O(T/Δt · (n + m))
```

For typical values:
- K = 30 objects
- T/Δt = 15 time steps
- n + m = 8 vertices
- Total: 30 × 120 = 3600 operations → 0.5-2 ms

**Space Complexity:**

**Per Object:**
- Trajectory points: (T/Δt) × 8 bytes = 15 × 8 = 120 bytes
- Polygon vertices: 4 × 16 bytes = 64 bytes

**All Objects:**
- K objects × 184 bytes = 30 × 184 = 5.5 KB

**Global State:**
- Collision flags: K × 1 byte = 30 bytes
- TTC values: K × 4 bytes = 120 bytes

**Total:** ~6 KB (minimal)

**Performance Bottlenecks:**

1. **Trajectory Prediction**:
   - Required for each object each cycle
   - Can dominate for many objects
   - Mitigation: Parallel processing, caching

2. **Geometric Collision Checks**:
   - SAT for each object-ego pair at each time step
   - Quadratic in prediction horizon
   - Mitigation: Spatial partitioning, early termination

3. **Multiple Hypothesis Handling**:
   - If check_all_predicted_path enabled
   - Linear scaling with hypothesis count
   - Mitigation: Prune unlikely paths, check only nearest

4. **Debug Visualization**:
   - Marker generation adds 20-30% overhead
   - Should be disabled in production
   - Mitigation: Conditional compilation, runtime flag

5. **Real-Time Criticality**:
   - Must execute within hard deadline
   - Failure = potential collision
   - Mitigation: Worst-case analysis, priority scheduling

**Parameter Trade-offs:**

- **`use_predicted_trajectory`**:
  - Enabled: More accurate for turning objects, slower
  - Disabled: Faster, sufficient for straight motion
  - Optimal: Enable for production (accuracy critical)

- **`check_all_predicted_path`**:
  - Enabled: Most conservative, 2-5× slower
  - Disabled: Fast, checks only most likely
  - Optimal: Disable for performance, enable for maximum safety

- **`vru_collision_time_margin`**:
  - High (3s): Very conservative, more false positives
  - Low (1s): Less conservative, may miss slow pedestrians
  - Optimal: 2s balances VRU safety and false positive rate

- **`vehicle_collision_time_margin`**:
  - High (2s): Conservative, frequent interventions
  - Low (0.5s): Late intervention, may not stop in time
  - Optimal: 1s provides adequate warning time

- **`path_footprint_extra_margin`**:
  - Large (2m): Very conservative, more false positives
  - Small (0.5m): Tight fit, risk of grazing collisions
  - Optimal: 1m balances safety margin and false positives

- **`collision_keeping_sec`**:
  - Short (0.2s): Quick release, may oscillate
  - Long (1.0s): Stable but delays recovery
  - Optimal: 0.5s provides hysteresis without excessive delay

- **`imu_prediction_time_horizon`**:
  - Short (0.5s): Fast, limited preview
  - Long (3.0s): Better for high-speed, more computation
  - Optimal: 1.5s covers typical reaction distance at urban speeds

## Summary

The Autonomous Emergency Braking node monitors for imminent collisions by computing time-to-collision for all nearby objects and checking geometric overlap between predicted ego and object trajectories. When TTC falls below safety thresholds, it commands maximum braking to avoid or mitigate collisions, serving as a last-resort safety mechanism independent of the planning system, essential for safe autonomous driving operation.

