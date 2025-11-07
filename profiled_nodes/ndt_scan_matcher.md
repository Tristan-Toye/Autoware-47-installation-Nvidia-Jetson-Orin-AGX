# NDT Scan Matcher Node

## Node Name
`/localization/pose_estimator/ndt_scan_matcher`

## Links
- [GitHub - NDT Scan Matcher](https://github.com/autowarefoundation/autoware.universe/tree/main/localization/autoware_ndt_scan_matcher)
- [Autoware Documentation - Localization](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-architecture/localization/)
- [Original NDT Paper](https://ieeexplore.ieee.org/document/1249285) - Biber & Straßer, 2003

## Algorithms
- **Normal Distributions Transform (NDT)**: Represents 3D space as a grid of cells, each modeled as a normal distribution
- **Newton's Method Optimization**: Iterative optimization to find the transformation that maximizes scan-to-map likelihood
- **Monte Carlo Initial Pose Estimation**: Particle-based initialization for global localization
- **Covariance Estimation**: Laplace approximation and Multi-NDT for uncertainty quantification

## Parameters

### Performance Impacting

- **`ndt_resolution`** (double):
  - **Description**: Voxel grid size for NDT representation
  - **Default**: `2.0` meters
  - **Impact**: Smaller values increase accuracy but exponentially increase memory and computation time. Directly affects the number of voxels: O((map_size/resolution)³)

- **`max_iterations`** (int):
  - **Description**: Maximum Newton optimization iterations
  - **Default**: `30`
  - **Impact**: More iterations improve convergence but increase latency linearly. Typical convergence: 10-20 iterations

- **`converged_param_transform_probability`** (double):
  - **Description**: Score threshold for convergence
  - **Default**: `3.0`
  - **Impact**: Lower values terminate earlier (faster but less accurate), higher values ensure better convergence

- **`voxel_leaf_size`** (double):
  - **Description**: Downsampling leaf size for input point cloud
  - **Default**: `0.5` meters
  - **Impact**: Larger values reduce point count, improving speed but reducing accuracy. Typical 64-layer LiDAR: ~100K→10K points at 0.5m

- **`initial_estimate_particles_num`** (int):
  - **Description**: Number of particles for Monte Carlo initialization
  - **Default**: `100`
  - **Impact**: More particles increase initialization robustness but add significant computational cost (linear scaling)

- **`num_threads`** (int):
  - **Description**: Number of parallel threads for NDT computation
  - **Default**: `4`
  - **Impact**: Linear speedup up to available CPU cores, diminishing returns beyond ~8 threads

### Other Parameters

- **`score_estimation_method_type`** (string):
  - **Description**: Method for score estimation: "normal" or "no_add_score"
  - **Default**: `"normal"`
  - **Purpose**: Alternative scoring methods for different scenarios

- **`covariance_estimation_method`** (string):
  - **Description**: "laplace" or "multi_ndt"
  - **Default**: `"laplace"`
  - **Purpose**: Affects pose uncertainty quantification

- **`regularization_enabled`** (bool):
  - **Description**: Use GNSS-based regularization
  - **Default**: `false`
  - **Purpose**: Prevents drift when GNSS is available

- **`critical_upper_bound_exe_time_ms`** (double):
  - **Description**: Maximum allowed execution time before warning
  - **Default**: `100.0` ms
  - **Purpose**: Performance monitoring and diagnostics

- **`use_dynamic_map_loading`** (bool):
  - **Description**: Load only nearby map portions
  - **Default**: `true`
  - **Purpose**: Essential for large maps to manage memory

- **`dynamic_map_loading_update_distance`** (double):
  - **Description**: Distance threshold for map update
  - **Default**: `20.0` meters
  - **Purpose**: Balance between map update frequency and performance

## Explanation

### High Level

The NDT Scan Matcher is the primary localization method in Autoware, responsible for estimating the vehicle's 6-DOF pose (x, y, z, roll, pitch, yaw) by matching LiDAR point clouds against a pre-built 3D map. Unlike traditional point-to-point matching (ICP), NDT represents the environment as a set of normal distributions, making it more robust to noise and requiring fewer points for accurate localization.

The node continuously receives point clouds from LiDAR sensors and matches them against the NDT map representation. It uses Newton's method to iteratively optimize the transformation that maximizes the likelihood of the current scan given the map. The result is a precise pose estimate with covariance, enabling the vehicle to know its position within centimeters.

### Model

#### NDT Representation

The map M is divided into a 3D grid of voxels. Each voxel V with sufficient points is represented by a normal distribution:

```
V ~ N(μ, Σ)
```

Where:
- `μ = (1/n)∑ᵢ pᵢ` is the mean position (centroid) of n points in the voxel
- `Σ = (1/n)∑ᵢ (pᵢ - μ)(pᵢ - μ)ᵀ` is the 3×3 covariance matrix

**Probability Density Function:**

For a point p, its probability of belonging to voxel V is:

```
P(p|V) = (1/√((2π)³|Σ|)) exp(-½(p - μ)ᵀΣ⁻¹(p - μ))
```

#### Score Function

For a scan S consisting of points {p₁, p₂, ..., pₙ} and a transformation T (rotation R and translation t):

```
S(T) = -∑ᵢ₌₁ⁿ exp(-½(T·pᵢ - μᵥᵢ)ᵀΣᵥᵢ⁻¹(T·pᵢ - μᵥᵢ))
```

Where Vᵢ is the voxel containing the transformed point T·pᵢ.

The negative sign converts maximizing probability to minimizing score, suitable for Newton's method.

#### Newton's Method Optimization

**Transformation Parameterization:**

```
T = [tx, ty, tz, rx, ry, rz]ᵀ (6-DOF pose)
```

**Iterative Update:**

```
Tₖ₊₁ = Tₖ - H⁻¹·g
```

Where:
- `g = ∇S(Tₖ)` is the gradient (6×1 vector)
- `H = ∇²S(Tₖ)` is the Hessian matrix (6×6)

**Gradient Computation:**

```
gᵢ = ∂S/∂Tᵢ = -∑ₚ [exp(-q) · Σ⁻¹(T·p - μ) · ∂(T·p)/∂Tᵢ]
```

Where `q = ½(T·p - μ)ᵀΣ⁻¹(T·p - μ)`

**Hessian Computation (Gauss-Newton approximation):**

```
H ≈ ∑ₚ [Jᵖᵀ · W · Jᵖ]
```

Where:
- `Jᵖ = ∂(T·p)/∂T` is the Jacobian
- `W = exp(-q) · Σ⁻¹` is a weighting matrix

**Convergence Criteria:**

```
Converged if: |ΔT| < ε_trans OR |S(Tₖ₊₁) - S(Tₖ)| < ε_score OR k ≥ max_iterations
```

#### Monte Carlo Initialization

For global localization without prior pose:

```
1. Sample N particles {T₁, T₂, ..., Tₙ} from uniform distribution over search space
2. Evaluate score S(Tᵢ) for each particle
3. Select Tₘₐₓ = argmax S(Tᵢ)
4. Use Tₘₐₓ as initial estimate for Newton optimization
```

#### Covariance Estimation

**Laplace Approximation:**

The pose covariance Σₚₒₛₑ is estimated from the Hessian:

```
Σₚₒₛₑ ≈ H⁻¹
```

This assumes the score function is locally quadratic near the optimum.

**Multi-NDT Method:**

Runs NDT from multiple perturbed initial poses and computes empirical covariance:

```
Σₚₒₛₑ = (1/m)∑ⱼ₌₁ᵐ (Tⱼ - T̄)(Tⱼ - T̄)ᵀ
```

Where Tⱼ are converged poses from different initializations and T̄ is their mean.

### Complexity

**Time Complexity:**

**Per Iteration:**
- **Voxel Lookup**: O(n log V)
  - n = number of points in scan
  - V = number of voxels in local map
  - Uses KD-tree or hash table for voxel lookup

- **Score Evaluation**: O(n)
  - Each point contributes one exponential calculation

- **Gradient/Hessian**: O(n × d²)
  - d = 6 (DOF)
  - Dominated by Hessian matrix construction

- **Matrix Inversion**: O(d³) = O(216)
  - 6×6 Hessian inversion, negligible compared to point processing

**Total per Frame:**
```
T_frame = O(max_iterations × n × d²)
        ≈ 30 × 10,000 × 36 = 10.8M operations
```

With typical parameters:
- Input points: 100K (full scan) → 10K (after downsampling)
- Iterations: 10-20 (typical convergence)
- Expected latency: 50-100ms on modern CPU

**Space Complexity:**

- **Map Representation**: O(V × 22)
  - Each voxel stores: mean (3 floats) + covariance (9 floats, symmetric) + metadata
  - Typical 500m × 500m × 10m map at 2m resolution: ~15K voxels = 330KB
  - Large maps (5km × 5km): ~6.25M voxels = 138MB

- **Point Cloud Storage**: O(n × 4)
  - n points × (x,y,z,intensity)
  - 100K points = 1.6MB

- **Optimization State**: O(d²) = 36 floats
  - 6×6 Hessian, negligible

**Performance Bottlenecks:**

1. **Point Cloud Downsampling**: 
   - VoxelGrid filter on 100K+ points
   - Typically 20-30% of total processing time
   - Mitigation: GPU-based downsampling, adaptive leaf size

2. **Voxel Lookup**:
   - Cache misses when scanning large areas
   - Hash table collisions with many voxels
   - Mitigation: Spatial hash with good distribution, prefetching

3. **Matrix Operations**:
   - Hessian construction requires many small matrix multiplications
   - Cache efficiency critical for performance
   - Mitigation: SIMD vectorization, blocking

4. **Map Loading** (dynamic mode):
   - I/O bound when crossing update boundaries
   - Can cause frame drops
   - Mitigation: Predictive loading, double buffering

**Parameter Trade-offs:**

- **`ndt_resolution`**:
  - Fine (0.5-1.0m): High accuracy, 8× memory vs. 2m, slower convergence
  - Coarse (2.0-4.0m): Fast, less memory, lower accuracy, better in feature-poor environments
  - Optimal: Match to environment feature density (urban: 1-2m, highway: 2-4m)

- **`voxel_leaf_size`**:
  - Small (0.1-0.3m): High accuracy, slow processing
  - Large (0.5-1.0m): Fast processing, potential information loss
  - Optimal: 2-4× ndt_resolution for balance

- **`max_iterations`**:
  - Few (10-15): Fast but may not converge in difficult scenes
  - Many (30-50): Robust but wasted computation if early convergence
  - Optimal: Use convergence thresholds with reasonable maximum

- **`num_threads`**:
  - Scaling typically good up to 4-8 threads
  - Beyond 8 threads: diminishing returns due to synchronization overhead
  - Optimal: Match to CPU core count, leave cores for other nodes

## Summary

The NDT Scan Matcher estimates vehicle pose by matching LiDAR scans to a pre-built map using the Normal Distributions Transform algorithm. It represents the environment as a grid of probabilistic voxels and uses Newton's method to optimize the scan-to-map alignment, providing centimeter-level localization accuracy essential for autonomous driving.

