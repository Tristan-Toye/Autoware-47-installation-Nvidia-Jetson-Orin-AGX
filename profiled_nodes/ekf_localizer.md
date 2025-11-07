# EKF Localizer Node

## Node Name
`/localization/pose_twist_fusion_filter/ekf_localizer`

## Links
- [GitHub - EKF Localizer](https://github.com/autowarefoundation/autoware.universe/tree/main/localization/autoware_ekf_localizer)
- [Autoware Documentation - Localization](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-architecture/localization/)
- [Extended Kalman Filter Theory](https://en.wikipedia.org/wiki/Extended_Kalman_filter)

## Algorithms
- **Extended Kalman Filter (EKF)**: Non-linear state estimation using linearization
- **2D Vehicle Kinematics Model**: Bicycle model with yaw rate dynamics
- **Mahalanobis Distance Gating**: Outlier rejection for measurements
- **Time Delay Compensation**: Handles varying input latencies
- **Automatic Yaw Bias Estimation**: Corrects for IMU mounting errors

## Parameters

### Performance Impacting

- **`predict_frequency`** (double):
  - **Description**: EKF prediction step frequency
  - **Default**: `50.0` Hz
  - **Impact**: Higher frequency improves tracking of fast dynamics but increases CPU usage linearly. Must be ≥2× maximum vehicle dynamics frequency

- **`extend_state_step`** (int):
  - **Description**: Number of augmented states for delay compensation
  - **Default**: `50`
  - **Impact**: More steps handle longer delays but increase state vector size quadratically (affects covariance matrix operations)

- **`pose_frame_id`** (string):
  - **Description**: Reference frame for pose measurements
  - **Default**: `"map"`
  - **Impact**: Frame lookups add latency; misaligned frames cause estimation errors

- **`enable_yaw_bias_estimation`** (bool):
  - **Description**: Estimate and compensate IMU yaw bias
  - **Default**: `true`
  - **Impact**: Adds one state variable, increases computational cost ~5%, significantly improves long-term accuracy

- **`proc_stddev_vx_c`** (double):
  - **Description**: Process noise for longitudinal velocity
  - **Default**: `2.0`
  - **Impact**: Larger values allow faster adaptation to changes but increase estimation variance

- **`proc_stddev_yaw_c`** (double):
  - **Description**: Process noise for yaw angle
  - **Default**: `0.005`
  - **Impact**: Critical for turning dynamics; too small causes lag, too large causes oscillation

### Other Parameters

- **`pose_additional_delay`** (double):
  - **Description**: Additional latency to account for in pose measurements
  - **Default**: `0.0` seconds
  - **Purpose**: Compensate for known sensor delays

- **`pose_gate_dist`** (double):
  - **Description**: Mahalanobis distance threshold for pose measurement acceptance
  - **Default**: `10000.0` (effectively disabled)
  - **Purpose**: Reject outlier measurements

- **`pose_smoothing_steps`** (int):
  - **Description**: Number of steps for smooth pose updates
  - **Default**: `5`
  - **Purpose**: Prevents estimation jumps from large corrections

- **`twist_additional_delay`** (double):
  - **Description**: Additional latency for twist measurements
  - **Default**: `0.0` seconds
  - **Purpose**: Compensate for twist sensor delays

- **`twist_gate_dist`** (double):
  - **Description**: Mahalanobis distance threshold for twist measurements
  - **Default**: `10000.0`
  - **Purpose**: Reject outlier velocity measurements

- **`publish_tf`** (bool):
  - **Description**: Broadcast TF transformation
  - **Default**: `true`
  - **Purpose**: Enable coordinate frame broadcasting

## Explanation

### High Level

The EKF Localizer fuses multiple sensor measurements (pose from NDT, velocity from wheel odometry, angular velocity from IMU) into a single, smooth, and accurate state estimate. It uses an Extended Kalman Filter, which optimally combines predictions from a vehicle motion model with noisy sensor measurements, weighting each by their uncertainty.

The node runs a prediction step at high frequency (typically 50 Hz) using the vehicle dynamics model, and incorporates measurements asynchronously as they arrive. This produces a continuous, low-latency pose and velocity estimate even when individual sensors update at different rates or experience temporary failures.

### Model

#### State Vector

The EKF maintains a state vector x:

```
x = [x, y, yaw, vx, wz, yaw_bias]ᵀ
```

Where:
- `x, y`: Position in map frame [m]
- `yaw`: Heading angle [rad]
- `vx`: Longitudinal velocity [m/s]
- `wz`: Yaw rate (angular velocity) [rad/s]
- `yaw_bias`: IMU yaw angle bias [rad] (optional)

**State Dimension**: n = 5 (without bias) or 6 (with bias)

#### Process Model (Prediction)

**Discrete-time kinematic model**:

```
xₖ₊₁ = f(xₖ, Δt) + wₖ
```

Where the motion model f is:

```
x_{k+1}     = x_k + vx_k·cos(yaw_k)·Δt
y_{k+1}     = y_k + vx_k·sin(yaw_k)·Δt
yaw_{k+1}   = yaw_k + wz_k·Δt
vx_{k+1}    = vx_k
wz_{k+1}    = wz_k
bias_{k+1}  = bias_k
```

This is a constant-velocity model with yaw rate control.

**Process Noise Covariance** Q:

```
Q = diag([σ²_x, σ²_y, σ²_yaw, σ²_vx, σ²_wz, σ²_bias])
```

Where each σ² is determined from the `proc_stddev_*` parameters.

#### Prediction Step

**State Prediction**:
```
x̂ₖ₊₁|ₖ = f(x̂ₖ|ₖ, Δt)
```

**Jacobian of Motion Model**:
```
F = ∂f/∂x = [1  0  -vx·sin(yaw)·Δt  cos(yaw)·Δt   0    0  ]
            [0  1   vx·cos(yaw)·Δt  sin(yaw)·Δt   0    0  ]
            [0  0         1              0        Δt    0  ]
            [0  0         0              1         0    0  ]
            [0  0         0              0         1    0  ]
            [0  0         0              0         0    1  ]
```

**Covariance Prediction**:
```
Pₖ₊₁|ₖ = F·Pₖ|ₖ·Fᵀ + Q
```

Where P is the state covariance matrix (6×6).

#### Measurement Models

**Pose Measurement** (from NDT):
```
z_pose = [x_meas, y_meas, yaw_meas]ᵀ
h_pose(x) = [x, y, yaw]ᵀ
```

Measurement matrix:
```
H_pose = [1  0  0  0  0  0]
         [0  1  0  0  0  0]
         [0  0  1  0  0  0]
```

**Twist Measurement** (from odometry):
```
z_twist = [vx_meas, wz_meas]ᵀ
h_twist(x) = [vx, wz]ᵀ
```

Measurement matrix:
```
H_twist = [0  0  0  1  0  0]
          [0  0  0  0  1  0]
```

**IMU Measurement** (angular velocity with bias compensation):
```
z_imu = wz_meas
h_imu(x) = wz + yaw_bias
```

Measurement matrix:
```
H_imu = [0  0  0  0  1  1]
```

#### Update Step

For each measurement z with observation model h(x) and measurement noise R:

**Innovation**:
```
y = z - h(x̂ₖ|ₖ₋₁)
```

**Innovation Covariance**:
```
S = H·Pₖ|ₖ₋₁·Hᵀ + R
```

**Mahalanobis Distance** (outlier rejection):
```
d² = yᵀ·S⁻¹·y
```

If d² > threshold, reject measurement.

**Kalman Gain**:
```
K = Pₖ|ₖ₋₁·Hᵀ·S⁻¹
```

**State Update**:
```
x̂ₖ|ₖ = x̂ₖ|ₖ₋₁ + K·y
```

**Covariance Update**:
```
Pₖ|ₖ = (I - K·H)·Pₖ|ₖ₋₁
```

#### Time Delay Compensation

To handle measurement delays, the filter maintains a history of states:

```
State History: {x̂ₜ₋ₙ, x̂ₜ₋ₙ₊₁, ..., x̂ₜ₋₁, x̂ₜ}
```

When a delayed measurement z_τ arrives (τ < t):

1. **Find historical state**: x̂_τ from history
2. **Apply update**: x̂'_τ = x̂_τ + K·(z_τ - h(x̂_τ))
3. **Repropagate**: Forward propagate correction through states τ+1 to t
4. **Smooth transition**: Blend correction over multiple steps to avoid jumps

**Augmented State Vector**:
```
x_aug = [x_t, x_{t-1}, x_{t-2}, ..., x_{t-n}]ᵀ
```

Size: (n_states × extend_state_step)

### Complexity

**Time Complexity:**

**Prediction Step** (at predict_frequency):
- **Matrix Multiplication (F·P·Fᵀ)**: O(n³)
  - For n=6: ~216 operations
- **Addition (P + Q)**: O(n²)
  - For n=6: 36 operations
- **Per prediction**: ~250 floating-point operations

**Update Step** (per measurement):
- **Innovation**: O(n·m)
  - m = measurement dimension (typically 2-3)
- **S = H·P·Hᵀ + R**: O(n²·m + m³)
- **Kalman Gain K = P·Hᵀ·S⁻¹**: O(n²·m + m³)
- **State Update**: O(n·m)
- **Covariance Update**: O(n³)

**Total per update**: O(n³) ≈ 216 ops for n=6

**With Delay Compensation**:
- State history storage: O(n × extend_state_step)
- Repropagation: O(n³ × affected_steps)
- Typically affects 5-10 steps: ~1K-2K operations

**Per Frame Computational Load**:
```
Predictions: 50 Hz × 250 ops = 12.5K ops/sec
Updates: 3 sensors × 10 Hz × 216 ops = 6.5K ops/sec
Total: ~19K floating-point ops/sec (negligible on modern CPU)
```

**Space Complexity:**

- **Current State**: O(n) = 6 floats = 24 bytes
- **Covariance Matrix**: O(n²) = 36 floats = 144 bytes
- **State History**: O(n × extend_state_step) = 6 × 50 = 300 floats = 1.2 KB
- **Covariance History**: O(n² × extend_state_step) = 36 × 50 = 1800 floats = 7.2 KB

**Total**: ~8.5 KB (negligible)

**Performance Bottlenecks:**

1. **Covariance Update**:
   - Matrix multiplication dominates computation
   - Cache-friendly implementation critical
   - Mitigation: Symmetric matrix optimizations, SIMD

2. **Delay Compensation Repropagation**:
   - Can affect multiple timesteps
   - Worst case: full history repropagation
   - Mitigation: Limit affected steps, use efficient Jacobian caching

3. **Measurement Synchronization**:
   - Waiting for delayed measurements can increase latency
   - Trade-off between latency and accuracy
   - Mitigation: Adaptive timeout based on typical delays

4. **Yaw Bias Convergence**:
   - Requires persistent excitation (turning)
   - Can take 30-60 seconds to converge
   - May affect initial localization accuracy

**Parameter Trade-offs:**

- **`predict_frequency`**:
  - Low (10-20 Hz): Misses high-frequency dynamics, causes discretization errors
  - High (50-100 Hz): Smooth estimates, higher CPU usage
  - Optimal: 2-5× maximum vehicle dynamic frequency (typically 50 Hz)

- **`extend_state_step`**:
  - Small (10-20): Cannot handle long delays, lower memory
  - Large (50-100): Handles delays up to 1-2 seconds, higher memory
  - Optimal: (max_expected_delay × predict_frequency) + margin

- **`proc_stddev_*`** (Process Noise):
  - Small: Trusts model, slow adaptation, low noise
  - Large: Fast adaptation, responds to changes, higher variance
  - Optimal: Tuned to actual vehicle dynamics variability

- **`pose_smoothing_steps`**:
  - Few (1-3): Fast response to corrections, potential jumps
  - Many (5-10): Smooth output, slower response
  - Optimal: Balance between smoothness and responsiveness (typically 5)

- **`enable_yaw_bias_estimation`**:
  - Disabled: Lower computational cost, assumes perfect IMU calibration
  - Enabled: Compensates for mounting errors, essential for production vehicles
  - Trade-off: 5% CPU increase vs. significant long-term accuracy improvement

## Summary

The EKF Localizer fuses pose estimates from NDT with velocity measurements from wheel odometry and angular velocity from IMU using an Extended Kalman Filter. It provides smooth, continuous state estimates at high frequency, handles asynchronous measurements with varying delays, and automatically compensates for sensor biases, producing robust and accurate vehicle localization for autonomous driving.

