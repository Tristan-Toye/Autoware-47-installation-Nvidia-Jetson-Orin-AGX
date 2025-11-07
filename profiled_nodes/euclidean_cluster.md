# Euclidean Cluster Node

## Node Name
`/perception/object_recognition/detection/clustering/euclidean_cluster`

## Links
- [GitHub - Euclidean Cluster](https://github.com/autowarefoundation/autoware.universe/tree/main/perception/autoware_euclidean_cluster)
- [PCL Euclidean Clustering](https://pointclouds.org/documentation/tutorials/cluster_extraction.html)
- [Autoware Documentation - Perception](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-architecture/perception/)

## Algorithms
- **Voxel Grid Downsampling**: Reduces point cloud density for efficiency
- **Euclidean Distance-Based Clustering**: DBSCAN-like algorithm for grouping nearby points
- **Connected Component Labeling**: Recursive region growing for cluster formation

## Parameters

### Performance Impacting

- **`tolerance`** (double):
  - **Description**: Maximum distance between points to be considered in the same cluster
  - **Default**: `0.7` meters
  - **Impact**: Critical parameter - smaller values create over-segmented clusters (splitting objects), larger values merge nearby objects. Directly affects clustering quality and computational cost

- **`voxel_leaf_size`** (double):
  - **Description**: Voxel grid resolution for downsampling
  - **Default**: `0.3` meters
  - **Impact**: Larger voxels reduce point count exponentially, improving speed but losing spatial resolution. 0.3m typical reduces 100K→10K points

- **`min_cluster_size`** (int):
  - **Description**: Minimum number of voxels to form a valid cluster
  - **Default**: `10`
  - **Impact**: Higher values filter small noise clusters but may reject small objects (pedestrians, cyclists). Linear effect on output count

- **`max_cluster_size`** (int):
  - **Description**: Maximum number of voxels per cluster
  - **Default**: `3000`
  - **Impact**: Prevents over-clustering (ground plane inclusion). Acts as safety limit for memory and processing

- **`max_voxel_cluster_for_output`** (int):
  - **Description**: Maximum voxels in output cluster (after filtering)
  - **Default**: `800`
  - **Impact**: Limits output point count for downstream processing. Voxels exceeding this are randomly sampled

- **`min_voxel_cluster_size_for_filtering`** (int):
  - **Description**: Clusters below this size exempt from per-voxel filtering
  - **Default**: `65`
  - **Impact**: Small objects keep full resolution; large objects are filtered for efficiency

- **`max_points_per_voxel_in_large_cluster`** (int):
  - **Description**: Maximum points allowed per voxel in large clusters
  - **Default**: `10`
  - **Impact**: Reduces redundant points in dense regions, significant speedup for large clusters

### Other Parameters

- **`min_points_number_per_voxel`** (int):
  - **Description**: Minimum points to consider a voxel occupied
  - **Default**: `1`
  - **Purpose**: Noise filtering at voxel level

- **`use_height`** (bool):
  - **Description**: Include Z coordinate in clustering
  - **Default**: `false`
  - **Purpose**: 2D clustering (XY only) is faster and prevents vertical over-segmentation

- **`input_frame`** (string):
  - **Description**: Frame ID for input point cloud
  - **Default**: `"base_link"`
  - **Purpose**: Coordinate system for distance calculations

- **`max_x, min_x, max_y, min_y, max_z, min_z`** (double):
  - **Description**: Crop box boundaries for region of interest
  - **Default**: `±200m` XY, `-10m` to `2m` Z
  - **Purpose**: Removes irrelevant points (sky, ground) before clustering

- **`negative`** (bool):
  - **Description**: Invert crop box (keep outside instead of inside)
  - **Default**: `false`
  - **Purpose**: Specialized cropping modes

## Explanation

### High Level

The Euclidean Cluster node segments a point cloud into distinct objects by grouping nearby points based on spatial proximity. It's a geometric clustering algorithm that doesn't require prior knowledge of object categories or shapes - it simply finds spatially connected regions in the point cloud.

The process begins by downsampling the input to a voxel grid, significantly reducing computational cost. Then, it applies a region-growing algorithm: starting from an unlabeled voxel, it recursively adds all neighbors within a distance threshold to the current cluster, continuing until no more points can be added. This produces clusters representing individual objects or distinct regions in the environment.

This node is particularly useful as a fallback detector for objects not covered by learning-based detectors, or as a preprocessing step to reduce downstream processing requirements. It's computationally efficient and deterministic, making it reliable for real-time operation.

### Model

#### Voxelization

Transform point cloud P = {p₁, p₂, ..., pₙ} into voxel grid V:

**Voxel Index Calculation:**
```
For point p = (x, y, z):
  voxel_idx = (⌊x/vₓ⌋, ⌊y/vᵧ⌋, ⌊z/vᵧ⌋)
```

Where (vₓ, vᵧ, vᵧ) = voxel_leaf_size

**Voxel Centroid:**
```
For voxel V containing points {p₁, ..., pₘ}:
  centroid(V) = (1/m) ∑ᵢ₌₁ᵐ pᵢ
```

Result: Downsampled cloud V with one representative point per occupied voxel.

**Complexity Reduction:**
```
Before: N = 100,000 points
After:  M = N / (voxel_leaf_size)³ ≈ 10,000 voxels (for 0.3m voxels)
```

#### Euclidean Clustering Algorithm

**Pseudo-code:**

```
Input: Voxel cloud V, distance threshold d
Output: Set of clusters C = {C₁, C₂, ..., Cₖ}

Initialize:
  labels = array of size |V|, all = UNLABELED
  cluster_id = 0

For each voxel v in V:
  If labels[v] == UNLABELED:
    cluster_id += 1
    RegionGrow(v, cluster_id)

Function RegionGrow(seed, id):
  queue = [seed]
  labels[seed] = id
  
  While queue not empty:
    current = queue.pop()
    neighbors = FindNeighbors(current, tolerance)
    
    For each neighbor n in neighbors:
      If labels[n] == UNLABELED:
        labels[n] = id
        queue.append(n)
```

**Neighbor Search:**

For 2D clustering (use_height = false):
```
Distance(v₁, v₂) = √((x₁-x₂)² + (y₁-y₂)²)
```

For 3D clustering (use_height = true):
```
Distance(v₁, v₂) = √((x₁-x₂)² + (y₁-y₂)² + (z₁-z₂)²)
```

Neighbors within threshold:
```
N(v) = {u ∈ V | Distance(v,u) ≤ tolerance}
```

#### Cluster Filtering

**Size Filtering:**
```
Valid clusters: C' = {C ∈ C | min_size ≤ |C| ≤ max_size}
```

**Point Density Filtering** (for large clusters):
```
If |C| > min_voxel_cluster_size_for_filtering:
  For each voxel V in C:
    Keep at most max_points_per_voxel_in_large_cluster points from V
```

**Output Size Limiting:**
```
If |C| > max_voxel_cluster_for_output:
  Randomly sample max_voxel_cluster_for_output voxels from C
```

#### Mathematical Properties

**Cluster Diameter:**

For cluster C with tolerance d:
```
max{Distance(p, q) | p, q ∈ C} ≤ n·d
```

Where n is the maximum path length through the cluster.

**Sensitivity to Tolerance:**

Small tolerance → More clusters, risk of over-segmentation:
```
lim_{d→0} |C| = |V| (each voxel is its own cluster)
```

Large tolerance → Fewer clusters, risk of merging:
```
lim_{d→∞} |C| = 1 (all voxels in one cluster)
```

**Optimal Tolerance Estimation:**

Empirically, for vehicle detection:
```
d_optimal ≈ 0.5 × min_object_dimension
```

For typical scenarios: d = 0.7m works well for most vehicle types.

### Complexity

**Time Complexity:**

**Voxelization**:
- **Hash table insertion**: O(N)
  - N = input point count
  - Average O(1) per point insertion

**Clustering**:
- **Naive approach**: O(M²)
  - M = number of voxels
  - Each voxel potentially checks all others

- **With spatial data structure** (KD-tree or grid):
  - **Building spatial index**: O(M log M)
  - **Range search per voxel**: O(k log M)
    - k = average neighbors (typically 6-26 for grid)
  - **Total**: O(M(k + log M))
  
**Per-voxel operations**:
- Label assignment: O(1)
- Queue operations: O(1) amortized

**Total clustering**: O(M log M) with spatial indexing

**Filtering**:
- Size filtering: O(K)
  - K = number of clusters
- Point density filtering: O(M)
- Output sampling: O(M)

**Total per Frame**:
```
T_total = O(N + M log M + M)
        ≈ O(M log M) for M << N
```

With typical values:
- N = 100K points
- M = 10K voxels
- K = 50 clusters
- Time: 5-15ms on CPU

**Space Complexity:**

**Memory Requirements**:
- Input cloud: O(N × 4) = 100K × 16 bytes = 1.6 MB
- Voxel grid: O(M × 16) = 10K × 16 bytes = 160 KB
  - Stores: position (12 bytes) + cluster_id (4 bytes)
- Label array: O(M × 4) = 10K × 4 bytes = 40 KB
- Spatial index (KD-tree): O(M × 32) = 10K × 32 bytes = 320 KB
- Queue (worst case): O(M × 4) = 40 KB

**Total**: ~2.2 MB (dominated by input cloud)

**Performance Bottlenecks:**

1. **Voxelization Hash Table**:
   - Many hash collisions slow down insertion
   - Cache misses for scattered points
   - Mitigation: Good hash function, aligned memory access

2. **Neighbor Search**:
   - Dominates clustering time (70-80%)
   - Random memory access patterns
   - Mitigation: Grid-based search (O(1) per neighbor) vs KD-tree, spatial locality optimization

3. **Large Cluster Growth**:
   - Queue size can grow very large for connected regions
   - Breadth-first search has poor cache behavior
   - Mitigation: Depth-first search, chunked processing

4. **Dense Point Clouds**:
   - Small voxel size → more voxels → slower
   - Urban environments particularly challenging
   - Mitigation: Adaptive voxel size, region-based processing

**Parameter Trade-offs:**

- **`tolerance`**:
  - Small (0.3-0.5m): Over-segmentation, splits vehicles, more clusters
  - Large (1.0-2.0m): Merges nearby objects, fewer clusters
  - Optimal: 0.7-1.0m for vehicle clustering, 0.3-0.5m for pedestrians

- **`voxel_leaf_size`**:
  - Small (0.1-0.2m): Preserves detail, slower, more voxels
  - Large (0.5-1.0m): Fast, loses small objects
  - Optimal: 0.3-0.5m balances speed and resolution
  - Relationship: Should be ≤ 0.5 × tolerance to avoid missed neighbors

- **`min_cluster_size`**:
  - Small (5-10): Keeps small objects, more false positives from noise
  - Large (20-50): Filters noise aggressively, may miss pedestrians/cyclists
  - Optimal: 10-15 voxels (corresponds to ~0.3-0.5m³ object at 0.3m voxels)

- **`max_cluster_size`**:
  - Prevents including ground plane or wall segments
  - Should be 2-3× largest expected object volume
  - For vehicles: 3000 voxels = 810m³ at 0.3m resolution (generous)

- **`use_height`**:
  - 2D (false): Faster, prevents vertical splits, better for ground vehicles
  - 3D (true): Better for multi-level scenes, slower
  - Optimal: false for road vehicles, true for general 3D scenes

- **`max_points_per_voxel_in_large_cluster`**:
  - Low (5-10): Aggressive downsampling, faster downstream, potential information loss
  - High (20-50): Preserves detail, slower
  - Optimal: 10-15 points balances information and efficiency

## Summary

The Euclidean Cluster node segments point clouds into distinct spatial regions using distance-based connectivity. It voxelizes the input for efficiency, then applies region growing to group nearby voxels into clusters, providing a fast, geometric-based object segmentation suitable for detecting objects missed by learning-based detectors or as input for shape estimation modules.

