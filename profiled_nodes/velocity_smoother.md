# Velocity Smoother Node

## Node Name
`/planning/scenario_planning/velocity_smoother`

## Links
- [GitHub - Velocity Smoother](https://github.com/autowarefoundation/autoware.universe/tree/main/planning/autoware_velocity_smoother)
- [Autoware Documentation - Planning](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-architecture/planning/)

## Algorithms
- **Jerk-Limited Optimization**: L2-based velocity optimization with jerk constraints
- **Quadratic Programming (QP)**: Convex optimization for smooth velocity profiles
- **Sequential Quadratic Programming**: Iterative refinement under constraints
- **Pseudo-Jerk Minimization**: Approximate jerk reduction for efficiency

## Parameters

### Performance Impacting

- **`max_iterations`** (int):
  - **Description**: Maximum optimization iterations
  - **Default**: `100`
  - **Impact**: More iterations improve smoothness but increase computation time linearly

- **`max_acceleration`** (double):
  - **Description**: Maximum allowed acceleration
  - **Default**: `2.0` m/s²
  - **Impact**: Tighter limits require more iterations to satisfy, affects convergence

- **`min_deceleration`** (double):
  - **Description**: Maximum allowed deceleration (negative)
  - **Default**: `-2.5` m/s²
  - **Impact**: Tighter limits increase optimization difficulty

- **`max_jerk`** (double):
  - **Description**: Maximum allowed jerk
  - **Default**: `1.0` m/s³
  - **Impact**: Lower jerk limits produce smoother profiles but are computationally harder to achieve

- **`min_jerk`** (double):
  - **Description**: Maximum allowed negative jerk
  - **Default**: `-1.0` m/s³
  - **Impact**: Symmetric limits provide balanced acceleration/deceleration smoothing

### Other Parameters

- **`pseudo_jerk_weight`** (double):
  - **Description**: Weight for pseudo-jerk term in objective
  - **Default**: `100.0`
  - **Purpose**: Balances smoothness vs. velocity tracking

- **`over_v_weight`** (double):
  - **Description**: Penalty for exceeding input velocity
  - **Default**: `10000.0`
  - **Purpose**: Strong penalty ensures velocity limits respected

- **`over_a_weight`** (double):
  - **Description**: Penalty for exceeding acceleration limits
  - **Default**: `5000.0`
  - **Purpose**: Soft constraint for acceleration bounds

- **`over_j_weight`** (double):
  - **Description**: Penalty for exceeding jerk limits
  - **Default**: `1000.0`
  - **Purpose**: Soft constraint for jerk bounds

- **`jerk_filter_ds`** (double):
  - **Description**: Distance interval for jerk filtering
  - **Default**: `1.0` meters
  - **Purpose**: Spatial resolution for jerk calculation

## Explanation

### High Level

The Velocity Smoother refines velocity profiles from the motion velocity planner, ensuring they are not only safe and constraint-satisfying but also comfortable and feasible. It formulates velocity smoothing as an optimization problem: minimize discomfort (jerk) while respecting maximum acceleration, deceleration, and velocity constraints. The optimization produces trajectories that are smooth, drivable, and maintain passenger comfort.

The node operates by converting the discrete velocity profile into an optimization problem with quadratic objective (minimize velocity changes and jerk) subject to linear inequality constraints (bounds on velocity, acceleration, jerk). It solves this using iterative methods, typically converging in 10-50 iterations, producing a refined velocity profile that can be directly executed by the controller.

### Model

#### Problem Formulation

**Decision Variables:**

Velocity at each waypoint: v = [v₁, v₂, ..., vₙ]ᵀ

**Objective Function:**

Minimize weighted sum of terms:
```
J(v) = w_smooth · ||v - v_ref||² + w_jerk · ||j||² + penalties
```

Where:
- v_ref: reference velocity from motion planner
- j: jerk approximation
- penalties: soft constraint violations

**Detailed Objective:**

```
minimize: 
  w_smooth · Σᵢ (vᵢ - v_ref,i)²                     (track reference)
  + w_jerk · Σᵢ (jᵢ)²                               (minimize jerk)
  + w_over_v · Σᵢ max(0, vᵢ - v_max,i)²            (velocity limit violation)
  + w_over_a · Σᵢ max(0, |aᵢ| - a_max)²            (acceleration limit violation)
  + w_over_j · Σᵢ max(0, |jᵢ| - j_max)²            (jerk limit violation)
```

**Constraints:**

Hard constraints:
```
0 ≤ vᵢ ≤ v_max,i              ∀i (velocity bounds)
a_min ≤ aᵢ ≤ a_max            ∀i (acceleration bounds)
j_min ≤ jᵢ ≤ j_max            ∀i (jerk bounds)
```

**Acceleration Approximation:**

For waypoints separated by distance Δs:

```
aᵢ ≈ (vᵢ₊₁² - vᵢ²) / (2·Δs)
```

From kinematic equation: v² = v₀² + 2a·Δs

**Jerk Approximation (Pseudo-Jerk):**

```
jᵢ ≈ (aᵢ₊₁ - aᵢ) / Δs
   = ((vᵢ₊₂² - vᵢ₊₁²) / (2·Δs) - (vᵢ₊₁² - vᵢ²) / (2·Δs)) / Δs
   = (vᵢ₊₂² - 2vᵢ₊₁² + vᵢ²) / (2·Δs²)
```

#### Quadratic Programming Formulation

**Standard QP Form:**

```
minimize: (1/2) xᵀ·P·x + qᵀ·x
subject to: G·x ≤ h
            A·x = b
```

**Mapping:**

Decision variable: x = v (velocity vector)

**Objective Quadratic Matrix P:**

Combination of smoothness and jerk terms:
```
P = w_smooth · I + w_jerk · Jᵀ·J
```

Where J is the jerk operator matrix:
```
J = [1  -2   1   0  ...  0]
    [0   1  -2   1  ...  0] / (2·Δs²)
    [...................]
```

**Linear Term q:**

From reference velocity tracking:
```
q = -2 · w_smooth · v_ref
```

**Inequality Constraints G·x ≤ h:**

Velocity bounds:
```
vᵢ ≤ v_max,i  →  [1] · vᵢ ≤ v_max,i
vᵢ ≥ 0        →  [-1] · vᵢ ≤ 0
```

Acceleration bounds (non-linear, linearized):
```
(vᵢ₊₁² - vᵢ²) / (2·Δs) ≤ a_max
```

Linearization at current iterate v⁽ᵏ⁾:
```
vᵢ₊₁ · (vᵢ₊₁⁽ᵏ⁾ / Δs) - vᵢ · (vᵢ⁽ᵏ⁾ / Δs) ≤ a_max + constant
```

#### Sequential Quadratic Programming (SQP)

Since acceleration and jerk constraints are non-linear in v, use iterative linearization:

**Algorithm:**

```
Initialize: v⁽⁰⁾ = v_ref

For k = 0 to max_iterations:
  1. Linearize constraints at v⁽ᵏ⁾:
     G⁽ᵏ⁾, h⁽ᵏ⁾ = Linearize(v⁽ᵏ⁾)
  
  2. Solve QP:
     v⁽ᵏ⁺¹⁾ = argmin (1/2)vᵀ·P·v + qᵀ·v
              s.t. G⁽ᵏ⁾·v ≤ h⁽ᵏ⁾
  
  3. Check convergence:
     if ||v⁽ᵏ⁺¹⁾ - v⁽ᵏ⁾|| < ε:
       break

Return: v⁽ᵏ⁺¹⁾
```

**Convergence:**

Typically converges in 10-50 iterations for well-conditioned problems.

Convergence criterion:
```
||v⁽ᵏ⁺¹⁾ - v⁽ᵏ⁾||₂ < ε_abs + ε_rel · ||v⁽ᵏ⁾||₂
```

Where ε_abs = 0.01 m/s, ε_rel = 0.001

#### L2-Based Smoothing

Alternative to QP, simpler approximation:

**Direct Minimization:**

```
minimize: ||v - v_ref||² + λ||D²v||²
```

Where D² is second-difference operator (approximate curvature).

**Closed-form Solution:**

```
v_opt = (I + λ·D²ᵀD²)⁻¹ · v_ref
```

Can be solved efficiently using sparse linear solvers or iterative methods (conjugate gradient).

**Advantages:**
- Faster than QP (no iterative linearization)
- Simple implementation

**Disadvantages:**
- Hard to enforce strict bounds
- Less accurate jerk control

### Complexity

**Time Complexity:**

**Per QP Iteration:**

**Matrix Operations:**
- Quadratic form evaluation: O(n²)
  - n = number of waypoints
- Constraint evaluation: O(m·n)
  - m = number of constraints
- Sparse matrix operations (if sparse): O(n·k)
  - k = average non-zeros per row

**QP Solver:**
- Interior point method: O(n³) per iteration
- Active set method: O(n²) per iteration
- Sparse QP (exploiting structure): O(n) per iteration

**Per SQP Iteration:**
```
T_iter = O(n³) or O(n) for sparse
```

**Total:**
```
T_total = k_iter · T_iter
```

For typical values:
- n = 150 waypoints
- k_iter = 20 iterations
- Sparse QP: 20 × O(150) ≈ 3000 operations → 2-5 ms
- Dense QP: 20 × O(150³) ≈ 67M operations → 50-100 ms

**Space Complexity:**

**Dense Formulation:**
- P matrix: O(n²) = 150² × 8 bytes = 180 KB
- G matrix: O(m·n) ≈ O(3n²) = 540 KB
- Working memory: O(n²) = 180 KB

**Sparse Formulation:**
- P matrix: O(n·k) = 150 × 5 × 8 bytes = 6 KB
- G matrix: O(n·k) = 150 × 10 × 8 bytes = 12 KB
- Working memory: O(n·k) = 6 KB

**Total (sparse):** ~25 KB
**Total (dense):** ~900 KB

**Performance Bottlenecks:**

1. **Dense Matrix Operations**:
   - QP with full matrices is O(n³)
   - Becomes prohibitive for long trajectories (n > 300)
   - Mitigation: Exploit sparsity, use specialized solvers

2. **Iterative Convergence**:
   - May require 50+ iterations for tight constraints
   - Each iteration repeats expensive matrix operations
   - Mitigation: Warm start, adaptive termination

3. **Constraint Linearization**:
   - Non-linear constraints require repeated linearization
   - Adds overhead each iteration
   - Mitigation: Cache Jacobians, analytical derivatives

4. **Numerical Conditioning**:
   - Large weight differences (w_over_v = 10000 vs w_jerk = 100)
   - Can cause poor conditioning, slow convergence
   - Mitigation: Constraint scaling, preconditioners

5. **Real-time Guarantee**:
   - Optimization may not converge in time budget
   - Need anytime algorithm with acceptable intermediate solutions
   - Mitigation: Early termination with best-so-far, time-limited iterations

**Parameter Trade-offs:**

- **`max_iterations`**:
  - Few (10-20): Fast, may not fully converge
  - Many (100-200): Better solutions, higher latency
  - Optimal: 50 with sparse solver gives good balance

- **`max_acceleration / min_deceleration`**:
  - Tight (±1.5 m/s²): Very comfortable, may not track reference well
  - Loose (±3.0 m/s²): Less smooth, better tracking
  - Optimal: ±2.0 m/s² matches passenger comfort expectations

- **`max_jerk / min_jerk`**:
  - Tight (±0.5 m/s³): Very smooth, slower optimization
  - Loose (±2.0 m/s³): Faster convergence, less comfort benefit
  - Optimal: ±1.0 m/s³ provides noticeable comfort improvement

- **`pseudo_jerk_weight`**:
  - Low (10): Prioritizes velocity tracking over smoothness
  - High (1000): Very smooth but may deviate from reference
  - Optimal: 100 balances tracking and smoothness

- **`over_v_weight`**:
  - Must be high (>>100) to enforce velocity limits strictly
  - Acts as barrier function
  - 10000 ensures sub-mm/s violations

- **Sparse vs. Dense Solver**:
  - Sparse: O(n) per iteration, requires specialized library
  - Dense: O(n³) per iteration, simple implementation
  - Optimal: Sparse for n > 100, dense acceptable for short trajectories

## Summary

The Velocity Smoother refines velocity profiles using jerk-limited optimization formulated as a Quadratic Program. It minimizes discomfort (jerk) while tracking the reference velocity and respecting kinematic constraints (acceleration, deceleration limits), using Sequential Quadratic Programming to handle non-linear constraints. The result is a smooth, comfortable, and feasible velocity profile ready for controller execution in autonomous driving.

