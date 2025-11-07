# Perf Commands Examples for Autoware Node Profiling

This document provides practical `perf stat` command examples optimized for the Jetson Orin AGX's 6 hardware counters per core limitation. All examples focus on architecture-agnostic metrics suitable for algorithm comparison across different platforms.

---

## Command Group 1: Algorithm Efficiency Baseline

### Command
```bash
perf stat -e instructions,cpu-clock,task-clock,branch-misses,branches,cache-misses \
  ./ndt_scan_matcher
```

### Purpose
Establishes fundamental algorithm efficiency metrics. This is the first command to run for any node - it tells you how much work the algorithm does (instructions), how long it takes (time), control flow predictability (branch behavior), and memory efficiency (cache misses).

### What This Measures
- **instructions**: Total computational work - direct measure of algorithm complexity
- **cpu-clock** / **task-clock**: Execution time (redundant but useful for validation)
- **branch-misses** / **branches**: Control flow predictability (miss rate = misses/branches)
- **cache-misses**: Memory efficiency - expensive misses to main memory

### Expected Output
```
Performance counter stats for './ndt_scan_matcher':

    10,234,567,890      instructions
            45.678 ms   cpu-clock
            45.654 ms   task-clock
            12,345      branch-misses
         1,234,567      branches
            45,678      cache-misses

       0.045678 seconds time elapsed
```

### Interpretation
- **Instructions per point**: 10.2B instructions / 100K points = 102K instructions/point
  - Compare across localization algorithms: NDT vs ICP vs Monte Carlo
  - Lower is better for same accuracy
  
- **Execution rate**: 10.2B instructions / 45.7ms = 223 GIPS (billion instructions per second)
  - Indicates CPU utilization efficiency
  - Lower than peak suggests memory/stall bottlenecks
  
- **Branch miss rate**: 12,345 / 1,234,567 = 1.0%
  - Excellent - predictable iteration over voxels
  - >5% would indicate unpredictable control flow
  
- **MPKI** (Misses Per Kilo-Instruction): 45,678 / 10,234,567 = 4.46 MPKI
  - Moderate - voxel hash table lookups cause misses
  - <1 MPKI is excellent, >10 MPKI indicates memory-bound

**Use Case**: Run this first on every node to establish performance baseline and identify if node is compute-bound (low MPKI, high GIPS) or memory-bound (high MPKI, low GIPS).

---

## Command Group 2: Detailed Cache Hierarchy Analysis

### Command
```bash
perf stat -e L1-dcache-load-misses,L1-dcache-loads,cache-references,cache-misses,LLC-loads,LLC-load-misses \
  ./lidar_centerpoint
```

### Purpose
Analyzes memory access patterns through the cache hierarchy. Critical for understanding memory bottlenecks in data-intensive algorithms like neural network inference, point cloud processing, and occupancy grid operations.

### What This Measures
- **L1-dcache-load-misses** / **L1-dcache-loads**: L1 data cache hit rate
- **cache-references** / **cache-misses**: Last-level cache (LLC) hit rate
- **LLC-loads** / **LLC-load-misses**: LLC behavior (redundant with cache-*, but useful validation)

### Expected Output
```
Performance counter stats for './lidar_centerpoint':

         3,456,789      L1-dcache-load-misses
        45,678,901      L1-dcache-loads
           234,567      cache-references
            89,012      cache-misses
           234,500      LLC-loads
            88,999      LLC-load-misses

       0.080123 seconds time elapsed
```

### Interpretation
- **L1 hit rate**: (45,678,901 - 3,456,789) / 45,678,901 = 92.4%
  - Excellent - neural network inference has good data locality in L1
  - <90% suggests working set exceeds L1 capacity (typically 32-64KB)
  
- **LLC hit rate**: (234,567 - 89,012) / 234,567 = 62.1%
  - Moderate - working set (network weights) spans L2/L3/memory
  - <50% indicates severe memory pressure
  
