# Shape Estimation Node

## Node Name
`/perception/object_recognition/detection/clustering/shape_estimation`

## Links
- [GitHub - Shape Estimation](https://github.com/autowarefoundation/autoware.universe/tree/main/perception/autoware_shape_estimation)
- [PCA Algorithm](https://en.wikipedia.org/wiki/Principal_component_analysis)
- [L-Shape Fitting Paper](https://www.sciencedirect.com/science/article/pii/S0921889017300647)

## Algorithms
- **Principal Component Analysis (PCA)**: Finds dominant directions in point clusters
- **L-Shape Fitting**: Fits L-shaped contours to vehicle corners
- **Bounding Box Estimation**: Computes oriented 3D bounding boxes
- **Convex Hull Computation**: Finds minimal enclosing polygon

## Parameters

### Performance Impacting

- **`use_corrector`** (bool):
  - **Description**: Enable L-shape fitting refinement
  - **Default**: `true`
  - **Impact**: L-shape fitting adds 30-50% computational cost but significantly improves vehicle orientation accuracy

- **`use_boost_bbox_optimizer`** (bool):
  - **Description**: Use iterative bounding box optimization
  - **Default**: `false`
  - **Impact**: Optimization improves fit quality but adds 50-100% computation time per object

- **`use_vehicle_reference_yaw`** (bool):
  - **Description**: Use reference yaw from tracking for initialization
  - **Default**: `true`
  - **Impact**: Improves convergence speed and prevents orientation flips, minimal overhead

- **`use_vehicle_reference_shape_size`** (bool):
  - **Description**: Use reference dimensions from tracking
  - **Default**: `true`
  - **Impact**: Stabilizes size estimation for tracked objects, negligible overhead

### Other Parameters

- **`min_points_for_valid_cluster`** (int):
  - **Description**: Minimum points required for shape estimation
  - **Default**: `3`
  - **Purpose**: Filters degenerate clusters before processing

- **`corrector_search_rough_offset_deg`** (double):
  - **Description**: Angular search range for L-shape fitting
  - **Default**: `20.0` degrees
  - **Purpose**: Limits search space for optimization

- **`vehicle_model_fitting_model`** (string):
  - **Description**: Model type for vehicle fitting ("convex_hull" or "bounding_box")
  - **Default**: `"convex_hull"`
  - **Purpose**: Trade-off between accuracy (convex hull) and speed (bounding box)

- **`use_fixed_vehicle_size`** (bool):
  - **Description**: Use predefined vehicle dimensions
  - **Default**: `false`
  - **Purpose**: For specific vehicle types with known dimensions

- **`fixed_vehicle_length, fixed_vehicle_width, fixed_vehicle_height`** (double):
  - **Description**: Fixed dimensions when use_fixed_vehicle_size=true
  - **Default**: `4.5, 1.8, 1.5` meters
  - **Purpose**: Override estimated dimensions

## Explanation

### High Level

The Shape Estimation node determines the size, orientation, and shape of detected object clusters. Given a set of 3D points representing an object, it computes an oriented bounding box that tightly fits the points while respecting the object's geometry. For vehicles, it uses specialized algorithms like L-shape fitting that exploit the rectangular nature of cars to accurately determine orientation even from sparse point clouds.

The process begins with PCA to find the dominant orientation, then optionally refines this using L-shape fitting which searches for the characteristic L-shaped corner patterns in vehicle point clouds. The output includes a 3D bounding box with position, dimensions (length, width, height), and orientation, enabling downstream modules to reason about object geometry and motion.

### Model

#### Principal Component Analysis (PCA)

Given cluster C = {p₁, p₂, ..., pₙ} where pᵢ ∈ ℝ³:

**Step 1: Compute Centroid**
```
μ = (1/n) ∑ᵢ₌₁ⁿ pᵢ
```

**Step 2: Construct Covariance Matrix**
```
Σ = (1/n) ∑ᵢ₌₁ⁿ (pᵢ - μ)(pᵢ - μ)ᵀ
```

Σ is a 3×3 symmetric matrix:
```
Σ = [σₓₓ  σₓᵧ  σₓᵧ]
    [σₓᵧ  σᵧᵧ  σᵧᵧ]
    [σₓᵧ  σᵧᵧ  σᵧᵧ]
```

**Step 3: Eigenvalue Decomposition**
```
Σ · vᵢ = λᵢ · vᵢ,  i = 1,2,3
```

Where:
- λ₁ ≥ λ₂ ≥ λ₃ are eigenvalues (variance along principal axes)
- v₁, v₂, v₃ are eigenvectors (principal directions)

**Step 4: Orientation Extraction**

Primary orientation (vehicle length direction):
```
θ_PCA = atan2(v₁ʸ, v₁ˣ)
```

**PCA Bounding Box:**

Dimensions computed by projecting points onto principal axes:
```
For each axis vᵢ:
  projections = {(pⱼ - μ) · vᵢ | j = 1..n}
  length_i = max(projections) - min(projections)

Dimensions: [length_1, length_2, length_3]
```

#### L-Shape Fitting

For vehicle-like objects, refine orientation using L-shape pattern:

**Algorithm:**

```
1. Project cluster to 2D (XY plane)
2. For each candidate angle θ ∈ [θ_PCA ± search_range]:
   a. Rotate points by -θ (align with axes)
   b. Compute axis-aligned bounding box
   c. Find corner point c = (max_x, max_y) or similar
   d. Fit two perpendicular lines from c
   e. Compute fitting score S(θ)
3. Select θ_best = argmax S(θ)
```

**Fitting Score:**

Measures how well points align with L-shape:
```
S(θ) = -∑_{p∈C} min(d(p, L₁)², d(p, L₂)²)
```

Where:
- L₁, L₂ are perpendicular lines forming the L
- d(p, L) is distance from point p to line L

**Closed-form Line Fitting:**

For line passing through points {p₁, ..., pₘ}:
```
Direction: v = principal eigenvector of ∑(pᵢ - p̄)(pᵢ - p̄)ᵀ
Offset: Line passes through centroid p̄
```

**Angular Resolution:**

Search space discretized at 1-5° intervals:
```
angles = [θ_PCA - search_range : step : θ_PCA + search_range]
Number of evaluations: ~2 × search_range / step
```

For search_range=20°, step=2°: ~20 evaluations

#### Bounding Box Computation

**Oriented Bounding Box (OBB):**

Given orientation θ and cluster C:

**Step 1: Rotate points to aligned frame**
```
R(θ) = [cos(θ)  -sin(θ)  0]
       [sin(θ)   cos(θ)  0]
       [  0        0     1]

p'ᵢ = R(-θ) · (pᵢ - μ)
```

**Step 2: Compute axis-aligned extents**
```
x_min = min{p'ᵢˣ}, x_max = max{p'ᵢˣ}
y_min = min{p'ᵢʸ}, y_max = max{p'ᵢʸ}
z_min = min{p'ᵢᶻ}, z_max = max{p'ᵢᶻ}

length = x_max - x_min
width  = y_max - y_min
height = z_max - z_min
```

**Step 3: Compute center in world frame**
```
center_local = [(x_max + x_min)/2, (y_max + y_min)/2, (z_max + z_min)/2]
center_world = μ + R(θ) · center_local
```

**Output Representation:**

Bounding box B = (c, d, θ) where:
- c = (cₓ, cᵧ, cᵧ): center position
- d = (l, w, h): dimensions
- θ: yaw angle

#### Convex Hull Method

Alternative to simple bounding box for 2D footprint:

**Graham Scan Algorithm:**

```
1. Find lowest point p₀
2. Sort points by polar angle from p₀
3. Process points maintaining convex property:
   - Add point if it makes left turn
   - Remove last point if it makes right turn
```

**Complexity**: O(n log n)

**Minimum Area Rectangle:**

Given convex hull H, find minimum area enclosing rectangle:

```
For each edge e of H:
  Compute supporting lines parallel/perpendicular to e
  Measure rectangle area A(e)
  
Select rectangle with min(A)
```

**Rotating Calipers** method: O(n) given convex hull

### Complexity

**Time Complexity:**

**PCA-based Estimation**:
- Centroid computation: O(n)
- Covariance matrix: O(9n) = O(n)
- Eigendecomposition: O(27) = O(1) for 3×3 matrix
- Projection for dimensions: O(3n) = O(n)

**Total PCA**: O(n) where n = points in cluster

**L-Shape Fitting**:
- Angular search: k iterations (k ≈ 20)
- Per iteration:
  - Rotation: O(n)
  - Bounding box: O(n)
  - Score computation: O(n)
- **Total L-shape**: O(k·n) ≈ O(20n)

**Convex Hull (if enabled)**:
- Graham scan: O(n log n)
- Minimum rectangle: O(n)
- **Total convex hull**: O(n log n)

**Per Object**:
- PCA only: ~5 µs for 100 points
- PCA + L-shape: ~50 µs for 100 points
- PCA + Convex hull: ~30 µs for 100 points

**Per Frame** (50 objects):
- PCA only: 0.25 ms
- With L-shape: 2.5 ms
- With convex hull: 1.5 ms

**Space Complexity:**

- Input cluster: O(n × 12) bytes (x,y,z per point)
- Covariance matrix: O(9 × 8) = 72 bytes
- Rotated points (temporary): O(n × 12) bytes
- Convex hull: O(m × 8) bytes, m ≤ n (typically m << n)

**Total**: ~2n bytes per cluster (dominated by point storage)

**Performance Bottlenecks:**

1. **L-Shape Angular Search**:
   - Dominates computation for large search ranges
   - 20-40× slower than PCA alone
   - Mitigation: Reduce search_range, increase step size, use reference yaw

2. **Dense Clusters**:
   - Large clusters (500+ points) slow down all operations
   - Linear scaling with point count
   - Mitigation: Downsample cluster points before estimation

3. **Eigendecomposition**:
   - Usually fast for 3×3 matrices
   - Can be numerically unstable for degenerate cases
   - Mitigation: Add regularization to covariance matrix

4. **Memory Bandwidth**:
   - Repeated iteration over points
   - Cache misses for scattered points
   - Mitigation: Compact point storage, sequential access patterns

**Parameter Trade-offs:**

- **`use_corrector` (L-shape fitting)**:
  - Disabled: Fast (0.25ms for 50 objects), less accurate orientation (±10-20°)
  - Enabled: Slower (2.5ms for 50 objects), accurate orientation (±2-5°)
  - Optimal: Enable for vehicles, disable for pedestrians/unknown objects

- **`corrector_search_rough_offset_deg`**:
  - Small (10°): Fast, may miss correct orientation if PCA is off
  - Large (30°): Robust but slower
  - Optimal: 15-20° balances robustness and speed

- **`use_vehicle_reference_yaw`**:
  - Critical for tracked objects: drastically reduces L-shape search time
  - Can directly use reference yaw, skipping angular search entirely
  - Should always be enabled when tracking is available

- **`vehicle_model_fitting_model`**:
  - "bounding_box": Faster, axis-aligned, simpler
  - "convex_hull": More accurate footprint, better for obstacle avoidance
  - Optimal: Convex hull for planning, bounding box for classification

- **`use_boost_bbox_optimizer`**:
  - Iterative refinement of bounding box fit
  - Adds significant overhead (50-100% more time)
  - Benefit: Tighter fit, better for path planning
  - Optimal: Disable for real-time, enable for post-processing

## Summary

The Shape Estimation node computes oriented 3D bounding boxes for object clusters using PCA for initial orientation and optionally L-shape fitting for refined vehicle orientation. It outputs precise geometric representations including position, dimensions, and orientation, enabling accurate object modeling for tracking, prediction, and path planning in autonomous driving systems.

