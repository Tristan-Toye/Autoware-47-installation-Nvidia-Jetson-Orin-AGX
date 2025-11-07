# Pointcloud Concatenate Data Node

## Node Name
`/sensing/lidar/concatenate_data`

## Links
- [GitHub - Autoware Pointcloud Preprocessor](https://github.com/autowarefoundation/autoware.universe/tree/main/sensing/autoware_pointcloud_preprocessor)
- [Autoware Documentation - Sensing](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-architecture/sensing/)

## Algorithms
- **Time-based synchronization**: Approximate time synchronization of multiple LiDAR point clouds
- **Point cloud concatenation**: Merging multiple point clouds with TF transformations
- **Coordinate frame transformation**: Converting point clouds to a common reference frame

## Parameters

### Performance Impacting

- **`input_topics`** (list of strings):
  - **Description**: List of input point cloud topic names to concatenate
  - **Default**: Varies by sensor configuration
  - **Impact**: More input topics increase synchronization complexity and processing time linearly

- **`output_frame`** (string):
  - **Description**: Target coordinate frame for the concatenated point cloud
  - **Default**: `"base_link"`
  - **Impact**: Frame transformations add computational overhead proportional to point count

- **`timeout_sec`** (double):
  - **Description**: Maximum time difference allowed for synchronization
  - **Default**: `0.1` seconds
  - **Impact**: Smaller timeouts reduce latency but may cause message drops; larger values increase latency

- **`input_twist_topic_type`** (string):
  - **Description**: Type of twist message for motion compensation
  - **Default**: `"twist"`
  - **Impact**: Motion compensation adds processing time but improves accuracy for moving platforms

### Other Parameters

- **`publish_synchronized_pointcloud`** (bool):
  - **Description**: Whether to publish each synchronized pointcloud individually
  - **Default**: `false`
  - **Purpose**: Debug visualization of synchronization

- **`keep_input_frame_in_synchronized_pointcloud`** (bool):
  - **Description**: Preserve original frame IDs in synchronized clouds
  - **Default**: `true`
  - **Purpose**: Debugging and visualization purposes

- **`maximum_queue_size`** (int):
  - **Description**: Maximum number of messages to buffer per input topic
  - **Default**: `5`
  - **Purpose**: Prevents memory overflow during temporary slowdowns

## Explanation

### High Level

The Pointcloud Concatenate Data node is responsible for fusing data from multiple LiDAR sensors into a single unified point cloud. Modern autonomous vehicles typically use multiple LiDARs to achieve 360-degree coverage and redundancy. This node synchronizes point clouds based on their timestamps, transforms them to a common coordinate frame, and merges them into a single output.

The synchronization process is critical because LiDARs operate asynchronously - each sensor captures data at slightly different times. The node uses approximate time synchronization to find point clouds captured within a specified time window, ensuring the merged result represents a consistent snapshot of the environment.

### Model

#### Synchronization Algorithm

The node implements an approximate time synchronization policy:

**Time Matching Criterion:**
```
For messages M₁, M₂, ..., Mₙ from n sensors:
Accept if: |timestamp(Mᵢ) - timestamp(Mⱼ)| ≤ timeout_sec, ∀i,j
```

**Message Queue Management:**
```
For each input topic k:
  - Maintain queue Qₖ of size ≤ maximum_queue_size
  - On new message arrival:
    1. Add message to Qₖ
    2. Search for time-matched set across all queues
    3. If match found, remove matched messages and process
    4. If Qₖ exceeds maximum_queue_size, drop oldest message
```

#### Coordinate Transformation

For each point p in input cloud i, the transformation to the output frame is:

```
p'ᵢ = Toutput←input_i · pᵢ
```

Where:
- `pᵢ = [x, y, z, 1]ᵀ` (homogeneous coordinates)
- `Toutput←input_i` is the 4×4 transformation matrix from input frame i to output frame
- `p'ᵢ` is the transformed point in the output frame

The transformation matrix is obtained from TF2:
```
Toutput←input_i = [R  t]
                  [0  1]
```

Where R is a 3×3 rotation matrix and t is a 3×1 translation vector.

#### Concatenation Operation

The final concatenated point cloud PC is:
```
PC = ⋃ᵢ₌₁ⁿ {Toutput←input_i · pⱼ | pⱼ ∈ PCᵢ}
```

Where PCᵢ is the point cloud from sensor i, and n is the number of input sensors.

**Motion Compensation (optional):**

When enabled, points are adjusted for ego-vehicle motion during the scan:
```
p'ᵢ(t) = p'ᵢ + v × (t_ref - tᵢ)
```

Where:
- `v` is the vehicle velocity from twist message
- `t_ref` is the reference timestamp (usually the latest)
- `tᵢ` is the timestamp of point i

### Complexity

**Time Complexity:**

- **Synchronization**: O(k × m)
  - k = number of input topics
  - m = maximum_queue_size
  - Performed on each message arrival

- **Transformation**: O(N)
  - N = total number of points across all inputs
  - Each point requires one matrix-vector multiplication (constant time per point)

- **Concatenation**: O(N)
  - Memory copy and reordering operations

**Total per-frame latency**: O(k × m + N)

**Space Complexity:**

- **Memory Usage**: O(k × m × p̄)
  - p̄ = average points per cloud
  - Queue storage for all input topics

- **Output Cloud**: O(N)
  - N = sum of all input point counts

**Performance Bottlenecks:**

1. **TF Lookups**: 
   - Each frame requires k TF lookups
   - Bottleneck when transforms are not cached or frequently changing
   - Mitigation: Use managed_transform_buffer for caching

2. **Point Cloud Copying**:
   - Memory bandwidth limited for large point clouds
   - Typical LiDAR: 100K-300K points per frame
   - At 10 Hz with 4 sensors: ~4M points/second throughput required

3. **Synchronization Overhead**:
   - Queue management adds latency proportional to timeout_sec
   - Trade-off: tight synchronization (small timeout) vs. robustness (large timeout)

**Parameter Trade-offs:**

- **`timeout_sec`**: 
  - Smaller → Lower latency, higher risk of dropped frames
  - Larger → Higher latency, more robust to timing jitter
  - Optimal: Slightly larger than maximum sensor time skew

- **`maximum_queue_size`**:
  - Smaller → Lower memory, faster failure on timing issues  
  - Larger → Higher memory, more robust to temporary slowdowns
  - Optimal: 2-3× typical processing jitter in frame counts

- **Number of input topics**:
  - More sensors → Better coverage, higher computational cost
  - Typical configurations: 1-4 LiDARs for full autonomous vehicles

## Summary

The Pointcloud Concatenate Data node synchronizes and merges point clouds from multiple LiDAR sensors into a unified representation. It performs time-based message synchronization, coordinate frame transformations, and point cloud concatenation, providing a complete 360-degree environmental perception input for downstream processing modules like object detection and localization.