- **LLC miss rate**: 89,012 / 234,567 = 37.9%
  - High - neural network weights don't fully fit in cache
  - Each LLC miss costs ~300 cycles (main memory access)
  - At 2 GHz: 89,012 misses × 300 cycles = 26.7M cycles = 13.4ms spent waiting for memory

**Cache Miss Cost Estimation**:
```
Total memory latency = LLC_misses × cycles_per_miss / CPU_frequency
                     = 89,012 × 300 / (2×10⁹) = 13.4ms
```

If total execution time is 80ms, then 13.4/80 = 16.8% of time waiting for memory.

**Use Case**: Essential for memory-intensive nodes (CenterPoint, NDT, Occupancy Grid, Clustering). Identifies whether optimizations should focus on cache locality or are memory-bandwidth limited.

---

## Command Group 3: Memory Access Pattern Characterization

### Command
```bash
perf stat -e L1-dcache-loads,dTLB-loads,dTLB-load-misses,page-faults,minor-faults,major-faults \
  ./occupancy_grid_map
```

### Purpose
Characterizes memory access patterns focusing on TLB behavior and page faults. TLB misses indicate scattered access across many pages. Page faults indicate memory management overhead. Critical for algorithms with large working sets or random access patterns.

### What This Measures
- **L1-dcache-loads**: Data access intensity
- **dTLB-loads** / **dTLB-load-misses**: Virtual memory translation efficiency
- **page-faults**: Memory management overhead
- **minor-faults** / **major-faults**: Cheap vs. expensive page faults

### Expected Output
```
Performance counter stats for './occupancy_grid_map':

        23,456,789      L1-dcache-loads
        23,450,123      dTLB-loads
             8,901      dTLB-load-misses
             1,234      page-faults
             1,234      minor-faults
                 0      major-faults

       0.025123 seconds time elapsed
```

### Interpretation
- **TLB hit rate**: (23,450,123 - 8,901) / 23,450,123 = 99.96%
  - Excellent - raycasting has good page locality
  - <99% indicates accessing data scattered across many pages
  
- **TLB efficiency**: dTLB-loads ≈ L1-dcache-loads
  - Normal - one TLB lookup per memory access
  - If dTLB-loads >> L1-dcache-loads, indicates TLB pressure
  
- **Page fault analysis**:
  - 1,234 page-faults, all minor, zero major
  - Minor faults are acceptable (page in RAM but not mapped)
  - Major faults (disk I/O) are catastrophic for real-time systems
  - Zero major faults is mandatory for autonomous driving

**TLB Miss Cost**:
- Each TLB miss requires page table walk: ~10-100 cycles
- 8,901 misses × 50 cycles (average) = 445K cycles = 0.22ms at 2 GHz
- Negligible compared to total execution time

**Use Case**: Important for nodes with large memory footprints (point cloud processing, map loading, prediction with many hypotheses). Ensures memory access patterns don't thrash TLB or cause disk paging.

---

## Command Group 4: System Overhead and Real-Time Performance

### Command
```bash
perf stat -e context-switches,cpu-migrations,cpu-clock,duration_time,alignment-faults,emulation-faults \
  ./trajectory_follower_controller
```

### Purpose
Measures system overhead and real-time performance metrics. Critical for control nodes that must meet hard real-time deadlines. Excessive context switches or migrations indicate scheduling problems. Alignment/emulation faults indicate code quality issues.

### What This Measures
- **context-switches**: Thread context switch overhead
- **cpu-migrations**: Thread migration between cores
- **cpu-clock** / **duration_time**: CPU utilization (cpu/duration ratio)
- **alignment-faults** / **emulation-faults**: Code quality issues

### Expected Output
```
Performance counter stats for './trajectory_follower_controller':

                45      context-switches
                 2      cpu-migrations
            14.234 ms   cpu-clock
            15.678 ms   duration_time
                 0      alignment-faults
                 0      emulation-faults

       0.015678 seconds time elapsed
```

