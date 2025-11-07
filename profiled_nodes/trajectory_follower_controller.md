# Trajectory Follower Controller Node

## Node Name
`/control/trajectory_follower/controller_node_exe`

## Links
- [GitHub - Trajectory Follower](https://github.com/autowarefoundation/autoware.universe/tree/main/control/autoware_trajectory_follower_node)
- [GitHub - MPC Lateral Controller](https://github.com/autowarefoundation/autoware.universe/tree/main/control/autoware_mpc_lateral_controller)
- [GitHub - PID Longitudinal Controller](https://github.com/autowarefoundation/autoware.universe/tree/main/control/autoware_pid_longitudinal_controller)
- [MPC Theory](https://en.wikipedia.org/wiki/Model_predictive_control)

## Algorithms
- **Model Predictive Control (MPC)**: Predictive optimization for lateral control
- **PID Control**: Proportional-Integral-Derivative for longitudinal control
- **Kinematic Bicycle Model**: Vehicle dynamics approximation
- **QP Solver**: Quadratic programming for MPC optimization

## Parameters

### Performance Impacting

#### MPC Lateral Controller

- **`prediction_horizon`** (int):
  - **Description**: Number of future steps to predict
  - **Default**: `70`
  - **Impact**: Larger horizons improve trajectory following but increase computation exponentially. Directly affects QP problem size

- **`prediction_dt`** (double):
  - **Description**: Time step for predictions
  - **Default**: `0.1` seconds
  - **Impact**: Smaller dt improves accuracy but increases horizon length needed. Total prediction time = horizon × dt

- **`weight_lat_error`** (double):
  - **Description**: Lateral error penalty in cost function
  - **Default**: `1.0`
  - **Impact**: Higher values prioritize position accuracy over control effort

- **`weight_heading_error`** (double):
  - **Description**: Heading error penalty
  - **Default**: `1.0`
  - **Impact**: Higher values improve heading tracking

- **`weight_steering_input`** (double):
  - **Description**: Steering input magnitude penalty
  - **Default**: `1.0`
  - **Impact**: Higher values produce smoother but less responsive steering

- **`weight_steering_input_rate`** (double):
  - **Description**: Steering rate change penalty
  - **Default**: `1.0`
  - **Impact**: Higher values reduce steering oscillations

#### PID Longitudinal Controller

- **`kp`** (double):
  - **Description**: Proportional gain
  - **Default**: `1.0`
  - **Impact**: Higher values increase responsiveness but may cause oscillations

- **`ki`** (double):
  - **Description**: Integral gain
  - **Default**: `0.1`
  - **Impact**: Eliminates steady-state error but can cause overshoot

- **`kd`** (double):
  - **Description**: Derivative gain
  - **Default**: `0.1`
  - **Impact**: Dampens oscillations but amplifies noise

### Other Parameters

- **`vehicle_wheelbase`** (double):
  - **Description**: Distance between front and rear axles
  - **Default**: `2.79` meters
  - **Purpose**: Kinematic model parameter

- **`steer_lim`** (double):
  - **Description**: Maximum steering angle
  - **Default**: `0.610865` radians (35°)
  - **Purpose**: Physical steering limit

- **`steer_rate_lim`** (double):
  - **Description**: Maximum steering rate
  - **Default**: `0.524` radians/second (30°/s)
  - **Purpose**: Actuator rate limit

- **`max_acceleration`** (double):
  - **Description**: Maximum longitudinal acceleration
  - **Default**: `2.0` m/s²
  - **Purpose**: Acceleration limit for PID output

- **`min_deceleration`** (double):
  - **Description**: Maximum braking deceleration
  - **Default**: `-3.0` m/s²
  - **Purpose**: Braking limit

## Explanation

### High Level

The Trajectory Follower Controller generates steering and throttle/brake commands to track the planned trajectory. It consists of two independent controllers: MPC for lateral (steering) control and PID for longitudinal (speed) control. The MPC predicts vehicle motion over a time horizon, formulates tracking as an optimization problem, and solves for optimal steering commands. The PID controller compares actual vs. desired velocity and outputs acceleration/deceleration commands.

This separation allows specialized control strategies: MPC excels at preview-based steering control, exploiting look-ahead information for smooth path following, while PID provides simple, robust speed control. Together, they enable precise trajectory tracking essential for autonomous driving.

### Model

#### Kinematic Bicycle Model

**State Vector:**

```
x = [X, Y, ψ, v]ᵀ
```

Where:
- X, Y: position coordinates [m]
- ψ: heading angle [rad]
- v: longitudinal velocity [m/s]

**Control Input:**

```
u = [δ, a]ᵀ
```

Where:
- δ: steering angle [rad]
- a: acceleration [m/s²]

**Continuous-Time Dynamics:**

```
Ẋ = v · cos(ψ)
Ẏ = v · sin(ψ)
ψ̇ = v · tan(δ) / L
v̇ = a
```

Where L is the wheelbase.

**Discrete-Time Model:**

Using forward Euler discretization with time step Δt:

```
xₖ₊₁ = f(xₖ, uₖ)

Xₖ₊₁ = Xₖ + v_k · cos(ψₖ) · Δt
Yₖ₊₁ = Yₖ + v_k · sin(ψₖ) · Δt
ψₖ₊₁ = ψₖ + (v_k · tan(δₖ) / L) · Δt
vₖ₊₁ = vₖ + aₖ · Δt
```

**Linearization:**

For small deviations from reference trajectory:

```
Δxₖ₊₁ = A · Δxₖ + B · Δuₖ
```

Where:
```
A = ∂f/∂x |_(x_ref, u_ref)
B = ∂f/∂u |_(x_ref, u_ref)
```

**Jacobian Matrices:**

```
A = [1  0  -v·sin(ψ)·Δt   cos(ψ)·Δt  ]
    [0  1   v·cos(ψ)·Δt   sin(ψ)·Δt  ]
    [0  0        1         tan(δ)/L·Δt]
    [0  0        0              1      ]

B = [           0           0]
    [           0           0]
    [v/(L·cos²(δ))·Δt       0]
    [           0          Δt]
```

#### MPC Formulation

**Prediction Horizon:**

N steps, total time T = N · Δt

**Predicted State Sequence:**

```
X = [x₀, x₁, x₂, ..., xₙ]
```

**Control Sequence:**

```
U = [u₀, u₁, u₂, ..., uₙ₋₁]
```

**Cost Function:**

```
J(U) = Σₖ₌₀ᴺ⁻¹ [eₖᵀQeₖ + uₖᵀRuₖ + Δuₖᵀ·S·Δuₖ] + eₙᵀQₙeₙ
```

Where:
- eₖ = xₖ - x_ref,k: tracking error
- Δuₖ = uₖ - uₖ₋₁: control rate
- Q: state error weight matrix
- R: control input weight matrix
- S: control rate weight matrix
- Qₙ: terminal state weight

**Weight Matrices:**

```
Q = diag([0, 0, w_heading, w_lateral])

R = diag([w_steering, 0])

S = diag([w_steering_rate, 0])
```

**Constraints:**

Control bounds:
```
|δₖ| ≤ δ_max
|Δδₖ| ≤ Δδ_max
```

State bounds (optional):
```
e_lat,k ≤ e_lat_max (stay within drivable area)
```

**QP Problem:**

Reformulate as standard QP:
```
minimize: (1/2) Uᵀ H U + fᵀ U
subject to: A_ineq · U ≤ b_ineq
```

Where H is the Hessian and f is the linear term derived from the cost function.

**Solution:**

Use QP solver (e.g., OSQP, qpOASES):
```
U* = argmin J(U)
```

Apply first control:
```
u = U*[0]
```

Repeat at next time step (receding horizon).

**MPC Algorithm:**

```
At each control cycle:
  1. Measure current state x
  2. Get reference trajectory {x_ref,0, ..., x_ref,N}
  3. Linearize dynamics around reference
  4. Formulate QP problem
  5. Solve for optimal U*
  6. Apply u = U*[0]
  7. Shift horizon forward
```

#### PID Longitudinal Control

**Error Definition:**

```
e(t) = v_ref(t) - v_actual(t)
```

**PID Output:**

```
a(t) = Kₚ·e(t) + Kᵢ·∫₀ᵗ e(τ)dτ + Kᵈ·de(t)/dt
```

**Discrete Implementation:**

```
eₖ = v_ref,k - v_k
I_k = I_{k-1} + e_k · Δt
D_k = (e_k - e_{k-1}) / Δt

aₖ = Kₚ·eₖ + Kᵢ·Iₖ + Kᵈ·Dₖ
```

**Anti-Windup:**

Prevent integrator saturation:
```
if |a_k| > a_max:
  I_k = I_{k-1}  (don't update integral)
  a_k = clamp(a_k, a_min, a_max)
```

**Feed-forward Term:**

Optionally add reference acceleration:
```
a_k = a_fb + a_ref,k
```

Where a_fb is the PID feedback term.

#### Error Coordinates

**Frenet Frame:**

Convert Cartesian errors to path-relative:

For vehicle at (X, Y, ψ) relative to path point (X_ref, Y_ref, ψ_ref):

**Lateral Error:**

```
e_lat = -(X - X_ref)·sin(ψ_ref) + (Y - Y_ref)·cos(ψ_ref)
```

**Heading Error:**

```
e_ψ = ψ - ψ_ref
```

Normalize to [-π, π]:
```
e_ψ = atan2(sin(e_ψ), cos(e_ψ))
```

### Complexity

**Time Complexity:**

**MPC Lateral Controller:**

**Per Cycle:**
- Trajectory resampling: O(N_traj)
  - N_traj = trajectory length
- Nearest point search: O(log N_traj) with spatial index
- Linearization: O(N)
  - N = prediction horizon
- QP formulation: O(N²)
  - Construct Hessian: N×N matrix
- QP solving: O(N³) for dense, O(N) for sparse
  - Interior point: multiple iterations

**Total MPC:**
```
T_MPC = O(log N_traj + N² + N³)
      ≈ O(N³) for small problems
```

For N = 70:
- Dense QP: ~340K operations → 20-50 ms
- Sparse QP: ~70K operations → 5-10 ms

**PID Longitudinal Controller:**

- Error computation: O(1)
- PID calculation: O(1)
- **Total: ~0.1 ms** (negligible)

**Combined:** 5-50 ms depending on QP solver

**Space Complexity:**

**MPC:**
- State predictions: N × 4 floats = 70 × 4 = 280 floats = 1.1 KB
- Control sequence: N × 2 floats = 140 floats = 560 bytes
- Hessian matrix: N² floats = 4900 floats = 19.6 KB (dense)
- Sparse Hessian: ~3N floats ≈ 210 floats = 840 bytes
- Constraints: O(N) = ~1 KB

**Total MPC:** 2-20 KB depending on sparsity

**PID:**
- State variables: 10 floats = 40 bytes (negligible)

**Performance Bottlenecks:**

1. **QP Solver**:
   - Dominates MPC computation (70-90% of time)
   - Dense solvers scale O(N³)
   - Mitigation: Sparse solvers, warm start, code generation

2. **Long Prediction Horizons**:
   - N = 70 typical, some configs use N = 100+
   - Cubic scaling makes large horizons prohibitive
   - Mitigation: Adaptive horizon, hierarchical MPC

3. **Linearization Accuracy**:
   - Small-angle approximation breaks at high curvatures
   - May require shorter prediction steps
   - Mitigation: Nonlinear MPC (much more expensive), frequent relinearization

4. **Reference Trajectory Processing**:
   - Resampling and searching can add overhead
   - Particularly for high-resolution trajectories
   - Mitigation: Cached lookups, spatial indexing

5. **Real-Time Guarantees**:
   - QP solver may not converge in time budget
   - Need fallback or anytime behavior
   - Mitigation: Time-limited iterations, previous solution as fallback

**Parameter Trade-offs:**

- **`prediction_horizon`**:
  - Short (N=30): Fast (2-5ms), less preview, oscillatory
  - Long (N=100): Slow (20-100ms), smooth, better anticipation
  - Optimal: 50-70 gives 5-7s lookahead at highway speeds

- **`prediction_dt`**:
  - Small (0.05s): Fine resolution, larger N needed
  - Large (0.2s): Coarse, may miss path details
  - Optimal: 0.1s balances resolution and horizon length

- **Weight Tuning (Q, R, S)**:
  - High Q: Aggressive tracking, jerky steering
  - High R: Smooth steering, tracking lag
  - High S: Very smooth, slow response
  - Optimal: Requires tuning for specific vehicle dynamics

- **PID Gains**:
  - High Kₚ: Fast response, potential oscillation
  - High Kᵢ: Eliminates steady-state error, risk of overshoot
  - High Kᵈ: Damping, but noise sensitive
  - Optimal: Ziegler-Nichols or iterative tuning

- **QP Solver Selection**:
  - Dense (CVXPY, quadprog): Simple, O(N³), N < 50
  - Sparse (OSQP, qpOASES): Fast, O(N), requires setup, N > 30
  - Custom/Code-gen: Fastest, requires offline preparation
  - Optimal: Sparse for production, dense for prototyping

## Summary

The Trajectory Follower Controller uses Model Predictive Control for lateral steering and PID control for longitudinal speed tracking. MPC formulates steering as a constrained optimization problem over a prediction horizon, solving a quadratic program to find optimal steering commands that minimize tracking error while respecting actuator limits. PID provides simple, robust speed control, together enabling precise trajectory following for autonomous vehicles.

