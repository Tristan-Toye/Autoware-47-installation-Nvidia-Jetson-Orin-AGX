# LiDAR CenterPoint Node

## Node Name
`/perception/object_recognition/detection/centerpoint/lidar_centerpoint`

## Links
- [GitHub - LiDAR CenterPoint](https://github.com/autowarefoundation/autoware.universe/tree/main/perception/autoware_lidar_centerpoint)
- [CenterPoint Paper](https://arxiv.org/abs/2006.11275) - Yin, Zhou & Krähenbühl, 2021
- [Autoware Documentation - Perception](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-architecture/perception/)

## Algorithms
- **CenterPoint Deep Neural Network**: Center-based 3D object detection from point clouds
- **Voxel Feature Encoding**: Sparse 3D convolution for feature extraction
- **Bird's Eye View (BEV) Representation**: 2D feature map projection
- **Center Heatmap Prediction**: Gaussian heatmap for object center localization
- **Multi-head Regression**: Simultaneous prediction of size, orientation, and velocity

## Parameters

### Performance Impacting

- **`model_path`** (string):
  - **Description**: Path to ONNX model file
  - **Default**: Model-specific path
  - **Impact**: Different models have different accuracy/speed trade-offs. Larger models (e.g., 512×512 BEV) are more accurate but 2-4× slower

- **`score_threshold`** (double):
  - **Description**: Minimum confidence score for detections
  - **Default**: `0.35`
  - **Impact**: Lower thresholds increase recall but add false positives and processing time for post-processing. Higher thresholds improve precision but may miss objects

- **`circle_nms_dist_threshold`** (double):
  - **Description**: Distance threshold for non-maximum suppression
  - **Default**: `1.5` meters
  - **Impact**: Smaller values may split single objects into multiple detections; larger values may merge nearby objects

- **`iou_nms_target_class_names`** (list):
  - **Description**: Classes to apply IoU-based NMS
  - **Default**: `["CAR", "TRUCK", "BUS"]`
  - **Impact**: IoU NMS is more accurate but computationally expensive compared to distance-based NMS

- **`iou_nms_search_distance_2d`** (double):
  - **Description**: Search radius for IoU NMS candidates
  - **Default**: `10.0` meters
  - **Impact**: Larger search increases computational cost quadratically with object density

- **`iou_nms_threshold`** (double):
  - **Description**: IoU threshold for suppression
  - **Default**: `0.1`
  - **Impact**: Lower values are more aggressive in removing duplicates

- **`yaw_norm_thresholds`** (list):
  - **Description**: Orientation consistency thresholds per class
  - **Default**: `[0.3, 0.3, 0.3, 0.0, 0.0]`
  - **Impact**: Rejects detections with inconsistent orientations, reducing false positives but may reject valid detections

- **`has_variance`** (bool):
  - **Description**: Whether model outputs uncertainty estimates
  - **Default**: `false`
  - **Impact**: Uncertainty estimation adds network overhead but improves downstream fusion

### Other Parameters

- **`densification_world_frame_id`** (string):
  - **Description**: Reference frame for point cloud densification
  - **Default**: `"map"`
  - **Purpose**: Multi-frame accumulation for increased point density

- **`densification_num_past_frames`** (int):
  - **Description**: Number of past frames to accumulate
  - **Default**: `1` (no accumulation)
  - **Purpose**: Improves detection of distant objects but increases latency

- **`class_names`** (list):
  - **Description**: Ordered list of detection classes
  - **Default**: `["CAR", "TRUCK", "BUS", "TRAILER", "BICYCLE", "MOTORBIKE", "PEDESTRIAN"]`
  - **Purpose**: Maps network outputs to semantic classes

- **`rename_car_to_truck_threshold`** (double):
  - **Description**: Size threshold for car/truck reclassification
  - **Default**: `6.0` meters
  - **Purpose**: Corrects misclassifications based on size heuristics

- **`has_twist`** (bool):
  - **Description**: Whether model predicts velocity
  - **Default**: `false`
  - **Purpose**: Single-frame velocity prediction for initialization

## Explanation

### High Level

CenterPoint is a state-of-the-art deep learning model for 3D object detection from LiDAR point clouds. Unlike anchor-based detectors, CenterPoint represents objects as points (their centers) in bird's-eye view, making it simpler and more efficient. The network takes a raw point cloud, converts it to a voxelized representation, extracts features using 3D sparse convolutions, projects to a 2D bird's-eye view, and predicts object centers along with their properties (size, orientation, class, velocity).

This approach is particularly effective for autonomous driving because it naturally handles objects of varying sizes and orientations without predefined anchors, and the center-based representation enables efficient post-processing. CenterPoint achieves high accuracy while maintaining real-time performance, making it suitable for deployment on embedded platforms.

### Model

#### Network Architecture

**Input Processing**:

1. **Voxelization**: Point cloud P → Voxel grid V
   - Divide 3D space into voxels of size (Δx, Δy, Δz)
   - Typical: 0.1-0.2m resolution
   - Range: X∈[-50, 50]m, Y∈[-50, 50]m, Z∈[-3, 5]m

2. **Voxel Feature Encoding**:
   ```
   For voxel v containing points {p₁, p₂, ..., pₙ}:
   f_v = VFE({p₁, p₂, ..., pₙ})
   ```
   
   Common VFE: PointNet-style max pooling
   ```
   f_v = max({MLP(pᵢ) | pᵢ ∈ v})
   ```

**Backbone Network**:

3D Sparse Convolution Network (e.g., Sparse ResNet):
```
Features: F₀ → Conv3D → F₁ → ... → Fₙ
```

Sparse convolution processes only occupied voxels:
```
y[u] = ∑_{i∈N(u)} w[i] · x[i]
```
Where N(u) are occupied neighbors of voxel u.

**BEV Projection**:

Collapse Z-dimension to create bird's-eye view:
```
BEV[x,y] = ∑_z F[x,y,z] or max_z F[x,y,z]
```

Result: Feature map of size (H_BEV × W_BEV × C)
Typical: 400×400×256 for ±50m range at 0.25m BEV resolution

**Detection Heads**:

Multiple parallel heads predict different properties:

1. **Center Heatmap** H ∈ ℝ^(H×W×K):
   ```
   H[x,y,k] = σ(Conv(BEV))[x,y,k]
   ```
   Where k indexes object classes, σ is sigmoid activation
   
   Loss (Focal Loss):
   ```
   L_heat = -(1/N) ∑_{xyc} {
     (1-Ĥ)^α · log(Ĥ)           if H=1
     (1-H)^β · Ĥ^α · log(1-Ĥ)   otherwise
   }
   ```
   Where H is ground truth heatmap, Ĥ is prediction, α=2, β=4

2. **Center Offset** O ∈ ℝ^(H×W×2):
   ```
   O[x,y] = (Δx, Δy)
   ```
   Refines discretization error from BEV grid

3. **Dimensions** D ∈ ℝ^(H×W×3):
   ```
   D[x,y] = (length, width, height)
   ```

4. **Orientation** θ ∈ ℝ^(H×W×2):
   ```
   θ[x,y] = (sin(yaw), cos(yaw))
   ```
   Or multi-bin classification for better gradient flow

5. **Velocity** V ∈ ℝ^(H×W×2):
   ```
   V[x,y] = (vₓ, vᵧ)
   ```

**Object Extraction**:

1. **Peak Detection**: Find local maxima in heatmap H
   ```
   Peaks = {(x,y,c) | H[x,y,c] > threshold AND 
                      H[x,y,c] = max(H[N(x,y),c])}
   ```

2. **Property Extraction**: For each peak (x,y,c):
   ```
   Object = {
     class: c
     score: H[x,y,c]
     center: BEVToWorld(x + O[x,y])
     size: D[x,y]
     yaw: atan2(θ[x,y])
     velocity: V[x,y]
   }
   ```

3. **Non-Maximum Suppression**:
   
   **Distance-based NMS**:
   ```
   For objects sorted by score:
     Remove objects within distance threshold of higher-scored object
   ```
   
   **IoU-based NMS**:
   ```
   For objects sorted by score:
     Compute IoU with higher-scored objects
     Remove if IoU > threshold
   ```
   
   IoU for 3D boxes:
   ```
   IoU(B₁, B₂) = Volume(B₁ ∩ B₂) / Volume(B₁ ∪ B₂)
   ```

#### Training Objective

Total loss (during training):
```
L_total = L_heat + λ₁·L_offset + λ₂·L_size + λ₃·L_yaw + λ₄·L_vel
```

Where:
- L_heat: Focal loss for center heatmap
- L_offset: L1 loss for center offset
- L_size: L1 loss for dimensions
- L_yaw: Classification or regression loss for orientation
- L_vel: L1 loss for velocity

Typical weights: λ₁=1.0, λ₂=1.0, λ₃=1.0, λ₄=1.0

### Complexity

**Time Complexity:**

**Preprocessing**:
- **Voxelization**: O(N)
  - N = number of points (typically 100K-300K)
  - Hash-based voxel assignment: O(N) average case
  - Occupied voxels: O(V) where V << N (typically 5K-15K)

**Network Inference**:
- **3D Sparse Convolution**: O(V · k³ · C²)
  - V = occupied voxels
  - k = kernel size (typically 3)
  - C = feature channels
  - Sparse nature: ~10× faster than dense convolution
  
- **BEV Projection**: O(V)
  
- **2D Convolution Heads**: O(H_BEV · W_BEV · k² · C²)
  - H_BEV, W_BEV: BEV resolution (e.g., 400×400)
  - Multiple heads process in parallel

**Post-processing**:
- **Peak Detection**: O(H·W·K)
  - K = number of classes
  - Requires scanning entire heatmap
  
- **Distance-based NMS**: O(M²)
  - M = number of detected objects before NMS
  - Spatial hash table can reduce to O(M·log M)
  
- **IoU-based NMS**: O(M²)
  - For each pair, compute 3D IoU: O(1)
  - Can use early termination heuristics

**Total Latency** (typical on Jetson Orin):
```
Voxelization:    10-15 ms
Network Inference: 40-80 ms (model dependent)
Post-processing:  5-10 ms
Total:           55-105 ms (10-18 Hz)
```

**Space Complexity:**

**Input**:
- Point cloud: O(N · 4) = 100K points × 4 floats = 1.6 MB
- Voxel indices: O(V · 4) = 10K voxels × 4 ints = 160 KB

**Network**:
- Feature maps: O(V · C) for 3D, O(H·W·C) for BEV
- Typical: 10K×256 + 160K×256 = ~43 MB
- Weights: Model-dependent, typically 20-50 MB

**Output**:
- Detections: O(M · 20) = 100 objects × 20 floats = 8 KB (negligible)

**GPU Memory**: 500-800 MB total for inference

**Performance Bottlenecks:**

1. **3D Sparse Convolution**:
   - Dominates inference time (50-70%)
   - Memory bandwidth bound on embedded GPUs
   - Mitigation: Model optimization (pruning, quantization), smaller backbone

2. **BEV Resolution**:
   - Higher resolution (512×512 vs 400×400): Better for small objects but ~1.6× slower
   - Trade-off between detection range and accuracy
   - Mitigation: Adaptive resolution based on object distance

3. **IoU-based NMS**:
   - Quadratic in number of detections
   - Can dominate post-processing in crowded scenes
   - Mitigation: Spatial partitioning, parallel implementation

4. **Voxelization**:
   - CPU-GPU data transfer overhead
   - Can be bottleneck if not optimized
   - Mitigation: GPU-based voxelization, zero-copy memory

5. **Multi-frame Densification**:
   - Linear increase in points with frame count
   - Requires accurate ego-motion compensation
   - Trade-off: Better distant object detection vs. latency
   - Mitigation: Adaptive densification based on scene density

**Parameter Trade-offs:**

- **`score_threshold`**:
  - Low (0.2-0.3): High recall, more false positives, slower NMS
  - High (0.4-0.6): High precision, may miss objects, faster NMS
  - Optimal: Depends on safety-critical requirements (typically 0.3-0.4)

- **`circle_nms_dist_threshold`**:
  - Small (0.5-1.0m): Better separation, may over-segment large vehicles
  - Large (1.5-2.5m): Fewer duplicates, may merge nearby objects
  - Optimal: ~1.5× typical object spacing for target class

- **`iou_nms_threshold`**:
  - Low (0.1-0.3): Aggressive suppression, fewer duplicates
  - High (0.5-0.7): Conservative, may keep duplicates
  - Optimal: 0.1-0.2 for vehicles (large overlap tolerance)

- **Model Selection**:
  - Small models (200×200 BEV): 30-40ms, good for nearby objects
  - Medium models (400×400 BEV): 50-80ms, balanced performance
  - Large models (512×512 BEV): 100-150ms, best for distant objects
  - Optimal: Medium for production, can use multi-scale ensemble

- **`densification_num_past_frames`**:
  - 1 (no densification): Lowest latency, standard detection range
  - 3-5 frames: Improved distant detection, adds 2-3 frame latency
  - Optimal: 1-2 for urban, 3-5 for highway scenarios

## Summary

CenterPoint is a deep learning model that detects 3D objects from LiDAR point clouds by representing objects as center points in bird's-eye view. It uses sparse 3D convolutions for efficient feature extraction and predicts object centers, dimensions, orientations, and velocities in a single forward pass, achieving state-of-the-art accuracy while maintaining real-time performance on autonomous driving platforms.