### Interpretation
- **Context switch rate**: 45 switches / 15.678ms = 2.87 switches/ms
  - Low - acceptable for 10 Hz control loop (100ms period)
  - >10 switches/ms indicates scheduling problems or excessive threading
  
- **CPU migrations**: 2 migrations
  - Very low - good, thread stays on same core
  - High migrations cause cache thrashing
  - For real-time nodes, should pin threads to cores (taskset command)
  
- **CPU utilization**: 14.234 / 15.678 = 90.8%
  - High - mostly compute, minimal blocking
  - <50% suggests excessive sleeping, blocking on I/O, or synchronization
  - >95% is excellent for CPU-bound tasks
  
- **Code quality**: 0 alignment faults, 0 emulation faults
  - Perfect - well-written code with proper data alignment
  - Non-zero indicates serious code quality issues

**Real-Time Analysis**:
- Execution time: 15.678ms
- For 10 Hz control loop: 100ms budget, using 15.7% - excellent headroom
- For 50 Hz control loop: 20ms budget, using 78% - tight but acceptable
- Context switches add ~1-10μs each: 45 × 5μs = 0.225ms overhead = 1.4% of time

**Use Case**: Mandatory for all real-time control and safety-critical nodes (MPC controller, AEB, EKF). Ensures timing determinism and identifies scheduling issues.

---

## Command Group 5: Branch Prediction and Control Flow

### Command
```bash
perf stat -e branches,branch-misses,branch-loads,branch-load-misses,instructions,cpu-clock \
  ./multi_object_tracker
```

### Purpose
Focuses on branch prediction performance and control flow complexity. High branch miss rates indicate unpredictable branching (data-dependent decisions, complex state machines). Important for algorithms with heavy conditional logic.

### What This Measures
- **branches** / **branch-misses**: Branch prediction accuracy
- **branch-loads** / **branch-load-misses**: Branch target buffer (BTB) efficiency
- **instructions** / **cpu-clock**: Instructions per second (context)

### Expected Output
```
Performance counter stats for './multi_object_tracker':

         1,234,567      branches
            12,345      branch-misses
         1,234,500      branch-loads
               123      branch-load-misses
        10,234,567      instructions
            25.456 ms   cpu-clock

       0.025456 seconds time elapsed
```

### Interpretation
- **Branch miss rate**: 12,345 / 1,234,567 = 1.0%
  - Excellent - state machine transitions are predictable
  - <2%: excellent, >5%: poor, >10%: severe control flow issues
  
- **Branch density**: 1,234,567 / 10,234,567 = 12.1%
  - Moderate - typical for object-oriented C++ with function calls
  - <5%: straight-line code, >20%: heavy branching
  
- **BTB miss rate**: 123 / 1,234,500 = 0.01%
  - Excellent - branch targets (function addresses) are predictable
  - High BTB misses indicate indirect calls (virtual functions, function pointers)

**Branch Prediction Cost**:
- Each branch misprediction: ~10-20 cycle penalty (pipeline flush)
- 12,345 misses × 15 cycles = 185K cycles = 0.09ms at 2 GHz
- 0.09 / 25.456 = 0.4% of execution time lost to branch mispredictions
- Negligible impact

**Use Case**: Important for nodes with state machines (tracking, behavior planning), complex decision trees (prediction, collision detection), or heavy conditional logic (planning validators).

---

## Command Group 6: Instruction Cache and Code Locality

### Command
```bash
perf stat -e L1-icache-loads,L1-icache-load-misses,iTLB-loads,iTLB-load-misses,instructions,branches \
  ./behavior_path_planner
```

### Purpose
Analyzes instruction fetch efficiency and code locality. Important for large codebases, heavily templated C++, or modular architectures with many functions. High I-cache or iTLB misses indicate code size issues.

