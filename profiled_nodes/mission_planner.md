# Mission Planner Node

## Node Name
`/planning/mission_planning/mission_planner`

## Links
- [GitHub - Mission Planner](https://github.com/autowarefoundation/autoware.universe/tree/main/planning/autoware_mission_planner_universe)
- [Dijkstra's Algorithm](https://en.wikipedia.org/wiki/Dijkstra%27s_algorithm)
- [Autoware Documentation - Planning](https://autowarefoundation.github.io/autoware-documentation/main/design/autoware-architecture/planning/)

## Algorithms
- **Dijkstra's Shortest Path**: Optimal route finding on lanelet routing graph
- **Goal Validation**: Footprint-based reachability checking
- **Route Section Creation**: Segmentation of route into functional units
- **Lanelet Routing Graph**: Topology-aware path planning

## Parameters

### Performance Impacting

- **`arrival_check_distance`** (double):
  - **Description**: Distance threshold to consider goal reached
  - **Default**: `1.0` meters
  - **Impact**: Affects goal achievement detection. Too small causes oscillation, too large premature goal declaration

- **`arrival_check_angle_deg`** (double):
  - **Description**: Heading angle threshold for goal achievement
  - **Default**: `45.0` degrees
  - **Impact**: Large values allow more lenient goal poses, small values require precise alignment

- **`goal_angle_threshold_deg`** (double):
  - **Description**: Maximum heading deviation for valid goal
  - **Default**: `45.0` degrees
  - **Impact**: Rejects goals that require infeasible orientations

- **`check_footprint_inside_lanes`** (bool):
  - **Description**: Validate that vehicle footprint fits in goal lanelet
  - **Default**: `true`
  - **Impact**: Adds geometric validation (~1-2ms), prevents unsafe goals but may reject valid narrow poses

- **`consider_no_drivable_lanes`** (bool):
  - **Description**: Allow routing through non-drivable lanelets
  - **Default**: `false`
  - **Impact**: Expands search space, slower but more flexible routing

### Other Parameters

- **`map_frame`** (string):
  - **Description**: Reference frame for route planning
  - **Default**: `"map"`
  - **Purpose**: Coordinate system for pose matching

- **`enable_correct_goal_pose`** (bool):
  - **Description**: Automatically adjust goal pose to lanelet centerline
  - **Default**: `false`
  - **Purpose**: Snap goals to valid driving positions

- **`reroute_time_threshold`** (double):
  - **Description**: Minimum time between reroute requests
  - **Default**: `10.0` seconds
  - **Purpose**: Prevents excessive replanning

- **`minimum_reroute_length`** (double):
  - **Description**: Minimum route change to trigger replanning
  - **Default**: `30.0` meters
  - **Purpose**: Avoids minor route adjustments

- **`arrival_check_duration`** (double):
  - **Description**: Time vehicle must remain near goal
  - **Default**: `1.0` seconds
  - **Purpose**: Confirms stable arrival

- **`allow_reroute_in_autonomous_mode`** (bool):
  - **Description**: Enable dynamic rerouting during autonomous operation
  - **Default**: `true`
  - **Purpose**: Handles blocked routes, detours

## Explanation

### High Level

The Mission Planner is responsible for global route planning from the vehicle's current position to a goal pose specified by the user or higher-level planner. It operates on the Lanelet2 HD map's routing graph, where nodes represent lanelets (lane segments) and edges represent legal transitions (lane continuations, lane changes, turns). Using Dijkstra's algorithm, it finds the shortest valid path through this graph that respects traffic rules and road topology.

The planner doesn't consider dynamic obstacles or traffic - it produces a static route based purely on the map structure and goal location. The output is a sequence of lanelets forming the route, along with metadata like lane changes and intersections. This route guides lower-level planners (behavior and motion planners) which handle dynamic obstacle avoidance and trajectory generation.

### Model

#### Lanelet Routing Graph

**Graph Structure:**

```
G = (V, E)
```

Where:
- V = set of lanelets in HD map
- E = directed edges representing allowed transitions

**Edge Types:**

1. **Successor**: Lane continuation (same lane forward)
2. **Left**: Left lane change
3. **Right**: Right lane change
4. **Adjacent Left/Right**: Neighbor lanes (for awareness)

**Edge Costs:**

```
cost(e) = length(lanelet_target) + penalty(e)
```

Penalties:
- Lane change: +5m equivalent
- Turn: +2m equivalent
- Road type change: variable

**Graph Construction:**

From Lanelet2 map, for each lanelet L:
```
For each regulatory element R affecting L:
  Add constraints to outgoing edges
  
For successor lanelets S:
  Add edge (L → S) with cost = length(S)
  
For adjacent lanelets A (left/right):
  If lane change allowed:
    Add edge (L → A) with cost = length(A) + lane_change_penalty
```

#### Dijkstra's Algorithm

**Input:** 
- Graph G = (V, E)
- Start lanelet s ∈ V
- Goal lanelet g ∈ V

**Output:** 
- Shortest path P = {s, l₁, l₂, ..., lₙ, g}
- Total cost C

**Algorithm:**

```
Initialize:
  dist[s] = 0
  dist[v] = ∞ for all v ≠ s
  prev[v] = null for all v
  Q = priority queue with all vertices, keyed by dist[]

While Q not empty:
  u = Q.extractMin()  // vertex with minimum dist
  
  if u == g:
    break  // goal reached
  
  for each neighbor v of u:
    alt = dist[u] + cost(u, v)
    
    if alt < dist[v]:
      dist[v] = alt
      prev[v] = u
      Q.decreaseKey(v, alt)

Path reconstruction:
  P = []
  u = g
  while u is not null:
    P.prepend(u)
    u = prev[u]
```

**Complexity:** O((|V| + |E|) log |V|) with binary heap

**Optimizations:**

**Bidirectional Search:**
Run Dijkstra from both start and goal, stop when frontiers meet:
```
dist_forward[v] from start
dist_backward[v] from goal

Stop when: min_v{dist_forward[v] + dist_backward[v]} found
```

Speedup: ~2× for large graphs

**A* Enhancement:**
Use heuristic h(v) = straight-line distance to goal:
```
f(v) = dist[v] + h(v)

Priority queue ordered by f(v) instead of dist[v]
```

Speedup: 3-10× depending on graph structure

#### Goal Pose Validation

**Lanelet Matching:**

Find lanelets within search radius:
```
Candidates = {L | distance(goal_pose, L.centerline) < threshold}
```

**Heading Check:**

```
For each candidate L:
  θ_diff = |goal_pose.yaw - L.heading|
  if θ_diff < goal_angle_threshold:
    valid_candidates.add(L)
```

**Footprint Validation:**

If check_footprint_inside_lanes enabled:

```
For each valid candidate L:
  1. Create vehicle footprint F at goal_pose
  2. Check if F ⊂ L.polygon:
     For each vertex v of F:
       if v not inside L.polygon:
         reject L
```

Vehicle footprint (rectangle):
```
F = {(x, y) | |x - x_goal| ≤ length/2, 
              |y - y_goal| ≤ width/2}
Rotated by goal_pose.yaw
```

Point-in-polygon test: Ray casting algorithm O(n) where n = polygon vertices

**Closest Valid Lanelet:**

```
L_goal = argmin_{L ∈ valid_candidates} distance(goal_pose, L.centerline)
```

#### Route Section Creation

After path finding, segment route into sections:

**Section Types:**

1. **Normal**: Standard lane following
2. **Lane Change**: Left/right lane change maneuver
3. **Intersection**: Turn or crossing
4. **Goal**: Final approach to goal

**Algorithm:**

```
current_section = []
sections = []

for i in range(len(Path) - 1):
  L_curr = Path[i]
  L_next = Path[i+1]
  
  transition = getTransitionType(L_curr, L_next)
  
  if transition == current_section.type:
    current_section.lanelets.append(L_next)
  else:
    sections.append(current_section)
    current_section = Section(type=transition, lanelets=[L_next])

sections.append(current_section)
```

**Preferred Lanes:**

For each section, identify preferred lane:
```
For lane_following sections:
  preferred = rightmost_lane (default, can be configurable)

For lane_change sections:
  preferred = target_lane
```

#### Rerouting Logic

**Trigger Conditions:**

1. **Blocked Route**: Current path obstructed
2. **Route Deviation**: Vehicle far from planned route
3. **Better Route**: Shorter path discovered
4. **User Request**: Explicit reroute command

**Reroute Decision:**

```
if time_since_last_reroute < reroute_time_threshold:
  reject  // too soon

new_route = ComputeRoute(current_pose, goal)

if length_difference(new_route, old_route) < minimum_reroute_length:
  reject  // not significantly different

if allow_reroute_in_autonomous_mode or in_manual_mode:
  accept new_route
else:
  reject
```

### Complexity

**Time Complexity:**

**Dijkstra's Algorithm:**
- Priority queue operations: O(log V) each
- Each vertex extracted once: O(V log V)
- Each edge relaxed once: O(E log V)
- **Total**: O((V + E) log V)

For typical urban map:
- V ≈ 1000-10,000 lanelets
- E ≈ 3V (each lanelet has ~3 outgoing edges)
- Complexity: O(4V log V) ≈ O(10,000 × 13) = 130K operations

**With A* heuristic:**
- Reduces explored nodes significantly
- Typical: explores 10-30% of graph
- Effective: O(0.3V log V) ≈ 40K operations

**Goal Validation:**
- Lanelet search: O(L) where L = lanelets in search radius (10-50)
- Heading check: O(L)
- Footprint validation: O(L · P)
  - P = polygon vertices per lanelet (~20)
- **Total**: O(L · P) ≈ O(50 × 20) = 1K operations

**Route Section Creation:**
- Single pass through path: O(N)
- N = path length in lanelets (typically 10-200)

**Total Planning Time:**
```
T_total = O((V + E) log V + L·P + N)
        ≈ O(V log V) dominated by Dijkstra
```

**Practical Latency:**
- Small route (<1km): 1-5 ms
- Medium route (1-5km): 5-20 ms
- Large route (>5km): 20-100 ms

**Space Complexity:**

**Graph Storage:**
- Vertices: O(V × metadata)
  - Per lanelet: ~500 bytes (geometry, rules, attributes)
  - Total: V × 500 bytes
- Edges: O(E × 16) bytes (from, to, cost, type)

**Dijkstra State:**
- dist array: O(V × 8) bytes (double per vertex)
- prev array: O(V × 8) bytes (pointer per vertex)
- Priority queue: O(V × 16) bytes

**Total:**
```
Memory = V × (500 + 8 + 8 + 16) + E × 16
       ≈ V × 532 + E × 16 bytes
```

For V = 10K, E = 30K:
```
= 10K × 532 + 30K × 16
= 5.3 MB + 0.5 MB
= 5.8 MB
```

**Route Storage:**
- Path lanelets: O(N × 8) bytes (pointers)
- Typical: 100 lanelets × 8 = 800 bytes (negligible)

**Performance Bottlenecks:**

1. **Large Maps**:
   - City-scale maps: 50K+ lanelets
   - Dijkstra scales as O(V log V)
   - Mitigation: A* heuristic, hierarchical planning, spatial partitioning

2. **Priority Queue Operations**:
   - Heap operations dominate for dense graphs
   - Cache misses for pointer-heavy data structures
   - Mitigation: D-ary heap (d=4), array-based heap

3. **Goal Pose Lookup**:
   - Linear search through nearby lanelets
   - Repeated for validation checks
   - Mitigation: Spatial index (R-tree, grid), cache last goal lanelet

4. **Rerouting Frequency**:
   - Full replanning is expensive
   - Unnecessary if route still valid
   - Mitigation: Route validation before replanning, incremental updates

5. **Graph Traversal Cache Misses**:
   - Random memory access for edge following
   - Poor spatial locality
   - Mitigation: Breadth-first layout, edge list optimization

**Parameter Trade-offs:**

- **`arrival_check_distance`**:
  - Small (0.5m): Precise goal, may oscillate if goal unreachable
  - Large (2.0m): Early goal declaration, potential undershooting
  - Optimal: 1.0m matches typical vehicle control accuracy

- **`arrival_check_angle_deg`**:
  - Small (20°): Requires precise final orientation
  - Large (60°): Lenient, suitable for parking or stopping
  - Optimal: 45° balances precision and reachability

- **`check_footprint_inside_lanes`**:
  - Critical for safety: prevents goals in obstacles
  - Adds 1-2ms but avoids planning failures
  - Should be enabled in production

- **`goal_angle_threshold_deg`**:
  - Should match arrival_check_angle_deg for consistency
  - Too strict: rejects valid goals
  - Too loose: accepts infeasible orientations

- **`consider_no_drivable_lanes`**:
  - Disabled: Faster, follows traffic rules strictly
  - Enabled: Slower, allows emergency maneuvers (shoulder driving)
  - Optimal: Disable for normal operation, enable for recovery

- **`reroute_time_threshold`**:
  - Short (5s): Responsive to changes, frequent replanning overhead
  - Long (20s): Stable routes, slow adaptation to blockages
  - Optimal: 10s balances stability and responsiveness

- **`minimum_reroute_length`**:
  - Prevents minor route oscillations
  - Should be 2-3× typical vehicle motion during reroute_time_threshold
  - 30m optimal for 10s threshold at urban speeds

## Summary

The Mission Planner computes optimal global routes from current position to goal using Dijkstra's algorithm on the Lanelet2 routing graph. It validates goal reachability, segments routes into functional sections (lane following, lane changes, intersections), and supports dynamic rerouting, providing the high-level path guidance essential for autonomous navigation while respecting map topology and traffic rules.

