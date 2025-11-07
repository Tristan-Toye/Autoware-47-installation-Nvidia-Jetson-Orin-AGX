# Multi-Object Tracker Node

## Node Name
`/perception/object_recognition/tracking/multi_object_tracker`

## Links
- [GitHub - Multi Object Tracker](https://github.com/autowarefoundation/autoware.universe/tree/main/perception/autoware_multi_object_tracker)
- [muSSP Algorithm](https://github.com/motokimura/mussp)
- [Autoware Documentation - Perception](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-architecture/perception/)

## Algorithms
- **muSSP (min-cost max-flow) Data Association**: Optimal assignment between detections and tracks
- **Extended Kalman Filter (EKF) Tracking**: State estimation for each object
- **Mahalanobis Distance Gating**: Association validation
- **Multi-model Tracking**: Separate motion models for different object types

## Parameters

### Performance Impacting

- **`publish_rate`** (double):
  - **Description**: Output publishing frequency
  - **Default**: `10.0` Hz
  - **Impact**: Higher rates reduce latency but increase computational load. Must process all objects at this rate

- **`car_tracker, truck_tracker, bus_tracker, etc.`** (string):
  - **Description**: Tracker model assignment for each class
  - **Default**: `"multi_vehicle_tracker"` for vehicles, `"pedestrian_and_bicycle_tracker"` for others
  - **Impact**: Different models have different computational costs and motion assumptions

- **`tracker_lifetime`** (double):
  - **Description**: Maximum time a track survives without measurements
  - **Default**: `1.0` seconds
  - **Impact**: Longer lifetime maintains tracks through occlusions but increases memory usage

- **`enable_delay_compensation`** (bool):
  - **Description**: Compensate for measurement delays using ego-motion
  - **Default**: `false`
  - **Impact**: Adds coordinate transformations for each object, ~20% overhead but improves accuracy

- **`consider_odometry_uncertainty`** (bool):
  - **Description**: Include odometry covariance in prediction
  - **Default**: `false`
  - **Impact**: More realistic uncertainty but adds covariance propagation cost

### Other Parameters

- **`world_frame_id`** (string):
  - **Description**: Global reference frame
  - **Default**: `"map"`
  - **Purpose**: Coordinate system for tracking

- **`ego_frame_id`** (string):
  - **Description**: Vehicle body frame
  - **Default**: `"base_link"`
  - **Purpose**: Ego-motion compensation reference

- **`min_known_object_removal_iou`** (double):
  - **Description**: IoU threshold for pruning overlapping known objects
  - **Default**: `0.1`
  - **Purpose**: Remove redundant or partially occluded objects

- **`min_unknown_object_removal_iou`** (double):
  - **Description**: IoU threshold for unknown object pruning
  - **Default**: `0.001`
  - **Purpose**: More aggressive pruning for uncertain objects

- **`pruning_generalized_iou_thresholds`** (list):
  - **Description**: Per-class GIoU thresholds for track pruning
  - **Default**: `[-0.3, -0.4, -0.6, -0.6, -0.6, -0.1, -0.1, -0.1]`
  - **Purpose**: Class-specific geometric overlap constraints

- **`pruning_distance_thresholds`** (list):
  - **Description**: Maximum distance between track and detection for association
  - **Default**: `[9.0, 5.0, 9.0, 9.0, 9.0, 4.0, 3.0, 2.0]` meters
  - **Purpose**: Spatially constrain associations, prevent far matches

- **`enable_unknown_object_velocity_estimation`** (bool):
  - **Description**: Estimate velocity for objects without detection velocity
  - **Default**: `true`
  - **Purpose**: Provides motion estimates from position changes

- **`publish_tentative_objects`** (bool):
  - **Description**: Output tracks before confirmation
  - **Default**: `false`
  - **Purpose**: Early detection vs. false positive trade-off

## Explanation

### High Level

The Multi-Object Tracker maintains temporal consistency of detected objects across frames, assigning unique IDs and estimating velocities. It solves the data association problem - matching current detections to existing tracks - using the muSSP algorithm, which formulates association as a min-cost max-flow problem ensuring globally optimal assignments under constraints.

For each track, the node maintains an Extended Kalman Filter that predicts the object's state between measurements and updates it when associated with detections. Different object classes use specialized motion models (constant velocity for vehicles, more complex models for pedestrians/cyclists) to accurately capture their dynamics. The tracker handles object appearance, disappearance, and temporary occlusions, providing stable object identities essential for prediction and planning.

### Model

#### State Representation

Each track maintains state x:

**Vehicle Track State** (7D):
```
x = [x, y, yaw, vₓ, vᵧ, vyaw, a]ᵀ
```

Where:
- (x, y): Position [m]
- yaw: Heading angle [rad]
- (vₓ, vᵧ): Velocity components [m/s]
- vyaw: Yaw rate [rad/s]
- a: Acceleration [m/s²]

**Pedestrian/Bicycle Track State** (6D):
```
x = [x, y, vₓ, vᵧ, a, vyaw]ᵀ
```

Simplified model without explicit heading.

#### Motion Models

**Constant Velocity Model** (for vehicles):

```
xₖ₊₁ = F · xₖ + wₖ
```

State transition matrix F:
```
F = [1  0   0   Δt  0   0   0]
    [0  1   0   0   Δt  0   0]
    [0  0   1   0   0   Δt  0]
    [0  0   0   1   0   0   0]
    [0  0   0   0   1   0   0]
    [0  0   0   0   0   1   0]
    [0  0   0   0   0   0   1]
```

Process noise Q (higher for uncertain classes):
```
Q = diag([σ²_x, σ²_y, σ²_yaw, σ²_vx, σ²_vy, σ²_vyaw, σ²_a])
```

**CTRV Model** (Constant Turn Rate and Velocity):

For pedestrians/bicycles with more variable motion:
```
xₖ₊₁ = [xₖ + (vₖ/ωₖ)(sin(yawₖ + ωₖΔt) - sin(yawₖ))]
       [yₖ + (vₖ/ωₖ)(cos(yawₖ) - cos(yawₖ + ωₖΔt))]
       [yawₖ + ωₖΔt]
       [vₖ]
       [ωₖ]
```

Non-linear → requires EKF linearization.

#### Data Association: muSSP Algorithm

**Problem Formulation:**

Given:
- T tracks: {t₁, t₂, ..., tₜ}
- D detections: {d₁, d₂, ..., dₐ}

Find optimal assignment minimizing total cost:
```
min ∑ᵢⱼ cᵢⱼ · xᵢⱼ
```

Subject to:
- Each detection assigned to at most one track: ∑ᵢ xᵢⱼ ≤ 1
- Each track assigned to at most one detection: ∑ⱼ xᵢⱼ ≤ 1
- xᵢⱼ ∈ {0, 1}

**Cost Matrix:**

Mahalanobis distance between track prediction and detection:
```
cᵢⱼ = √((zⱼ - h(x̂ᵢ))ᵀ · Sᵢ⁻¹ · (zⱼ - h(x̂ᵢ)))
```

Where:
- zⱼ: detection j measurement
- x̂ᵢ: predicted state of track i
- h(·): measurement function
- Sᵢ: innovation covariance

**Gating:**

Set cᵢⱼ = ∞ if:
```
- Mahalanobis distance > gate_threshold (typically 9.21 for χ² p=0.01)
- Euclidean distance > pruning_distance_threshold[class]
- GIoU < pruning_giou_threshold[class]
```

**muSSP Solver:**

Converts to network flow problem:
```
Source → Tracks → Detections → Sink
         ↓
       Dummy (unmatched)
```

Capacities:
- All edges: capacity = 1
- Source to tracks: 1 (each track can be updated once)
- Detections to sink: 1 (each detection used once)

Solved using Successive Shortest Path algorithm: O(V²E log V)
- V = T + D + 2 (vertices)
- E = T×D + T + D (edges)

Complexity: O((T+D)² · T·D · log(T+D)) ≈ O((T+D)³ log(T+D))

**Practical Performance:** O(T·D) for sparse cost matrices with gating

#### EKF Update

For each successfully associated track-detection pair:

**Prediction Step** (already computed):
```
x̂ₖ|ₖ₋₁ = F · x̂ₖ₋₁|ₖ₋₁
Pₖ|ₖ₋₁ = F · Pₖ₋₁|ₖ₋₁ · Fᵀ + Q
```

**Measurement Model:**
```
z = h(x) = [x, y, yaw, vₓ, vᵧ, vyaw, length, width, height]ᵀ
```

(Detection provides position, orientation, size, and optionally velocity)

**Update:**
```
y = z - h(x̂ₖ|ₖ₋₁)                    (innovation)
S = H · Pₖ|ₖ₋₁ · Hᵀ + R               (innovation covariance)
K = Pₖ|ₖ₋₁ · Hᵀ · S⁻¹                 (Kalman gain)
x̂ₖ|ₖ = x̂ₖ|ₖ₋₁ + K · y                (state update)
Pₖ|ₖ = (I - K·H) · Pₖ|ₖ₋₁            (covariance update)
```

#### Track Management

**Track Creation:**
```
New detection d not associated → create tentative track
If tentative track confirmed for n consecutive frames → promote to confirmed
```

**Track Deletion:**
```
If no association for tracker_lifetime → delete track
```

**Track Confidence:**
```
confidence = n_hits / (n_hits + n_misses)
```

Where n_hits = successful associations, n_misses = failed associations

#### Multi-Model Tracking

For ambiguous objects (e.g., pedestrian vs. bicycle):

**Run multiple trackers in parallel:**
```
Track T maintains {Model₁, Model₂}
Each model has own (x, P, likelihood)
```

**Model Probability:**
```
P(Mᵢ | Z) ∝ P(z | Mᵢ) · P(Mᵢ)
```

**Output:** Use highest probability model or model-averaged estimate

### Complexity

**Time Complexity:**

**Per Frame:**

**Prediction** (all tracks):
- Per track: O(n²) where n = state dimension (7 for vehicles)
- All tracks: O(T · n²) ≈ O(T · 49)

**Data Association:**
- Cost matrix computation: O(T · D · m)
  - m = measurement dimension (9)
- muSSP solver: O((T+D)³ log(T+D)) worst case
  - With gating: typically O(T · D · k) where k = avg neighbors
- Practical: O(T · D) for sparse associations

**Update** (matched tracks):
- Per track: O(n³) for matrix inversion
- M matched tracks: O(M · n³) ≈ O(M · 343)

**Track Management**: O(T)

**Total:**
```
T_frame = O(T·49 + T·D + M·343)
        ≈ O(T·D) for T,D << 100
```

**Typical Performance:**
- 50 tracks, 30 detections
- Prediction: 50 × 50 operations = 2.5K ops
- Association: 50 × 30 = 1.5K matrix elements
- Update: 20 matched × 350 ops = 7K ops
- Total: ~2-5 ms on modern CPU

**Space Complexity:**

**Per Track:**
- State: n floats (7 for vehicles) = 28 bytes
- Covariance: n² floats = 196 bytes
- Additional metadata: ~100 bytes
- **Total per track**: ~324 bytes

**Global:**
- T tracks: 324T bytes
- Cost matrix: 4 · T · D bytes
- Association graph: variable, ~8(T+D) bytes

**Total:** ~0.3T + 4TD + 8(T+D) bytes

For 50 tracks, 30 detections: ~15KB + ~6KB + ~0.6KB ≈ 22KB

**Performance Bottlenecks:**

1. **Data Association Scaling**:
   - Quadratic in track/detection count
   - Dense scenes (urban intersections) challenging
   - Mitigation: Spatial partitioning, hierarchical association

2. **Multiple Tracks Per Object**:
   - False positives create redundant tracks
   - Pruning overhead increases
   - Mitigation: Aggressive IoU-based merging, confidence thresholding

3. **Covariance Updates**:
   - Matrix inversions for each update
   - Numerical stability issues for degenerate cases
   - Mitigation: Joseph form update (more stable), regularization

4. **Track Management Overhead**:
   - Iterating through all tracks each frame
   - Memory allocation/deallocation for creation/deletion
   - Mitigation: Object pooling, lazy deletion

**Parameter Trade-offs:**

- **`publish_rate`**:
  - Low (5 Hz): Lower CPU, larger prediction intervals, higher error
  - High (20 Hz): Smoother tracks, better for fast objects, higher CPU
  - Optimal: 10 Hz balances latency and accuracy for typical vehicle speeds

- **`tracker_lifetime`**:
  - Short (0.5s): Quick removal of disappeared objects, poor occlusion handling
  - Long (2.0s): Handles occlusions, slower removal of ghosts
  - Optimal: 1.0s for urban, 1.5s for highway (longer occlusions)

- **`enable_delay_compensation`**:
  - Essential for systems with >50ms sensor delay
  - Adds 20-30% overhead but significantly improves association accuracy
  - Optimal: Enable for production systems

- **`pruning_distance_thresholds`**:
  - Small: Faster association, may break tracks during sudden motion
  - Large: More robust, but slower association, potential far matches
  - Optimal: Class-dependent, 2-3× typical object velocity × publish period

- **`publish_tentative_objects`**:
  - Enabled: Early detection, more false positives
  - Disabled: More reliable, delayed detection
  - Optimal: Disable for planning, enable for awareness/visualization

- **Multi-model Tracking**:
  - Doubles computational cost per ambiguous object
  - Critical for pedestrian/bicycle discrimination
  - Optimal: Enable only for VRU (Vulnerable Road Users) classes

## Summary

The Multi-Object Tracker maintains consistent object identities across frames by solving the data association problem using muSSP optimization and tracking each object with an Extended Kalman Filter. It handles object appearances, disappearances, and occlusions while using class-specific motion models, providing stable object tracks with accurate velocity estimates essential for prediction and planning in autonomous driving.