### What This Measures
- **L1-icache-loads** / **L1-icache-load-misses**: Instruction cache hit rate
- **iTLB-loads** / **iTLB-load-misses**: Instruction TLB hit rate (code page locality)
- **instructions** / **branches**: Code execution characteristics

### Expected Output
```
Performance counter stats for './behavior_path_planner':

         5,678,901      L1-icache-loads
             2,345      L1-icache-load-misses
         1,234,567      iTLB-loads
               123      iTLB-load-misses
        20,000,000      instructions
         3,456,789      branches

       0.050123 seconds time elapsed
```

### Interpretation
- **I-cache hit rate**: (5,678,901 - 2,345) / 5,678,901 = 99.96%
  - Excellent - code has tight loops, good locality
  - <99% suggests large code footprint, many distant function calls
  
- **iTLB hit rate**: (1,234,567 - 123) / 1,234,567 = 99.99%
  - Excellent - code fits in reasonable number of pages
  - <99% indicates code spread across many pages
  
- **I-cache efficiency**: L1-icache-loads / instructions = 5.7M / 20M = 28.4%
  - Normal - some instructions reused from cache
  - 100% would mean every instruction is a cache miss (impossible)
  - Low percentage indicates good loop structure

**I-cache Miss Cost**:
- Each I-cache miss: ~10-50 cycles to fetch from L2
- 2,345 misses × 30 cycles = 70K cycles = 0.035ms at 2 GHz
- Negligible impact

**Use Case**: Relevant for large modular systems (behavior path planner with scene modules), template-heavy C++, or when profiling shows frontend stalls. Helps identify if code size optimization is needed.

---

## Command Group 7: Comprehensive Memory Profiling

### Command
```bash
perf stat -e cache-references,cache-misses,L1-dcache-load-misses,dTLB-load-misses,page-faults,instructions \
  ./map_based_prediction
```

### Purpose
Comprehensive memory subsystem profiling combining cache, TLB, and virtual memory metrics. Provides complete picture of memory behavior. Useful when you suspect memory issues but aren't sure at which level.

### What This Measures
- **cache-references** / **cache-misses**: LLC behavior
- **L1-dcache-load-misses**: L1 data cache behavior
- **dTLB-load-misses**: Virtual memory translation issues
- **page-faults**: Memory management overhead
- **instructions**: For normalization (MPKI calculation)

### Expected Output
```
Performance counter stats for './map_based_prediction':

           123,456      cache-references
            12,345      cache-misses
           234,567      L1-dcache-load-misses
             1,234      dTLB-load-misses
               456      page-faults
        50,000,000      instructions

       0.030456 seconds time elapsed
```

### Interpretation
- **LLC hit rate**: (123,456 - 12,345) / 123,456 = 90.0%
  - Good - path generation data fits mostly in cache
  
- **L1 MPKI**: 234,567 / 50,000 = 4.69 MPKI
  - Moderate - typical for data structures with pointers
  
- **LLC MPKI**: 12,345 / 50,000 = 0.25 MPKI
  - Excellent - very few expensive memory accesses
  
- **Memory hierarchy pressure** (L1 miss → LLC miss ratio):
  - 234,567 L1 misses but only 12,345 LLC misses
  - L2 cache captures 94.7% of L1 misses
  - Indicates working set fits in L2 (typically 512KB-4MB)

**Memory Bottleneck Severity**:
1. **L1-only pressure**: Many L1 misses, few LLC misses → Optimize for L1 (hot data paths)
2. **L2 pressure**: Many L1 misses, moderate LLC misses → Working set spans L1/L2
3. **LLC pressure**: High LLC miss rate → Working set exceeds all caches, memory-bound

**Use Case**: First-line memory profiling for any data-intensive node. Quickly identifies which level of cache hierarchy is the bottleneck.

---

## Command Group 8: Algorithm Computational Intensity

### Command
```bash
perf stat -e instructions,L1-dcache-loads,branches,cache-misses,task-clock,duration_time \
  ./velocity_smoother
```

