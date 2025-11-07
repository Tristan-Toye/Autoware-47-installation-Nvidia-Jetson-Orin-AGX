# Map-Based Prediction Node

## Node Name
`/perception/object_recognition/prediction/map_based_prediction`

## Links
- [GitHub - Map Based Prediction](https://github.com/autowarefoundation/autoware.universe/tree/main/perception/autoware_map_based_prediction)
- [Autoware Documentation - Perception](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-architecture/perception/)

## Algorithms
- **Lanelet-based Path Generation**: Predicts trajectories following road topology
- **Physics-based Motion Models**: Constant velocity, constant acceleration, lane following
- **Multi-hypothesis Prediction**: Generates multiple possible futures (straight, lane change)
- **Lateral Offset Modeling**: Gaussian distribution for lateral position uncertainty

## Parameters

### Performance Impacting

- **`prediction_time_horizon.vehicle`** (double):
  - **Description**: Prediction time for vehicles
  - **Default**: `15.0` seconds
  - **Impact**: Longer horizons increase path sampling points exponentially and computational cost. Each additional second adds ~2 trajectory points × hypotheses

- **`prediction_time_horizon.pedestrian`** (double):
  - **Description**: Prediction time for pedestrians
  - **Default**: `10.0` seconds
  - **Impact**: Similar to vehicles but pedestrians are simpler (fewer hypotheses)

- **`prediction_sampling_delta_time`** (double):
  - **Description**: Time resolution for trajectory sampling
  - **Default**: `0.5` seconds
  - **Impact**: Smaller intervals increase trajectory point count linearly. 0.5s → 30 points for 15s horizon

- **`lateral_control_time_horizon`** (double):
  - **Description**: Time to complete lane changes
  - **Default**: `5.0` seconds
  - **Impact**: Affects lane change trajectory shape and computational cost for multiple hypothesis

- **`min_velocity_for_map_based_prediction`** (double):
  - **Description**: Minimum speed to use map-based prediction
  - **Default**: `1.39` m/s (5 km/h)
  - **Impact**: Below threshold, uses simple constant velocity model (much faster)

- **`check_lateral_acceleration_constraints`** (bool):
  - **Description**: Validate predicted paths against lateral acceleration limits
  - **Default**: `false`
  - **Impact**: Adds physics validation for each trajectory point, increases cost 30-50%

### Other Parameters

- **`dist_threshold_for_searching_lanelet`** (double):
  - **Description**: Maximum distance for lanelet association
  - **Default**: `3.0` meters
  - **Purpose**: Limits search space for map matching

- **`delta_yaw_threshold_for_searching_lanelet`** (double):
  - **Description**: Maximum heading difference for lanelet matching
  - **Default**: `0.785` radians (45°)
  - **Purpose**: Filters irrelevant lanelets based on orientation

- **`sigma_lateral_offset`** (double):
  - **Description**: Standard deviation for lateral position uncertainty
  - **Default**: `0.5` meters
  - **Purpose**: Models lane-keeping uncertainty

- **`sigma_yaw_angle_deg`** (double):
  - **Description**: Standard deviation for heading uncertainty
  - **Default**: `5.0` degrees
  - **Purpose**: Models orientation uncertainty

- **`use_vehicle_acceleration`** (bool):
  - **Description**: Consider current acceleration in predictions
  - **Default**: `false`
  - **Purpose**: More accurate short-term predictions but adds complexity

- **`acceleration_exponential_half_life`** (double):
  - **Description**: Time for acceleration to decay to 50%
  - **Default**: `2.5` seconds
  - **Purpose**: Models realistic deceleration behavior

- **`max_lateral_accel`** (double):
  - **Description**: Maximum lateral acceleration for path validation
  - **Default**: `2.0` m/s²
  - **Purpose**: Physics-based path feasibility check

- **`speed_limit_multiplier`** (double):
  - **Description**: Speed limit factor for predictions
  - **Default**: `1.5`
  - **Purpose**: Upper bound on predicted speeds

## Explanation

### High Level

The Map-Based Prediction node forecasts future trajectories of tracked objects by leveraging HD map information. Instead of assuming arbitrary motion, it predicts that vehicles will follow lanes, respect topology (lane connections, merges), and obey physical constraints. For each object, it generates multiple trajectory hypotheses representing different intentions (continue straight, turn left/right, change lanes).

The prediction process begins by associating the object with current and reachable lanelets, then generates candidate paths along these lanelets. Each path is sampled at regular time intervals, creating discrete trajectory points. The node also estimates uncertainty, representing lateral position variability and maneuver probabilities, enabling downstream planning to reason about multiple possible futures.

### Model

#### Lanelet Association

**Current Lanelet Matching:**

For object at position p with heading θ:

```
Candidates = {L ∈ Lanelets | 
  distance(p, L.centerline) < dist_threshold AND
  |θ - L.heading| < delta_yaw_threshold
}
```

**Distance to Lanelet:**
```
d(p, L) = min{||p - q|| | q ∈ L.centerline}
```

**Select:** Lanelet with minimum distance and heading difference:
```
L_current = argmin_{L ∈ Candidates} w₁·d(p,L) + w₂·|θ - L.heading|
```

#### Path Hypothesis Generation

**Reachable Lanelets:**

Given current lanelet L₀, compute reachable lanelets within time horizon T:

```
Reachable(L₀, T) = {L | exists path P: L₀ → L, length(P) ≤ v_max · T}
```

Using graph search (BFS/Dijkstra) on lanelet routing graph:
```
Queue = [L₀]
Visited = {}
while Queue not empty:
  L = Queue.pop()
  if distance(L₀, L) > v_max · T: continue
  Visited.add(L)
  for neighbor in L.successors:
    Queue.append(neighbor)
```

**Hypothesis Types:**

1. **Lane Following**: Continue in current lane
2. **Lane Change Left**: Shift to left neighboring lane
3. **Lane Change Right**: Shift to right neighboring lane
4. **Turn**: Follow lanelet successor (at intersections)

Each hypothesis generates a distinct trajectory.

#### Trajectory Generation

**Centerline Following:**

For lanelet sequence {L₁, L₂, ..., Lₙ}, construct reference path:
```
Path P = Concat(L₁.centerline, L₂.centerline, ..., Lₙ.centerline)
```

**Motion Model:**

**Constant Velocity (CV):**
```
s(t) = s₀ + v · t
```

Where s is arc length along path P.

**Constant Acceleration (CA):**
```
s(t) = s₀ + v₀·t + ½·a·t²
v(t) = v₀ + a·t
```

**Exponential Decay (if use_vehicle_acceleration):**
```
a(t) = a₀ · exp(-ln(2)·t / t_half)
v(t) = v₀ + ∫₀ᵗ a(τ) dτ
s(t) = s₀ + ∫₀ᵗ v(τ) dτ
```

**Trajectory Sampling:**

For times t = {0, Δt, 2Δt, ..., T}:
```
1. Compute arc length: s_i = s(t_i)
2. Find point on path: p_i = PathPoint(P, s_i)
3. Compute heading: θ_i = PathTangent(P, s_i)
4. Store: trajectory[i] = (p_i, θ_i, v_i)
```

**Lane Change Trajectory:**

Smooth lateral transition using polynomial or sigmoid:

```
Lateral offset:
  y_offset(t) = y_0 + Δy · sigmoid((t - t_start) / t_duration)
  
  sigmoid(x) = 1 / (1 + exp(-x))
```

Or polynomial:
```
  y(t) = a₀ + a₁·t + a₂·t² + a₃·t³
```

Solved to satisfy:
- y(0) = 0 (start in current lane)
- y(T_lc) = lane_width (end in target lane)
- ẏ(0) = 0, ẏ(T_lc) = 0 (smooth entry/exit)

Where T_lc = lateral_control_time_horizon

#### Uncertainty Modeling

**Lateral Position Uncertainty:**

At each trajectory point, lateral variance:
```
σ²_lat(t) = σ²₀ + k · t
```

Where:
- σ₀ = sigma_lateral_offset
- k = growth rate (typically 0.01-0.1 m²/s)

**Probability Distribution:**

Position p(t) modeled as Gaussian:
```
p(t) ~ N(μ(t), Σ(t))
```

Where:
```
μ(t) = predicted centerline position
Σ(t) = [σ²_lateral    0        ]
       [    0      σ²_longitudinal]
```

**Maneuver Probabilities:**

For hypotheses {H₁, H₂, ..., Hₖ}:

```
P(Hᵢ) ∝ exp(-cost(Hᵢ))
```

Cost factors:
- Lateral deviation from current path
- Required acceleration changes
- Lanelet-specific prior probabilities

Normalized:
```
P(Hᵢ) = exp(-cost(Hᵢ)) / ∑ⱼ exp(-cost(Hⱼ))
```

#### Lateral Acceleration Constraint

If check_lateral_acceleration_constraints enabled:

For each trajectory point:
```
a_lat = v² / R
```

Where R is path curvature radius.

Reject trajectory if:
```
a_lat > max_lateral_accel
```

**Curvature Calculation:**

For path discretization {p₁, p₂, ..., pₙ}:
```
κ_i = (θᵢ₊₁ - θᵢ) / ||pᵢ₊₁ - pᵢ||
R_i = 1 / |κ_i|
```

### Complexity

**Time Complexity:**

**Per Object:**

**Lanelet Association**:
- Candidate search: O(L)
  - L = nearby lanelets (typically 5-20)
- Distance computation: O(L · P)
  - P = points per lanelet centerline (~100)
- **Total**: O(L · P) ≈ O(1000) operations

**Hypothesis Generation**:
- Reachable lanelet search: O(V + E)
  - V = reachable lanelets (~10-50)
  - E = edges in routing graph (~3V)
- **Total**: O(4V) ≈ O(200) for V=50

**Trajectory Generation** (per hypothesis):
- Path concatenation: O(V · P)
- Trajectory sampling: O(N)
  - N = T / Δt = 15 / 0.5 = 30 points
- Arc length computation: O(N · P) (search along path)
- **Total per hypothesis**: O(V·P + N·P) ≈ O(N·P)

**Uncertainty Computation**: O(N)

**Lateral Acceleration Check**: O(N)

**Per Object Total**:
```
H hypotheses (typically 3-5):
T_object = O(L·P + V + H·N·P)
         ≈ O(H·N·P) when dominated by trajectory generation
         ≈ O(5 · 30 · 100) = O(15,000) operations
```

**Per Frame**:
```
M objects:
T_frame = O(M · H · N · P)
```

For 30 objects: ~450K operations → ~5-10 ms

**Space Complexity:**

**Per Object:**
- Trajectory points: H × N × (position + velocity + metadata)
  = 5 × 30 × 40 bytes = 6 KB
- Uncertainty: H × N × (covariance matrix)
  = 5 × 30 × 32 bytes = 4.8 KB
- Path storage: H × V × P × point
  = 5 × 20 × 100 × 12 bytes = 120 KB

**Total per object**: ~130 KB
**For 30 objects**: ~3.9 MB

**Performance Bottlenecks:**

1. **Arc Length Search**:
   - Finding path position for each trajectory point
   - Linear search through path segments: O(P) per point
   - Mitigation: Binary search, pre-compute arc length table

2. **Multiple Hypotheses**:
   - Each hypothesis requires full trajectory generation
   - Scales linearly with hypothesis count
   - Mitigation: Lazy evaluation, prune unlikely hypotheses early

3. **Long Prediction Horizons**:
   - 15s vehicle prediction → 30 trajectory points
   - Linear scaling with horizon
   - Mitigation: Adaptive horizon based on speed, coarser sampling for distant future

4. **Lanelet Topology Queries**:
   - Graph search for reachable lanelets
   - Can be expensive in complex intersections
   - Mitigation: Caching, pre-computed reachability maps

5. **Lateral Acceleration Validation**:
   - Adds 30-50% overhead
   - Curvature calculation requires numerical differentiation
   - Mitigation: Coarser validation (every N points), analytical curvature if available

**Parameter Trade-offs:**

- **`prediction_time_horizon`**:
  - Short (5-8s): Fast, sufficient for tactical planning
  - Long (15-20s): Slower, needed for strategic planning (highway)
  - Optimal: 10s urban, 15s highway

- **`prediction_sampling_delta_time`**:
  - Coarse (1.0s): Fewer points, faster, may miss details
  - Fine (0.2s): More points, smoother trajectories, slower
  - Optimal: 0.5s balances resolution and efficiency

- **`min_velocity_for_map_based_prediction`**:
  - Critical performance parameter
  - Stopped/slow objects use simple CV model (10× faster)
  - Should match typical stopped vehicle threshold

- **`check_lateral_acceleration_constraints`**:
  - Disabled: Faster, may generate infeasible paths
  - Enabled: Physically realistic, essential for planning safety
  - Optimal: Enable for vehicles, disable for pedestrians

- **`lateral_control_time_horizon`**:
  - Short (3s): Aggressive lane changes, higher lateral acceleration
  - Long (7s): Comfortable lane changes, more trajectory points
  - Optimal: 5s matches typical human lane change duration

- **`use_vehicle_acceleration`**:
  - Improves short-term accuracy (< 3s)
  - Adds exponential decay computation per point
  - Optimal: Enable for critical objects (e.g., cut-in scenarios)

## Summary

The Map-Based Prediction node generates future trajectories for tracked objects by leveraging HD map topology and lane structure. It produces multiple motion hypotheses (lane following, lane changes, turns) with associated probabilities and uncertainty estimates, sampling trajectories at regular intervals along lanelet centerlines while respecting physics constraints, providing essential input for trajectory planning and decision-making in autonomous driving.

