# Occupancy Grid Map Node

## Node Name
`/perception/occupancy_grid_map/occupancy_grid_map_node`

## Links
- [GitHub - Probabilistic Occupancy Grid Map](https://github.com/autowarefoundation/autoware.universe/tree/main/perception/autoware_probabilistic_occupancy_grid_map)
- [Occupancy Grid Theory](http://robots.stanford.edu/papers/thrun.occgrid-ijrr.pdf)
- [Autoware Documentation - Perception](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-architecture/perception/)

## Algorithms
- **Bayesian Occupancy Mapping**: Probabilistic space representation using log-odds
- **Ray Casting**: Beam-based sensor model for LiDAR
- **Grid Cell Update**: Incremental Bayesian belief update
- **Point Cloud Projection**: 3D to 2D bird's-eye view transformation

## Parameters

### Performance Impacting

- **`map_length`** (double):
  - **Description**: Grid map extent in x-direction
  - **Default**: `100.0` meters
  - **Impact**: Directly affects grid size. 100m × 100m at 0.5m resolution = 40K cells

- **`map_width`** (double):
  - **Description**: Grid map extent in y-direction
  - **Default**: `100.0` meters
  - **Impact**: Combined with length determines total cell count: (length/resolution) × (width/resolution)

- **`map_resolution`** (double):
  - **Description**: Grid cell size
  - **Default**: `0.5` meters
  - **Impact**: Quadratic effect on cell count. 0.5m → 0.25m gives 4× more cells. Critical performance parameter

- **`use_height_filter`** (bool):
  - **Description**: Filter points by height before processing
  - **Default**: `true`
  - **Impact**: Reduces point count 50-80%, significantly speeds up processing

- **`min_height, max_height`** (double):
  - **Description**: Height range for filtering
  - **Default**: `-1.0, 2.0` meters
  - **Impact**: Determines what obstacles are considered. Affects point count and accuracy

- **`enable_single_frame_mode`** (bool):
  - **Description**: Process only current frame vs. temporal integration
  - **Default**: `false`
  - **Impact**: Single frame is 3-5× faster but loses temporal filtering advantages

- **`gridmap_update_method`** (string):
  - **Description**: "raycasting" or "pointcloud_projection"
  - **Default**: `"raycasting"`
  - **Impact**: Raycasting is 2-3× slower but provides free space information

### Other Parameters

- **`map_frame`** (string):
  - **Description**: Reference frame for grid map
  - **Default**: `"map"`
  - **Purpose**: Coordinate system for grid alignment

- **`base_link_frame`** (string):
  - **Description**: Vehicle body frame
  - **Default**: `"base_link"`
  - **Purpose**: Sensor pose reference

- **`gridmap_origin_frame`** (string):
  - **Description**: Origin convention ("base_link" for moving window)
  - **Default**: `"base_link"`
  - **Purpose**: Moving window vs. fixed map

- **`scan_origin_frame`** (string):
  - **Description**: LiDAR sensor frame
  - **Default**: `"base_link"`
  - **Purpose**: Ray origin for raycasting

- **`occupied_threshold`** (double):
  - **Description**: Probability threshold for occupied classification
  - **Default**: `0.6`
  - **Purpose**: Converts probabilistic map to binary for output

- **`free_threshold`** (double):
  - **Description**: Probability threshold for free classification
  - **Default**: `0.4`
  - **Purpose**: Free space detection

- **`update_probability_occupied`** (double):
  - **Description**: Probability increase for hit cells
  - **Default**: `0.7`
  - **Purpose**: Bayesian update magnitude for occupied

- **`update_probability_free`** (double):
  - **Description**: Probability decrease for ray cells
  - **Default**: `0.4`
  - **Purpose**: Bayesian update magnitude for free

## Explanation

### High Level

The Occupancy Grid Map node creates a 2D bird's-eye view representation of the environment, discretizing space into cells and estimating the probability that each cell is occupied by an obstacle. Unlike object-based representations, occupancy grids provide a complete spatial representation including unknown or ambiguous regions, making them valuable for planning in unstructured environments.

The node processes point clouds by projecting them onto a 2D grid and applying Bayesian updates. For each point, it updates not only the cell containing the point (as occupied) but also all cells along the ray from sensor to point (as free), implementing an inverse sensor model. Over time, repeated observations increase confidence, while the probabilistic framework naturally handles sensor noise and uncertainty.

### Model

#### Grid Representation

**Discrete Grid:**
```
Grid G = {c_{ij} | i ∈ [0, N_x), j ∈ [0, N_y)}
```

Where:
```
N_x = ⌈map_length / map_resolution⌉
N_y = ⌈map_width / map_resolution⌉
```

**Cell Coordinates:**

World position (x_w, y_w) → Grid indices (i, j):
```
i = ⌊(x_w - x_origin) / resolution⌋
j = ⌊(y_w - y_origin) / resolution⌋
```

**Cell State:**

Each cell maintains occupancy probability P(occupied | z):
```
0 ≤ P(c_{ij}) ≤ 1
```

Stored as log-odds for computational efficiency:
```
L(c_{ij}) = log(P(c_{ij}) / (1 - P(c_{ij})))
```

#### Bayesian Occupancy Update

**Inverse Sensor Model:**

For measurement z (point cloud):
```
P(c | z) = Bayes update based on whether point hits cell
```

**Log-Odds Form:**

```
L(c | z₁, z₂, ..., zₜ) = L(c | z₁, ..., zₜ₋₁) + L(c | zₜ) - L₀
```

Where L₀ = log(0.5/0.5) = 0 is the prior.

**Update Rule:**

For cell c and observation z:

If point hits cell c (occupied observation):
```
L(c) += log(P_occ / (1 - P_occ))
```

If ray passes through c (free observation):
```
L(c) += log(P_free / (1 - P_free))
```

Where:
- P_occ = update_probability_occupied
- P_free = update_probability_free

**Clamping:**

Prevent saturation:
```
L_min ≤ L(c) ≤ L_max
```

Typically:
```
L_min = log(0.01/0.99) ≈ -4.6
L_max = log(0.99/0.01) ≈ +4.6
```

**Probability Conversion:**

For output:
```
P(c) = 1 / (1 + exp(-L(c)))
```

#### Raycasting Algorithm

For each point p in point cloud:

**Step 1: Identify ray endpoints**
```
Origin: o = sensor_pose
Target: p = point_position
```

**Step 2: Bresenham-like line traversal**
```
Cells_on_ray = LineTraversal(o, p)
```

**Step 3: Update cells**
```
For each cell c in Cells_on_ray:
  if c == cell_containing(p):
    L(c) += Δ_occupied
  else:
    L(c) += Δ_free
```

**Bresenham 2D Algorithm:**

```
dx = |x₁ - x₀|
dy = |y₁ - y₀|
error = 0

while not at endpoint:
  visit current cell
  if 2·error < dy:
    y += step_y
    error += dx
  if 2·error > dx:
    x += step_x
    error -= dy
```

Complexity: O(d) where d = distance in cells

#### Point Cloud Projection Method

Alternative to raycasting (faster but no free space):

**For each point p:**

```
1. Filter by height: min_height ≤ p_z ≤ max_height
2. Project to 2D: (x, y) = (p_x, p_y)
3. Find grid cell: (i, j) = WorldToGrid(x, y)
4. Update: L(c_{ij}) += Δ_occupied
```

**No ray traversal** → much faster but loses free space information.

#### Temporal Integration

**Decay (forgetting factor):**

To handle dynamic environments:
```
L(c) = λ · L(c) + (1 - λ) · L₀
```

Where λ ∈ [0.9, 0.99] provides gradual decay toward prior.

**Moving Window:**

If gridmap_origin_frame = "base_link":
- Grid centered on vehicle
- Cells outside window are discarded
- Maintains constant computational cost

### Complexity

**Time Complexity:**

**Height Filtering:**
```
O(N) where N = point cloud size
Typical: 100K points → 20K points after filtering
```

**Per Point Processing:**

**Raycasting Method:**
- Ray traversal: O(d_avg)
  - d_avg = average ray length in cells
  - For 50m range, 0.5m resolution: d_avg ≈ 100 cells
- Cell update: O(1) per cell
- **Per point**: O(d_avg)

**Total raycasting:**
```
T_raycast = O(N · d_avg)
          = O(20K · 100) = O(2M) operations
```

**Projection Method:**
- Coordinate transform: O(1)
- Grid index: O(1)
- Cell update: O(1)
- **Per point**: O(1)

**Total projection:**
```
T_project = O(N) = O(20K) operations
```

**Grid Output:**
- Log-odds to probability: O(N_cells)
- For 100m × 100m at 0.5m: O(40K) conversions

**Per Frame Latency:**
- Raycasting: 10-30 ms
- Projection: 2-5 ms
- Grid conversion: 1-2 ms

**Space Complexity:**

**Grid Storage:**
```
Memory = N_x · N_y · bytes_per_cell
```

Each cell stores:
- Log-odds: 4 bytes (float)
- Optional metadata: 1-2 bytes

**Total:**
```
For 100m × 100m at 0.5m resolution:
  = 200 × 200 × 4 bytes
  = 160 KB
```

**For 0.25m resolution:**
```
  = 400 × 400 × 4 bytes  
  = 640 KB
```

**Point Cloud Buffer:**
```
20K points × 12 bytes = 240 KB
```

**Total Memory:** ~400KB - 1MB

**Performance Bottlenecks:**

1. **Raycasting Overhead**:
   - Dominates computation (70-80% of time)
   - Many cache misses due to random cell access
   - Mitigation: Projection mode for free space, optimized line traversal

2. **Grid Resolution**:
   - Quadratic scaling with resolution
   - 0.25m vs 0.5m: 4× more cells, 4× slower
   - Mitigation: Adaptive resolution, hierarchical grids

3. **Large Point Clouds**:
   - Urban environments: 100K+ points
   - Linear scaling with point count
   - Mitigation: Height filtering, voxel downsampling

4. **Memory Bandwidth**:
   - Scattered writes to grid cells
   - Poor cache locality
   - Mitigation: Tiled processing, cell access reordering

5. **Coordinate Transformations**:
   - TF lookups for each frame
   - Point transformation overhead
   - Mitigation: Batch transforms, cached TF

**Parameter Trade-offs:**

- **`map_resolution`**:
  - Fine (0.2-0.3m): High detail, 4-9× slower, larger memory
  - Coarse (0.5-1.0m): Fast, less detail, sufficient for most planning
  - Optimal: 0.5m for general use, 0.25m for tight spaces (parking)

- **`map_length / map_width`**:
  - Small (50m): Fast, limited range
  - Large (200m): Covers more area, 16× more cells
  - Optimal: 100m for urban, 150m for highway

- **`use_height_filter`**:
  - Essential for performance (50-80% speedup)
  - Removes ground and overhanging obstacles
  - Should always be enabled

- **`min_height / max_height`**:
  - Narrow range: Fewer points, faster, may miss obstacles
  - Wide range: More complete, slower
  - Optimal: -0.5m to 2.0m captures road-level obstacles

- **`gridmap_update_method`**:
  - "raycasting": Slower (10-30ms), provides free space (critical for planning)
  - "pointcloud_projection": Faster (2-5ms), occupied only (sufficient for visualization)
  - Optimal: Raycasting for planning, projection for monitoring

- **`enable_single_frame_mode`**:
  - Enabled: Fast, no history, noisy
  - Disabled: Slower, temporal filtering, smoother
  - Optimal: Disable for production (temporal integration essential)

- **`update_probability_occupied / free`**:
  - Conservative (0.6/0.4): Slow convergence, robust to noise
  - Aggressive (0.8/0.3): Fast convergence, sensitive to outliers
  - Optimal: 0.7/0.4 balances convergence and robustness

- **`gridmap_origin_frame`**:
  - "base_link": Moving window, constant memory, better for long routes
  - "map": Fixed world frame, growing memory, better for localized operation
  - Optimal: "base_link" for autonomous driving

## Summary

The Occupancy Grid Map node creates a 2D probabilistic representation of occupied and free space by projecting point clouds onto a discrete grid and applying Bayesian updates. It uses raycasting to mark both occupied cells (where points land) and free cells (along sensor rays), providing a complete environmental representation essential for planning and navigation in autonomous driving systems.