### Purpose
Characterizes algorithm computational intensity - the ratio of computation to memory operations. Helps classify whether algorithm is compute-bound (many instructions per memory access) or memory-bound (many memory accesses per instruction).

### What This Measures
- **instructions**: Total computational work
- **L1-dcache-loads**: Memory read operations
- **branches**: Control flow operations
- **cache-misses**: Expensive memory operations
- **task-clock** / **duration_time**: Execution time and utilization

### Expected Output
```
Performance counter stats for './velocity_smoother':

        50,000,000      instructions
         5,000,000      L1-dcache-loads
         8,000,000      branches
             1,234      cache-misses
            12.345 ms   task-clock
            13.456 ms   duration_time

       0.013456 seconds time elapsed
```

### Interpretation
- **Instructions per memory operation**: 50M / 5M = 10 instructions/load
  - High computational intensity - compute-bound
  - <2: memory-bound, >5: compute-bound, >20: highly compute-bound
  
- **Instructions per branch**: 50M / 8M = 6.25 instructions/branch
  - Moderate - mix of computation and control flow
  - <3: control-flow heavy, >10: straight-line computation
  
- **Compute rate**: 50M instructions / 12.345ms = 4.05 GIPS
  - At 2 GHz CPU: theoretical max ~4-8 GIPS (IPC 2-4)
  - Achieving 4 GIPS suggests good CPU utilization
  
- **CPU utilization**: 12.345 / 13.456 = 91.7%
  - High - algorithm is CPU-bound, not waiting for I/O

**Algorithm Classification**:
1. **Compute-bound** (>5 inst/load, <1 MPKI): QP solver, matrix operations
   - Optimization: Improve algorithms, use SIMD, reduce instruction count
   
2. **Memory-bound** (<3 inst/load, >10 MPKI): Random access, pointer-chasing
   - Optimization: Improve cache locality, reduce working set, prefetch
   
3. **Control-flow bound** (>5% branch miss rate): Complex state machines
   - Optimization: Reduce branching, use branchless techniques, predicatable patterns

**Use Case**: Essential for understanding optimization direction. No point optimizing code if you're memory-bound, no point improving cache locality if you're compute-bound.

---

## Command Group 9: Minimal Overhead Quick Check

### Command
```bash
perf stat -e instructions,task-clock,cache-misses,branch-misses \
  ./any_node
```

### Purpose
Minimal 4-counter quick check for rapid profiling. Provides core metrics with minimal overhead. Use when you need quick feedback during iterative optimization or when profiling time-sensitive code.

### What This Measures
- **instructions**: Computational work
- **task-clock**: Execution time
- **cache-misses**: Memory efficiency
- **branch-misses**: Control flow predictability

### Expected Output
```
Performance counter stats for './any_node':

        10,234,567      instructions
            15.678 ms   task-clock
            12,345      cache-misses
             5,678      branch-misses

       0.015678 seconds time elapsed
```

### Interpretation
- **GIPS**: 10.2M / 15.678ms = 652 MIPS
- **MPKI**: 12,345 / 10,234 = 1.21 MPKI - excellent
- **Branch miss ratio**: 5,678 / ? (need branches count for rate)
- Quick assessment: Low MPKI suggests compute-bound, optimize algorithms

**Use Case**: Rapid iteration during optimization. Run this between code changes to quickly see if performance improved. Only 4 counters so minimal profiling overhead.

---

## Command Group 10: Complete Algorithm Profile

### Command
```bash
perf stat -e instructions,branches,cache-misses,L1-dcache-load-misses,page-faults,task-clock \
  ./mission_planner
```

### Purpose
Balanced profile covering computation (instructions), control flow (branches), memory hierarchy (caches), virtual memory (page faults), and time. Best all-around profile when you don't know what the bottleneck is.

### What This Measures
- **instructions**: Computational complexity
- **branches**: Control flow complexity
- **cache-misses**: LLC memory efficiency
- **L1-dcache-load-misses**: L1 memory efficiency
- **page-faults**: Virtual memory overhead
- **task-clock**: Execution time

### Expected Output
```
Performance counter stats for './mission_planner':

        30,000,000      instructions
         5,000,000      branches
             2,345      cache-misses
            45,678      L1-dcache-load-misses
               123      page-faults
             8.901 ms   task-clock

       0.008901 seconds time elapsed
```

### Interpretation
- **Algorithm complexity**: 30M instructions for route planning
- **Branch density**: 5M / 30M = 16.7% - typical for graph algorithms
- **LLC MPKI**: 2,345 / 30,000 = 0.078 - excellent
- **L1 MPKI**: 45,678 / 30,000 = 1.52 - excellent
- **Page faults**: 123 - all minor, acceptable
- **Performance**: 30M / 8.9ms = 3.37 GIPS - good

**Overall Assessment**:
- Low MPKI at all levels → Not memory-bound
- High GIPS → Good CPU utilization
- Low branch miss ratio (need branches count to verify)
- 123 page faults might be improvable with preallocation
- Algorithm is efficient, Dijkstra implementation is well-optimized

**Use Case**: Default comprehensive profile for any node. Covers all major performance aspects. Run this first if you don't know what to profile.

---

## Best Practices

### Counter Selection Strategy

1. **Always include**: `instructions` and `task-clock`
   - These provide normalization baseline and execution time
   
2. **Choose primary focus**: Based on suspected bottleneck
   - Memory: cache-*, TLB-*
   - Control flow: branch-*
   - System: context-switches, page-faults
   
3. **Fill remaining slots**: With related metrics
   - If measuring cache-misses, also measure cache-references
   - If measuring branch-misses, also measure branches
   
4. **Stay within 6 counters**: Hardware limitation on Jetson Orin AGX
   - More than 6 requires multiplexing (less accurate)

### Profiling Workflow

1. **Baseline** (Group 1): Establish basic performance
2. **Identify bottleneck**: Low GIPS → memory-bound, High GIPS → compute-bound
3. **Deep dive**: Run specific group based on bottleneck type
4. **Optimize**: Make code changes
5. **Validate**: Re-run baseline to measure improvement

### Interpretation Guidelines

- **MPKI** < 1: Excellent cache behavior
- **MPKI** 1-5: Acceptable, room for improvement
- **MPKI** 5-10: Poor, significant memory bottleneck
- **MPKI** > 10: Severe, memory-bound

- **Branch miss rate** < 2%: Excellent prediction
- **Branch miss rate** 2-5%: Acceptable
- **Branch miss rate** > 5%: Poor, unpredictable control flow

- **GIPS** approaching theoretical max (2-8 GIPS on 2 GHz CPU): Compute-bound
- **GIPS** well below theoretical max: Memory or I/O bound

### Platform Portability

All commands in this document use architecture-agnostic metrics. Results can be compared across:
- Different ARM processors (Cortex-A57, A72, A78, etc.)
- Different architectures (x86, ARM, RISC-V)
- Different platforms (Jetson, server, desktop)

The metrics measure algorithmic properties, not hardware-specific features, enabling fair algorithm comparison across platforms.

---

## Summary

These 10 command groups provide comprehensive, architecture-agnostic profiling for Autoware nodes:

1. **Baseline efficiency**: Instructions, time, branches, cache
2. **Cache hierarchy**: L1/LLC miss rates
3. **Memory patterns**: TLB, page faults
4. **Real-time performance**: Context switches, migrations
5. **Control flow**: Branch prediction
6. **Code locality**: I-cache, iTLB
7. **Memory comprehensive**: Combined memory metrics
8. **Computational intensity**: Compute vs. memory ratio
9. **Quick check**: Minimal overhead
10. **Complete profile**: Balanced all-around

Use these commands to profile Autoware nodes, identify bottlenecks, guide optimizations, and compare algorithms objectively across platforms.

