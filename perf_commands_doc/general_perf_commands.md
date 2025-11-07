# Architecture-Specific Perf Commands

These performance counters are tied to specific hardware implementations - primarily ARM Cortex-A78 CPU and the Jetson Orin AGX platform. These metrics expose microarchitectural details like pipeline structure, cache implementation, and platform-specific features. Values and interpretations are hardware-dependent.

---

## General Hardware Events

### cpu-cycles (or cycles)

**Explanation**: Counts the total number of CPU clock cycles elapsed during execution. This is hardware-dependent because different CPUs run at different frequencies (GHz). CPU cycles alone don't indicate efficiency - a slow algorithm on a fast CPU might use more cycles than an efficient algorithm on a slow CPU. Use with `instructions` to calculate IPC (Instructions Per Cycle), which is more meaningful. Modern CPUs also have dynamic frequency scaling, so cycle counts vary with clock speed.

**Commonly Used With**:
- `instructions` - To calculate IPC (instructions / cycles)
- `task-clock` - To determine average CPU frequency
- `stalled-cycles-frontend` / `stalled-cycles-backend` - To see where cycles are wasted

**Example**:
```bash
perf stat -e cpu-cycles,instructions,task-clock ./ndt_scan_matcher

# Output interpretation:
# 5,000,000,000 cpu-cycles
# 10,000,000,000 instructions
# IPC: 2.0 - excellent instruction-level parallelism
# At 50ms task-clock: 100 GHz equivalent (likely 2 GHz × 50ms with superscalar execution)
```

---

### bus-cycles

**Explanation**: Counts cycles spent on the system bus. This is highly platform-specific, measuring interactions between CPU and other system components (memory controller, I/O devices). High bus-cycles relative to cpu-cycles indicates the CPU is frequently waiting for external data. This metric is specific to the bus architecture and interconnect design.

**Commonly Used With**:
- `cpu-cycles` - To calculate bus utilization ratio
- `cache-misses` - Bus cycles often correlate with cache misses
- `mem_access` (ARM-specific) - To understand memory subsystem pressure

**Example**:
```bash
perf stat -e bus-cycles,cpu-cycles,cache-misses ./lidar_centerpoint

# Output interpretation:
# 1,000,000,000 bus-cycles
# 5,000,000,000 cpu-cycles
# 20% of cycles on bus - memory-intensive neural network inference
```

---

### stalled-cycles-frontend (or idle-cycles-frontend)

**Explanation**: Counts cycles where the CPU frontend (instruction fetch/decode) was stalled - no new instructions entering the pipeline. Frontend stalls occur due to instruction cache misses, branch mispredictions, or complex instruction decoding. This is microarchitecture-specific: different CPUs have different frontend designs. High frontend stalls indicate instruction supply problems.

**Commonly Used With**:
- `cpu-cycles` - To calculate frontend stall rate
- `L1-icache-load-misses` - Frontend stalls often due to I-cache misses
- `branch-misses` - Branch mispredictions cause frontend stalls
- `stalled-cycles-backend` - To see if frontend or backend dominates

**Example**:
```bash
perf stat -e stalled-cycles-frontend,cpu-cycles,L1-icache-load-misses ./behavior_path_planner

# Output interpretation:
# 500,000,000 stalled-cycles-frontend
# 5,000,000,000 cpu-cycles
# 10% frontend stall - acceptable, mostly due to branch mispredictions
```

---

### stalled-cycles-backend (or idle-cycles-backend)

**Explanation**: Counts cycles where the CPU backend (execution units) was stalled - instructions decoded but waiting to execute. Backend stalls occur due to data dependencies, cache misses, or resource conflicts (all ALUs busy). This is microarchitecture-specific to pipeline design. High backend stalls indicate data supply problems or insufficient execution resources.

**Commonly Used With**:
- `cpu-cycles` - To calculate backend stall rate
- `cache-misses` - Backend stalls often due to cache misses
- `L1-dcache-load-misses` - Data cache misses cause backend stalls
- `stalled-cycles-frontend` - To identify dominant bottleneck

**Example**:
```bash
perf stat -e stalled-cycles-backend,cpu-cycles,cache-misses ./occupancy_grid_map

# Output interpretation:
# 2,000,000,000 stalled-cycles-backend
# 5,000,000,000 cpu-cycles
# 40% backend stall - memory-bound, raycasting causes many cache misses
```

---

## ARM Cortex-A78 PMU Events

### br_mis_pred

**Explanation**: ARM Cortex-A78 specific count of branch mispredictions. This is the same concept as generic `branch-misses` but uses the ARM PMU counter directly. Specific to Cortex-A78's branch predictor implementation (TAGE-based predictor). Useful for ARM-specific optimization but conceptually similar to architecture-agnostic branch-misses.

**Commonly Used With**:
- `br_pred` - To calculate prediction accuracy
- `br_retired` - To calculate misprediction rate
- Generic `branch-misses` - Should give similar values

**Example**:
```bash
perf stat -e armv8_cortex_a78/br_mis_pred/,armv8_cortex_a78/br_retired/ ./multi_object_tracker

# Output interpretation:
# 12,345 br_mis_pred
# 1,234,567 br_retired
# 1.0% misprediction rate - excellent for state machine code
```

---

### br_mis_pred_retired

**Explanation**: ARM Cortex-A78 specific count of mispredicted branches that actually retired (completed). Slightly different from `br_mis_pred` which counts all mispredictions including speculative ones. This gives a more accurate picture of mispredictions that actually affected execution. Specific to ARM's speculative execution model.

**Commonly Used With**:
- `br_mis_pred` - To see speculative vs. committed mispredictions
- `br_retired` - To calculate retired misprediction rate
- `inst_retired` - To correlate with instruction retirement

**Example**:
```bash
perf stat -e armv8_cortex_a78/br_mis_pred_retired/,armv8_cortex_a78/br_retired/ ./mission_planner

# Output interpretation:
# 5,678 br_mis_pred_retired
# 234,567 br_retired
# 2.4% - slightly higher than typical due to graph traversal patterns
```

---

### br_pred

**Explanation**: ARM Cortex-A78 count of predicted branches (branches where prediction occurred, regardless of accuracy). Not all branches are predicted - some are always taken or never taken. This metric shows how many branches engaged the predictor. ARM-specific insight into branch predictor utilization.

**Commonly Used With**:
- `br_mis_pred` - To calculate prediction accuracy (mis_pred / pred)
- `br_retired` - To see what fraction of branches are predicted
- `br_immed_retired` - To see direct vs. indirect branches

**Example**:
```bash
perf stat -e armv8_cortex_a78/br_pred/,armv8_cortex_a78/br_retired/ ./velocity_smoother

# Output interpretation:
# 123,456 br_pred
# 134,567 br_retired  
# 92% of branches predicted - some unconditional branches not predicted
```

---

### br_retired

**Explanation**: ARM Cortex-A78 count of branch instructions that completed (retired). Equivalent to generic `branches` or `branch-loads` but from ARM's PMU. Counts all branch types: conditional, unconditional, calls, returns. ARM-specific but conceptually similar to architecture-agnostic branch counting.

**Commonly Used With**:
- `br_mis_pred` - To calculate misprediction rate
- `inst_retired` - To calculate branch density
- Generic `branches` - Should match this value

**Example**:
```bash
perf stat -e armv8_cortex_a78/br_retired/,armv8_cortex_a78/inst_retired/ ./shape_estimation

# Output interpretation:
# 234,567 br_retired
# 1,234,567 inst_retired
# 19% branch density - typical for C++ code with many function calls
```

---

### bus_access

**Explanation**: ARM Cortex-A78 count of bus accesses - transactions on the CPU's memory bus. Includes reads and writes to external memory or peripherals. Higher bus accesses indicate more off-chip traffic. Platform-specific to Jetson Orin's bus architecture. Useful for identifying memory bottlenecks.

**Commonly Used With**:
- `bus_cycles` - To understand bus utilization
- `mem_access` - Total memory operations
- `l3d_cache_refill` - L3 misses lead to bus accesses

**Example**:
```bash
perf stat -e armv8_cortex_a78/bus_access/,armv8_cortex_a78/mem_access/ ./pointcloud_concatenate_data

# Output interpretation:
# 45,678 bus_access
# 3,456,789 mem_access
# 1.3% of memory accesses go to bus - good cache hit rate
```

---

### bus_cycles

**Explanation**: ARM Cortex-A78 count of cycles spent on bus transactions. Similar to generic `bus-cycles` but ARM-specific counter. Indicates time waiting for bus operations to complete. High bus_cycles suggests memory bandwidth bottleneck or high external memory latency.

**Commonly Used With**:
- `cpu_cycles` - To calculate bus cycle ratio
- `bus_access` - To determine average cycles per bus access
- `stall_backend_mem` - Backend stalls due to memory/bus delays

**Example**:
```bash
perf stat -e armv8_cortex_a78/bus_cycles/,armv8_cortex_a78/cpu_cycles/ ./lidar_centerpoint

# Output interpretation:
# 800,000,000 bus_cycles
# 4,000,000,000 cpu_cycles
# 20% bus utilization - GPU tensor operations cause bus traffic
```

---

### cpu_cycles

**Explanation**: ARM Cortex-A78 count of CPU cycles. Equivalent to generic `cpu-cycles` but from ARM PMU counter. Use this when you want ARM-specific cycle counting rather than generic hardware counters. Useful for ARM-specific profiling tools and analysis.

**Commonly Used With**:
- `inst_retired` - To calculate IPC
- `stall` - To identify stall sources
- Generic `cpu-cycles` - Should match

**Example**:
```bash
perf stat -e armv8_cortex_a78/cpu_cycles/,armv8_cortex_a78/inst_retired/ ./ekf_localizer

# Output interpretation:
# 1,000,000,000 cpu_cycles
# 2,000,000,000 inst_retired
# IPC: 2.0 - efficient matrix operations
```

---

### dtlb_walk

**Explanation**: ARM Cortex-A78 count of data TLB hardware page table walks. When data TLB misses, the MMU performs a page table walk to find the translation. Page table walks are expensive (10-100 cycles). High dtlb_walk counts indicate poor TLB locality. ARM-specific measurement of TLB miss handling.

**Commonly Used With**:
- `l1d_tlb` - Total TLB accesses
- `l1d_tlb_refill` - L1 TLB refills
- Generic `dTLB-load-misses` - Conceptually similar

**Example**:
```bash
perf stat -e armv8_cortex_a78/dtlb_walk/,armv8_cortex_a78/l1d_tlb/ ./map_based_prediction

# Output interpretation:
# 1,234 dtlb_walk
# 3,456,789 l1d_tlb
# 0.036% TLB miss rate - excellent locality
```

---

### inst_retired

**Explanation**: ARM Cortex-A78 count of instructions retired (completed). Equivalent to generic `instructions` but from ARM PMU. This is the definitive instruction count on ARM processors. Use for ARM-specific analysis and when you need exact ARM instruction counting.

**Commonly Used With**:
- `cpu_cycles` - To calculate IPC
- `op_retired` - Micro-ops vs. instructions (if applicable)
- Generic `instructions` - Should match

**Example**:
```bash
perf stat -e armv8_cortex_a78/inst_retired/,armv8_cortex_a78/cpu_cycles/ ./autonomous_emergency_braking

# Output interpretation:
# 50,000,000 inst_retired
# 30,000,000 cpu_cycles
# IPC: 1.67 - good for control flow heavy code
```

---

### inst_spec

**Explanation**: ARM Cortex-A78 count of speculatively executed instructions. Modern CPUs speculatively execute instructions beyond branches. If the branch prediction was correct, these instructions commit. If wrong, they're discarded. High inst_spec relative to inst_retired indicates either high speculation or many mispredictions. ARM-specific insight into speculative execution.

**Commonly Used With**:
- `inst_retired` - Ratio shows speculation efficiency
- `br_mis_pred` - Mispredictions waste speculative work
- `op_spec` - Speculative micro-operations

**Example**:
```bash
perf stat -e armv8_cortex_a78/inst_spec/,armv8_cortex_a78/inst_retired/ ./multi_object_tracker

# Output interpretation:
# 110,000,000 inst_spec
# 100,000,000 inst_retired
# 10% speculation overhead - acceptable for branch-heavy tracking logic
```

---

### itlb_walk

**Explanation**: ARM Cortex-A78 count of instruction TLB hardware page table walks. When instruction TLB misses, the MMU walks the page table to find the translation. Instruction TLB walks indicate code spread across many pages. ARM-specific measurement of instruction TLB behavior.

**Commonly Used With**:
- `l1i_tlb` - Total instruction TLB accesses
- `l1i_tlb_refill` - Instruction TLB refills
- Generic `iTLB-load-misses` - Conceptually similar

**Example**:
```bash
perf stat -e armv8_cortex_a78/itlb_walk/,armv8_cortex_a78/l1i_tlb/ ./behavior_path_planner

# Output interpretation:
# 123 itlb_walk
# 123,456 l1i_tlb
# 0.1% iTLB miss rate - compact code footprint
```

---

### l1d_cache

**Explanation**: ARM Cortex-A78 count of L1 data cache accesses. Total number of L1D lookups for data reads and writes. High l1d_cache counts indicate data-intensive algorithms. ARM-specific L1 cache counter providing detailed cache access information.

**Commonly Used With**:
- `l1d_cache_refill` - To calculate L1D hit rate
- Generic `L1-dcache-loads` - Subset (only loads)
- `l1d_cache_wb` - Cache writebacks

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1d_cache/,armv8_cortex_a78/l1d_cache_refill/ ./euclidean_cluster

# Output interpretation:
# 5,000,000 l1d_cache
# 250,000 l1d_cache_refill
# 95% L1D hit rate - excellent for voxel grid clustering
```

---

### l1d_cache_refill

**Explanation**: ARM Cortex-A78 count of L1 data cache refills from L2. Each refill represents an L1D miss. Lower is better. High refill counts indicate working set exceeds L1D size or poor data locality. ARM-specific measurement of L1D miss behavior.

**Commonly Used With**:
- `l1d_cache` - To calculate miss rate
- Generic `L1-dcache-load-misses` - Similar concept
- `l2d_cache_refill` - L2 misses that cascade from L1 misses

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1d_cache_refill/,armv8_cortex_a78/l1d_cache/ ./shape_estimation

# Output interpretation:
# 340,000 l1d_cache_refill
# 5,000,000 l1d_cache
# 6.8% L1D miss rate - acceptable for PCA matrix operations
```

---

### l1d_cache_lmiss_rd

**Explanation**: ARM Cortex-A78 count of L1 data cache line misses on read operations. Specifically tracks read misses (not writes). ARM-specific detail separating read vs. write cache behavior. Useful for identifying whether read or write patterns cause cache issues.

**Commonly Used With**:
- `l1d_cache_refill` - Total L1D refills
- `l1d_cache` - To calculate read miss rate
- `l2d_cache_lmiss_rd` - Read miss propagation to L2

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1d_cache_lmiss_rd/,armv8_cortex_a78/l1d_cache/ ./ndt_scan_matcher

# Output interpretation:
# 200,000 l1d_cache_lmiss_rd
# 4,000,000 l1d_cache
# 5% read miss rate - voxel lookups have good locality
```

---

### l1d_cache_wb

**Explanation**: ARM Cortex-A78 count of L1 data cache writebacks to L2. Writebacks occur when dirty (modified) cache lines are evicted from L1D. High writeback counts indicate write-intensive algorithms or cache pressure forcing evictions. ARM-specific insight into write behavior.

**Commonly Used With**:
- `l1d_cache_refill` - Cache refills vs. writebacks
- `l1d_cache` - To understand write intensity
- `l2d_cache_wb` - Writeback propagation to L2

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1d_cache_wb/,armv8_cortex_a78/l1d_cache/ ./occupancy_grid_map

# Output interpretation:
# 150,000 l1d_cache_wb
# 3,000,000 l1d_cache
# 5% writeback rate - expected for grid update operations
```

---

### l1d_tlb

**Explanation**: ARM Cortex-A78 count of L1 data TLB accesses. Every data memory access requires TLB lookup. High counts indicate data access intensity. ARM-specific TLB counter. Essentially counts unique page accesses.

**Commonly Used With**:
- `l1d_tlb_refill` - To calculate TLB hit rate
- Generic `dTLB-loads` - Similar concept
- `dtlb_walk` - TLB miss handling

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1d_tlb/,armv8_cortex_a78/l1d_tlb_refill/ ./trajectory_follower_controller

# Output interpretation:
# 1,000,000 l1d_tlb
# 50 l1d_tlb_refill
# 0.005% TLB miss rate - excellent, small working set
```

---

### l1d_tlb_refill

**Explanation**: ARM Cortex-A78 count of L1 data TLB refills from L2 TLB or page table. TLB refills indicate accessing data across many memory pages. High refill counts suggest poor page locality. ARM-specific TLB miss measurement.

**Commonly Used With**:
- `l1d_tlb` - To calculate miss rate
- `dtlb_walk` - Page table walks after TLB miss
- Generic `dTLB-load-misses` - Similar concept

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1d_tlb_refill/,armv8_cortex_a78/dtlb_walk/ ./map_based_prediction

# Output interpretation:
# 500 l1d_tlb_refill
# 100 dtlb_walk
# Some refills from L2 TLB (not requiring page walk) - good
```

---

### l1i_cache

**Explanation**: ARM Cortex-A78 count of L1 instruction cache accesses. Total instruction fetches from L1I. High counts indicate large code or frequent instruction fetching. ARM-specific instruction cache monitoring.

**Commonly Used With**:
- `l1i_cache_refill` - To calculate L1I hit rate
- Generic `L1-icache-loads` - Similar
- `l1i_cache_lmiss` - L1I misses

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1i_cache/,armv8_cortex_a78/l1i_cache_refill/ ./mission_planner

# Output interpretation:
# 2,000,000 l1i_cache
# 1,000 l1i_cache_refill
# 99.95% L1I hit rate - excellent, tight Dijkstra loop
```

---

### l1i_cache_lmiss

**Explanation**: ARM Cortex-A78 count of L1 instruction cache line misses. Specifically tracks instruction cache misses at line granularity. ARM-specific detail for instruction cache behavior analysis.

**Commonly Used With**:
- `l1i_cache` - To calculate miss rate
- `l1i_cache_refill` - Related but slightly different counting
- Generic `L1-icache-load-misses` - Similar concept

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1i_cache_lmiss/,armv8_cortex_a78/l1i_cache/ ./velocity_smoother

# Output interpretation:
# 2,345 l1i_cache_lmiss
# 1,234,567 l1i_cache
# 0.19% miss rate - QP solver has good code locality
```

---

### l1i_cache_refill

**Explanation**: ARM Cortex-A78 count of L1 instruction cache refills from L2. Each refill is an L1I miss. High refills indicate large code footprint or poor instruction locality. ARM-specific L1I miss measurement.

**Commonly Used With**:
- `l1i_cache` - To calculate hit rate
- Generic `L1-icache-load-misses` - Similar
- `l2d_cache_refill` - Can compare instruction vs. data cache behavior

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1i_cache_refill/,armv8_cortex_a78/l1i_cache/ ./behavior_path_planner

# Output interpretation:
# 5,678 l1i_cache_refill
# 20,000,000 l1i_cache
# 0.028% miss rate - modular scene architecture but good locality
```

---

### l1i_tlb

**Explanation**: ARM Cortex-A78 count of L1 instruction TLB accesses. Every instruction fetch requires TLB lookup. High counts simply mean executing many instructions. ARM-specific instruction TLB monitoring.

**Commonly Used With**:
- `l1i_tlb_refill` - To calculate iTLB hit rate
- Generic `iTLB-loads` - Similar
- `itlb_walk` - iTLB miss handling

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1i_tlb/,armv8_cortex_a78/l1i_tlb_refill/ ./autonomous_emergency_braking

# Output interpretation:
# 500,000 l1i_tlb
# 50 l1i_tlb_refill
# 0.01% iTLB miss rate - compact safety-critical code
```

---

### l1i_tlb_refill

**Explanation**: ARM Cortex-A78 count of L1 instruction TLB refills. iTLB refills indicate code spread across many pages. High refills suggest large code footprint. ARM-specific iTLB miss measurement.

**Commonly Used With**:
- `l1i_tlb` - To calculate miss rate
- `itlb_walk` - Page table walks for iTLB misses
- Generic `iTLB-load-misses` - Similar

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1i_tlb_refill/,armv8_cortex_a78/itlb_walk/ ./lidar_centerpoint

# Output interpretation:
# 234 l1i_tlb_refill
# 50 itlb_walk
# Most refills from L2 TLB (not page table) - good
```

---

### l2d_cache

**Explanation**: ARM Cortex-A78 count of L2 cache accesses. L2 is accessed on L1 misses. High L2 access counts indicate working set exceeds L1 but may fit in L2. ARM-specific L2 cache monitoring.

**Commonly Used With**:
- `l2d_cache_refill` - To calculate L2 hit rate
- `l1d_cache_refill` - L1 misses feed into L2 accesses
- `l3d_cache` - L2 misses feed into L3 accesses

**Example**:
```bash
perf stat -e armv8_cortex_a78/l2d_cache/,armv8_cortex_a78/l2d_cache_refill/ ./euclidean_cluster

# Output interpretation:
# 500,000 l2d_cache
# 50,000 l2d_cache_refill
# 90% L2 hit rate - working set fits mostly in L2
```

---

### l2d_cache_allocate

**Explanation**: ARM Cortex-A78 count of L2 cache line allocations. When data is brought into L2 (from L3 or memory), a cache line is allocated. High allocations indicate cache thrashing or working set exceeding L2. ARM-specific L2 allocation tracking.

**Commonly Used With**:
- `l2d_cache_refill` - Refills cause allocations
- `l2d_cache_wb` - Allocations may force writebacks
- `l3d_cache` - Source of allocated data

**Example**:
```bash
perf stat -e armv8_cortex_a78/l2d_cache_allocate/,armv8_cortex_a78/l2d_cache_refill/ ./shape_estimation

# Output interpretation:
# 60,000 l2d_cache_allocate
# 60,000 l2d_cache_refill
# 1:1 ratio - each refill allocates a line (normal)
```

---

### l2d_cache_lmiss_rd

**Explanation**: ARM Cortex-A78 count of L2 cache line read misses. Tracks read operations that missed L2 and went to L3/memory. ARM-specific separation of read vs. write L2 cache behavior.

**Commonly Used With**:
- `l2d_cache_refill` - Total L2 misses
- `l3d_cache_lmiss_rd` - L3 read misses
- `ll_cache_miss_rd` - Last-level cache read misses

**Example**:
```bash
perf stat -e armv8_cortex_a78/l2d_cache_lmiss_rd/,armv8_cortex_a78/l2d_cache/ ./occupancy_grid_map

# Output interpretation:
# 30,000 l2d_cache_lmiss_rd
# 500,000 l2d_cache
# 6% L2 read miss rate - raycasting has moderate L2 pressure
```

---

### l2d_cache_refill

**Explanation**: ARM Cortex-A78 count of L2 cache refills from L3 or memory. Each refill is an L2 miss. High L2 refills indicate working set exceeds L2 capacity. ARM-specific L2 miss measurement.

**Commonly Used With**:
- `l2d_cache` - To calculate L2 hit rate
- `l3d_cache` - L2 misses feed into L3
- `cache-misses` - L3 misses (if no L3) or LLC misses

**Example**:
```bash
perf stat -e armv8_cortex_a78/l2d_cache_refill/,armv8_cortex_a78/l2d_cache/ ./multi_object_tracker

# Output interpretation:
# 50,000 l2d_cache_refill
# 500,000 l2d_cache
# 10% L2 miss rate - object tracking working set spans L2/L3
```

---

### l2d_cache_wb

**Explanation**: ARM Cortex-A78 count of L2 cache writebacks to L3 or memory. Writebacks occur when dirty L2 lines are evicted. High writebacks indicate write-intensive workload or L2 cache pressure. ARM-specific L2 write behavior.

**Commonly Used With**:
- `l2d_cache_refill` - Cache refills vs. writebacks
- `l3d_cache_wb` - L3 writeback behavior
- `l1d_cache_wb` - Multi-level writeback analysis

**Example**:
```bash
perf stat -e armv8_cortex_a78/l2d_cache_wb/,armv8_cortex_a78/l2d_cache/ ./velocity_smoother

# Output interpretation:
# 10,000 l2d_cache_wb
# 200,000 l2d_cache
# 5% writeback rate - optimization updates trajectory in-place
```

---

### l2d_tlb

**Explanation**: ARM Cortex-A78 count of L2 TLB accesses. L2 TLB is accessed on L1 TLB misses. High L2 TLB accesses indicate poor L1 TLB locality but may have good L2 TLB locality. ARM-specific two-level TLB architecture.

**Commonly Used With**:
- `l2d_tlb_refill` - To calculate L2 TLB hit rate
- `l1d_tlb_refill` - L1 TLB misses feed into L2 TLB
- `dtlb_walk` - L2 TLB misses require page table walk

**Example**:
```bash
perf stat -e armv8_cortex_a78/l2d_tlb/,armv8_cortex_a78/l2d_tlb_refill/ ./map_based_prediction

# Output interpretation:
# 5,000 l2d_tlb
# 100 l2d_tlb_refill
# 98% L2 TLB hit rate - good page locality at L2 level
```

---

### l2d_tlb_refill

**Explanation**: ARM Cortex-A78 count of L2 TLB refills requiring page table walk. L2 TLB misses are expensive, requiring full page table walk. High refills indicate very poor TLB locality. ARM-specific L2 TLB miss measurement.

**Commonly Used With**:
- `l2d_tlb` - To calculate L2 TLB hit rate
- `dtlb_walk` - Should match (page table walks)
- `l1d_tlb_refill` - Multi-level TLB behavior

**Example**:
```bash
perf stat -e armv8_cortex_a78/l2d_tlb_refill/,armv8_cortex_a78/dtlb_walk/ ./ndt_scan_matcher

# Output interpretation:
# 100 l2d_tlb_refill
# 100 dtlb_walk
# Match confirms L2 TLB misses cause page walks
```

---

### l3d_cache

**Explanation**: ARM Cortex-A78 count of L3 cache accesses. L3 is accessed on L2 misses. L3 is shared across cores. High L3 accesses indicate large working sets. ARM-specific L3 cache (may not exist on all ARM chips).

**Commonly Used With**:
- `l3d_cache_refill` - To calculate L3 hit rate
- `l2d_cache_refill` - L2 misses feed into L3
- Generic `LLC-loads` - L3 is often the LLC

**Example**:
```bash
perf stat -e armv8_cortex_a78/l3d_cache/,armv8_cortex_a78/l3d_cache_refill/ ./lidar_centerpoint

# Output interpretation:
# 200,000 l3d_cache
# 100,000 l3d_cache_refill
# 50% L3 hit rate - neural network weights span L2/L3/memory
```

---

### l3d_cache_allocate

**Explanation**: ARM Cortex-A78 count of L3 cache line allocations. L3 allocations occur when bringing data from memory. High allocations indicate memory-intensive workload. ARM-specific L3 allocation tracking.

**Commonly Used With**:
- `l3d_cache_refill` - Refills cause allocations
- `mem_access` - Memory accesses that allocate in L3
- `l3d_cache_wb` - Allocations may force writebacks

**Example**:
```bash
perf stat -e armv8_cortex_a78/l3d_cache_allocate/,armv8_cortex_a78/l3d_cache_refill/ ./pointcloud_concatenate_data

# Output interpretation:
# 50,000 l3d_cache_allocate
# 50,000 l3d_cache_refill
# 1:1 ratio - normal allocation on refill
```

---

### l3d_cache_lmiss_rd

**Explanation**: ARM Cortex-A78 count of L3 cache read misses going to memory. These are the most expensive misses. High L3 read misses indicate working set exceeds all cache levels. ARM-specific L3 read miss tracking.

**Commonly Used With**:
- `l3d_cache_refill` - Total L3 misses
- Generic `cache-misses` or `LLC-load-misses` - Should match
- `mem_access` - Memory operations from L3 misses

**Example**:
```bash
perf stat -e armv8_cortex_a78/l3d_cache_lmiss_rd/,armv8_cortex_a78/l3d_cache/ ./occupancy_grid_map

# Output interpretation:
# 40,000 l3d_cache_lmiss_rd
# 200,000 l3d_cache
# 20% L3 miss rate - memory-bound raycasting
```

---

### l3d_cache_refill

**Explanation**: ARM Cortex-A78 count of L3 cache refills from main memory. Each refill is an L3 miss - the most expensive cache event. Minimizing L3 refills is critical for performance. ARM-specific L3 miss measurement.

**Commonly Used With**:
- `l3d_cache` - To calculate L3 hit rate
- Generic `cache-misses` - Should be similar or same
- `mem_access` - Memory accesses include L3 refills

**Example**:
```bash
perf stat -e armv8_cortex_a78/l3d_cache_refill/,armv8_cortex_a78/l3d_cache/ ./euclidean_cluster

# Output interpretation:
# 10,000 l3d_cache_refill
# 100,000 l3d_cache
# 10% L3 miss rate - voxel grid mostly fits in cache
```

---

### ll_cache_miss_rd

**Explanation**: ARM Cortex-A78 count of last-level cache read misses. On systems where L3 is LLC, this equals l3d_cache_lmiss_rd. Provides portable way to measure LLC behavior. ARM-specific but conceptually matches generic cache-misses.

**Commonly Used With**:
- `ll_cache_rd` - To calculate LLC miss rate
- Generic `LLC-load-misses` or `cache-misses` - Should match
- `mem_access` - Memory operations from LLC misses

**Example**:
```bash
perf stat -e armv8_cortex_a78/ll_cache_miss_rd/,armv8_cortex_a78/ll_cache_rd/ ./motion_velocity_planner

# Output interpretation:
# 5,000 ll_cache_miss_rd
# 50,000 ll_cache_rd
# 10% LLC miss rate - path processing has good locality
```

---

### ll_cache_rd

**Explanation**: ARM Cortex-A78 count of last-level cache read accesses. LLC reads occur when all prior cache levels miss. Portable metric for LLC behavior regardless of whether it's L2 or L3. ARM-specific LLC monitoring.

**Commonly Used With**:
- `ll_cache_miss_rd` - To calculate LLC hit rate
- Generic `LLC-loads` - Should be similar
- `cache-misses` - LLC misses

**Example**:
```bash
perf stat -e armv8_cortex_a78/ll_cache_rd/,armv8_cortex_a78/ll_cache_miss_rd/ ./mission_planner

# Output interpretation:
# 20,000 ll_cache_rd
# 2,000 ll_cache_miss_rd
# 90% LLC hit rate - graph fits in cache
```

---

### mem_access

**Explanation**: ARM Cortex-A78 count of memory operations (loads and stores). This is total memory access count including all cache levels. High mem_access indicates memory-intensive algorithm. ARM-specific total memory operation counting.

**Commonly Used With**:
- `inst_retired` - To calculate memory operations per instruction
- `l1d_cache` - Subset of mem_access
- `cache-misses` - To see what fraction goes to DRAM

**Example**:
```bash
perf stat -e armv8_cortex_a78/mem_access/,armv8_cortex_a78/inst_retired/ ./shape_estimation

# Output interpretation:
# 3,000,000 mem_access
# 10,000,000 inst_retired
# 30% memory operations - typical for matrix-heavy PCA
```

---

### memory_error

**Explanation**: ARM Cortex-A78 count of memory errors detected by hardware (ECC errors, parity errors). Should be zero in normal operation. Non-zero indicates hardware problems. ARM-specific error monitoring.

**Commonly Used With**:
- `mem_access` - To calculate error rate
- Used for hardware validation, not algorithm profiling

**Example**:
```bash
perf stat -e armv8_cortex_a78/memory_error/,armv8_cortex_a78/mem_access/ ./any_node

# Output interpretation:
# 0 memory_error - good, no hardware issues detected
```

---

### op_retired

**Explanation**: ARM Cortex-A78 count of micro-operations retired. Modern CPUs decode instructions into micro-ops. Some complex instructions become multiple micro-ops. High op_retired relative to inst_retired indicates many complex instructions. ARM-specific micro-architectural detail.

**Commonly Used With**:
- `inst_retired` - Ratio shows instruction complexity
- `op_spec` - Speculative vs. retired micro-ops
- `cpu_cycles` - Micro-ops per cycle

**Example**:
```bash
perf stat -e armv8_cortex_a78/op_retired/,armv8_cortex_a78/inst_retired/ ./trajectory_follower_controller

# Output interpretation:
# 110,000,000 op_retired
# 100,000,000 inst_retired
# 1.1 micro-ops per instruction - mostly simple instructions
```

---

### op_spec

**Explanation**: ARM Cortex-A78 count of speculatively executed micro-operations. Similar to inst_spec but at micro-op level. High op_spec indicates aggressive speculation or many mispredictions. ARM-specific speculation monitoring.

**Commonly Used With**:
- `op_retired` - Speculation efficiency ratio
- `inst_spec` - Instruction-level speculation
- `br_mis_pred` - Mispredictions waste speculative work

**Example**:
```bash
perf stat -e armv8_cortex_a78/op_spec/,armv8_cortex_a78/op_retired/ ./multi_object_tracker

# Output interpretation:
# 120,000,000 op_spec
# 110,000,000 op_retired
# 9% speculation waste - acceptable for data association logic
```

---

### remote_access

**Explanation**: ARM Cortex-A78 count of remote memory accesses in multi-socket systems. On Jetson Orin (single socket), this should be zero or irrelevant. ARM-specific NUMA monitoring.

**Commonly Used With**:
- `mem_access` - Local vs. remote memory ratio
- Relevant only for multi-socket ARM servers

**Example**:
```bash
perf stat -e armv8_cortex_a78/remote_access/,armv8_cortex_a78/mem_access/ ./any_node

# Output interpretation:
# 0 remote_access - expected on Jetson Orin (single socket)
```

---

### exc_taken

**Explanation**: ARM Cortex-A78 count of exceptions taken (interrupts, traps, system calls). Exceptions are expensive due to context switching overhead. High exception counts indicate frequent kernel interaction or interrupts. ARM-specific exception monitoring.

**Commonly Used With**:
- `inst_retired` - Exceptions per instruction
- `context-switches` - System calls cause context switches
- `cpu_cycles` - Exceptions add cycle overhead

**Example**:
```bash
perf stat -e armv8_cortex_a78/exc_taken/,armv8_cortex_a78/inst_retired/ ./ekf_localizer

# Output interpretation:
# 50 exc_taken
# 100,000,000 inst_retired
# Very low - minimal kernel interaction
```

---

### exc_return

**Explanation**: ARM Cortex-A78 count of exception returns. Should match exc_taken in normal operation. Measures return from exception handlers. ARM-specific exception flow monitoring.

**Commonly Used With**:
- `exc_taken` - Should be equal
- `context-switches` - Related system events

**Example**:
```bash
perf stat -e armv8_cortex_a78/exc_return/,armv8_cortex_a78/exc_taken/ ./velocity_smoother

# Output interpretation:
# 30 exc_return
# 30 exc_taken
# Match confirms normal exception handling
```

---

### stall

**Explanation**: ARM Cortex-A78 count of pipeline stall cycles. Generic stall counter summing all stall sources. High stall cycles indicate pipeline inefficiency. ARM-specific aggregate stall measurement.

**Commonly Used With**:
- `cpu_cycles` - To calculate stall percentage
- `stall_frontend` / `stall_backend` - To identify stall source
- Generic `stalled-cycles-frontend` / `stalled-cycles-backend`

**Example**:
```bash
perf stat -e armv8_cortex_a78/stall/,armv8_cortex_a78/cpu_cycles/ ./occupancy_grid_map

# Output interpretation:
# 2,000,000,000 stall
# 5,000,000,000 cpu_cycles
# 40% pipeline stalls - memory-bound raycasting
```

---

### stall_frontend

**Explanation**: ARM Cortex-A78 count of frontend (fetch/decode) stall cycles. Frontend stalls occur due to I-cache misses or branch mispredictions. ARM-specific detailed frontend stall counter.

**Commonly Used With**:
- `stall_backend` - To identify dominant stall source
- Generic `stalled-cycles-frontend` - Similar
- `br_mis_pred` - Branch mispredictions cause frontend stalls

**Example**:
```bash
perf stat -e armv8_cortex_a78/stall_frontend/,armv8_cortex_a78/cpu_cycles/ ./mission_planner

# Output interpretation:
# 300,000,000 stall_frontend
# 3,000,000,000 cpu_cycles
# 10% frontend stalls - branch predictor handles graph traversal well
```

---

### stall_backend

**Explanation**: ARM Cortex-A78 count of backend (execution) stall cycles. Backend stalls occur due to data dependencies or cache misses. ARM-specific detailed backend stall counter.

**Commonly Used With**:
- `stall_frontend` - To identify dominant bottleneck
- Generic `stalled-cycles-backend` - Similar
- `cache-misses` - Cache misses cause backend stalls

**Example**:
```bash
perf stat -e armv8_cortex_a78/stall_backend/,armv8_cortex_a78/cpu_cycles/ ./ndt_scan_matcher

# Output interpretation:
# 1,500,000,000 stall_backend
# 5,000,000,000 cpu_cycles
# 30% backend stalls - voxel lookups cause data stalls
```

---

### stall_backend_mem

**Explanation**: ARM Cortex-A78 count of backend stalls specifically due to memory operations. Isolates memory-related backend stalls. High values indicate memory bandwidth or latency bottleneck. ARM-specific memory stall attribution.

**Commonly Used With**:
- `stall_backend` - Memory vs. other backend stalls
- `cache-misses` - Cache misses cause memory stalls
- `ll_cache_miss_rd` - LLC misses are main memory stall source

**Example**:
```bash
perf stat -e armv8_cortex_a78/stall_backend_mem/,armv8_cortex_a78/stall_backend/ ./lidar_centerpoint

# Output interpretation:
# 1,200,000,000 stall_backend_mem
# 1,500,000,000 stall_backend
# 80% of backend stalls are memory - neural network is memory-bound
```

---

### stall_slot

**Explanation**: ARM Cortex-A78 count of pipeline slots wasted due to stalls. Cortex-A78 has multiple issue slots per cycle. Stalled slots represent wasted parallelism opportunities. ARM-specific slot-level stall accounting.

**Commonly Used With**:
- `cpu_cycles` - Slot utilization analysis
- `stall_slot_frontend` / `stall_slot_backend` - Slot stall breakdown
- `inst_retired` - Instructions per non-stalled slot

**Example**:
```bash
perf stat -e armv8_cortex_a78/stall_slot/,armv8_cortex_a78/cpu_cycles/ ./behavior_path_planner

# Output interpretation:
# 1,000,000,000 stall_slot
# 4,000,000,000 potential_slots (assuming 4-wide)
# 25% slot waste - room for optimization
```

---

### stall_slot_frontend

**Explanation**: ARM Cortex-A78 count of pipeline slots wasted due to frontend stalls. Measures instruction supply bottleneck at slot granularity. ARM-specific frontend slot stall accounting.

**Commonly Used With**:
- `stall_slot` - Frontend vs. total slot stalls
- `stall_frontend` - Cycle vs. slot-based accounting
- `l1i_cache_lmiss` - I-cache misses cause slot stalls

**Example**:
```bash
perf stat -e armv8_cortex_a78/stall_slot_frontend/,armv8_cortex_a78/stall_slot/ ./autonomous_emergency_braking

# Output interpretation:
# 100,000,000 stall_slot_frontend
# 500,000,000 stall_slot
# 20% of stalled slots are frontend - mostly backend bound
```

---

### stall_slot_backend

**Explanation**: ARM Cortex-A78 count of pipeline slots wasted due to backend stalls. Measures execution bottleneck at slot granularity. ARM-specific backend slot stall accounting.

**Commonly Used With**:
- `stall_slot` - Backend vs. total slot stalls
- `stall_backend` - Cycle vs. slot-based accounting
- `cache-misses` - Data cache misses cause backend slot stalls

**Example**:
```bash
perf stat -e armv8_cortex_a78/stall_slot_backend/,armv8_cortex_a78/stall_slot/ ./multi_object_tracker

# Output interpretation:
# 800,000,000 stall_slot_backend
# 1,000,000,000 stall_slot
# 80% of stalled slots are backend - data-bound tracking
```

---

### sw_incr

**Explanation**: ARM Cortex-A78 count of software increment events. This is a programmable counter that software can explicitly increment. Used for custom instrumentation. ARM-specific software event counting.

**Commonly Used With**:
- Custom profiling instrumentation
- Not typically used in standard profiling

**Example**:
```bash
# Requires explicit software instrumentation to be useful
# Not commonly used in standard perf profiling
```

---

### cid_write_retired

**Explanation**: ARM Cortex-A78 count of Context ID writes retired. Context ID changes during context switches. Measures OS-level context switching. ARM-specific context switch monitoring.

**Commonly Used With**:
- Generic `context-switches` - Should correlate
- `exc_taken` - Context switches involve exceptions

**Example**:
```bash
perf stat -e armv8_cortex_a78/cid_write_retired/,context-switches ./trajectory_follower_controller

# Output interpretation:
# 50 cid_write_retired
# 50 context-switches
# Match confirms context ID tracking works
```

---

### ttbr_write_retired

**Explanation**: ARM Cortex-A78 count of Translation Table Base Register writes retired. TTBR changes during process switches. Measures heavy context switches (process vs. thread). ARM-specific process switch monitoring.

**Commonly Used With**:
- `cid_write_retired` - Context switches
- Generic `context-switches` - Subset are process switches

**Example**:
```bash
perf stat -e armv8_cortex_a78/ttbr_write_retired/,context-switches ./any_node

# Output interpretation:
# 5 ttbr_write_retired
# 50 context-switches
# 10% are process switches, 90% are thread switches
```

---

### cnt_cycles

**Explanation**: ARM Cortex-A78 count of counter cycles. Typically matches cpu_cycles. This is the generic counter register. ARM-specific generic cycle counter.

**Commonly Used With**:
- `cpu_cycles` - Should match
- Used for low-level timing

**Example**:
```bash
perf stat -e armv8_cortex_a78/cnt_cycles/,armv8_cortex_a78/cpu_cycles/ ./any_node

# Output interpretation:
# 5,000,000,000 cnt_cycles
# 5,000,000,000 cpu_cycles
# Should always match
```

---

### sample_collision

**Explanation**: ARM Cortex-A78 count of Statistical Profiling Extension (SPE) sample collisions. SPE is ARM's hardware profiling feature. Collisions occur when samples overlap. ARM-specific profiling infrastructure monitoring.

**Commonly Used With**:
- `sample_feed` / `sample_pop` - SPE sampling pipeline
- ARM SPE profiling tools

**Example**:
```bash
# Relevant only when using ARM SPE profiling
# Not used in standard perf stat
```

---

### sample_feed / sample_pop / sample_filtrate

**Explanation**: ARM Cortex-A78 Statistical Profiling Extension (SPE) sample pipeline counters. Track sample generation, filtering, and collection. ARM-specific profiling infrastructure used by advanced ARM profiling tools.

**Commonly Used With**:
- ARM SPE profiling workflow
- Not used in standard perf stat workflows

**Example**:
```bash
# These are infrastructure counters for ARM SPE
# Not typically used in application profiling
```

---

## SCF PMU Events (System Cache Fabric)

### scf_pmu/bus_access/

**Explanation**: Jetson Orin specific System Cache Fabric (SCF) bus access counter. SCF connects CPU, GPU, and other accelerators. Counts total bus accesses through SCF. Platform-specific to Nvidia Jetson Orin interconnect architecture.

**Commonly Used With**:
- `scf_pmu/bus_access_rd/` / `scf_pmu/bus_access_wr/` - Read vs. write breakdown
- `scf_pmu/bus_cycles/` - Bus utilization
- `armv8_cortex_a78/bus_access/` - CPU-specific bus access

**Example**:
```bash
perf stat -e scf_pmu/bus_access/,scf_pmu/bus_access_rd/,scf_pmu/bus_access_wr/ ./lidar_centerpoint

# Output interpretation:
# 1,000,000 scf_pmu/bus_access/
# 700,000 bus_access_rd
# 300,000 bus_access_wr
# CPU-GPU communication for neural network inference
```

---

### scf_pmu/bus_access_normal/

**Explanation**: Jetson Orin SCF normal bus accesses (non-peripheral). Counts accesses to normal memory regions through SCF. Jetson-specific interconnect monitoring.

**Commonly Used With**:
- `scf_pmu/bus_access_periph/` - Normal vs. peripheral traffic
- `scf_pmu/bus_access/` - Total bus access

**Example**:
```bash
perf stat -e scf_pmu/bus_access_normal/,scf_pmu/bus_access/ ./any_node

# Output interpretation:
# 950,000 bus_access_normal
# 1,000,000 bus_access
# 95% normal memory traffic
```

---

### scf_pmu/bus_access_periph/

**Explanation**: Jetson Orin SCF peripheral bus accesses. Counts accesses to peripheral devices (I/O) through SCF. Jetson-specific I/O traffic monitoring.

**Commonly Used With**:
- `scf_pmu/bus_access_normal/` - Peripheral vs. normal memory
- `scf_pmu/bus_access/` - Total bus access

**Example**:
```bash
perf stat -e scf_pmu/bus_access_periph/,scf_pmu/bus_access/ ./pointcloud_concatenate_data

# Output interpretation:
# 50,000 bus_access_periph
# 1,000,000 bus_access
# 5% peripheral - sensor data ingestion
```

---

### scf_pmu/bus_access_rd/

**Explanation**: Jetson Orin SCF bus read accesses. Counts read operations through SCF interconnect. Jetson-specific read traffic monitoring.

**Commonly Used With**:
- `scf_pmu/bus_access_wr/` - Read vs. write ratio
- `scf_pmu/bus_access/` - Total traffic

**Example**:
```bash
perf stat -e scf_pmu/bus_access_rd/,scf_pmu/bus_access_wr/ ./ndt_scan_matcher

# Output interpretation:
# 700,000 bus_access_rd
# 300,000 bus_access_wr
# 70% read traffic - typical for data processing
```

---

### scf_pmu/bus_access_wr/

**Explanation**: Jetson Orin SCF bus write accesses. Counts write operations through SCF interconnect. Jetson-specific write traffic monitoring.

**Commonly Used With**:
- `scf_pmu/bus_access_rd/` - Read vs. write ratio
- `scf_pmu/bus_access/` - Total traffic

**Example**:
```bash
perf stat -e scf_pmu/bus_access_wr/,scf_pmu/bus_access/ ./occupancy_grid_map

# Output interpretation:
# 400,000 bus_access_wr
# 1,000,000 bus_access
# 40% writes - grid updates generate write traffic
```

---

### scf_pmu/bus_access_shared/

**Explanation**: Jetson Orin SCF shared bus accesses. Counts accesses to shared memory regions (CPU-GPU shared memory). Jetson-specific shared memory monitoring critical for heterogeneous computing.

**Commonly Used With**:
- `scf_pmu/bus_access_not_shared/` - Shared vs. private memory
- `scf_pmu/bus_access/` - Total traffic

**Example**:
```bash
perf stat -e scf_pmu/bus_access_shared/,scf_pmu/bus_access/ ./lidar_centerpoint

# Output interpretation:
# 500,000 bus_access_shared
# 1,000,000 bus_access
# 50% shared - CPU-GPU zero-copy data transfer
```

---

### scf_pmu/bus_access_not_shared/

**Explanation**: Jetson Orin SCF non-shared bus accesses. Counts accesses to private (CPU-only or GPU-only) memory. Jetson-specific private memory monitoring.

**Commonly Used With**:
- `scf_pmu/bus_access_shared/` - Shared vs. private ratio
- `scf_pmu/bus_access/` - Total traffic

**Example**:
```bash
perf stat -e scf_pmu/bus_access_not_shared/,scf_pmu/bus_access/ ./multi_object_tracker

# Output interpretation:
# 900,000 bus_access_not_shared
# 1,000,000 bus_access
# 90% private - CPU-only tracking computation
```

---

### scf_pmu/bus_cycles/

**Explanation**: Jetson Orin SCF bus cycle count. Measures cycles the SCF interconnect is active. Platform-specific to Jetson Orin interconnect timing. High cycles indicate sustained bus traffic.

**Commonly Used With**:
- `scf_pmu/bus_access/` - To calculate average cycles per access
- `cpu-cycles` - Bus vs. CPU cycle ratio

**Example**:
```bash
perf stat -e scf_pmu/bus_cycles/,scf_pmu/bus_access/ ./lidar_centerpoint

# Output interpretation:
# 50,000,000 bus_cycles
# 1,000,000 bus_access
# 50 cycles per access - typical for memory operations
```

---

### scf_pmu/scf_cache/

**Explanation**: Jetson Orin System Cache (within SCF) access count. Jetson Orin has a system-level cache shared by CPU/GPU/accelerators. Counts SCF cache accesses. Platform-specific last-level shared cache.

**Commonly Used With**:
- `scf_pmu/scf_cache_refill/` - SCF cache hit rate
- `scf_pmu/scf_cache_wb/` - Write behavior

**Example**:
```bash
perf stat -e scf_pmu/scf_cache/,scf_pmu/scf_cache_refill/ ./any_node

# Output interpretation:
# 5,000,000 scf_cache
# 500,000 scf_cache_refill
# 90% SCF cache hit rate - good sharing between CPU and GPU
```

---

### scf_pmu/scf_cache_allocate/

**Explanation**: Jetson Orin System Cache line allocations. Counts cache line allocations in SCF cache. Platform-specific allocation tracking for shared cache.

**Commonly Used With**:
- `scf_pmu/scf_cache_refill/` - Refills cause allocations
- `scf_pmu/scf_cache/` - Cache access patterns

**Example**:
```bash
perf stat -e scf_pmu/scf_cache_allocate/,scf_pmu/scf_cache_refill/ ./lidar_centerpoint

# Output interpretation:
# 600,000 scf_cache_allocate
# 600,000 scf_cache_refill
# 1:1 ratio - each refill allocates a line
```

---

### scf_pmu/scf_cache_refill/

**Explanation**: Jetson Orin System Cache refills from main memory. SCF cache misses that fetch from DRAM. Platform-specific last-level shared cache miss measurement.

**Commonly Used With**:
- `scf_pmu/scf_cache/` - Cache hit rate
- `cache-misses` - CPU-specific cache misses vs. system cache

**Example**:
```bash
perf stat -e scf_pmu/scf_cache_refill/,scf_pmu/scf_cache/ ./occupancy_grid_map

# Output interpretation:
# 400,000 scf_cache_refill
# 4,000,000 scf_cache
# 10% SCF cache miss rate - shared cache helps CPU-GPU collaboration
```

---

### scf_pmu/scf_cache_wb/

**Explanation**: Jetson Orin System Cache writebacks to memory. Counts dirty SCF cache lines written back to DRAM. Platform-specific write behavior monitoring for shared cache.

**Commonly Used With**:
- `scf_pmu/scf_cache_refill/` - Refills vs. writebacks
- `scf_pmu/scf_cache/` - Write intensity

**Example**:
```bash
perf stat -e scf_pmu/scf_cache_wb/,scf_pmu/scf_cache/ ./velocity_smoother

# Output interpretation:
# 200,000 scf_cache_wb
# 2,000,000 scf_cache
# 10% writeback rate - optimization updates shared data
```

---

## Summary

These 77+ architecture-specific events provide deep insight into ARM Cortex-A78 and Jetson Orin platform behavior:

- **CPU Pipeline**: Cycles, stalls, speculation (ARM Cortex-A78 specific)
- **Cache Hierarchy**: L1/L2/L3 detailed behavior (ARM PMU)
- **TLB**: Multi-level TLB monitoring (ARM-specific)
- **Memory**: Bus access, memory operations (ARM and SCF)
- **System**: Exceptions, context switches (ARM-specific)
- **Platform**: SCF interconnect, shared cache (Jetson Orin specific)

Use these metrics to understand hardware-level bottlenecks and optimize for ARM Cortex-A78 and Jetson Orin platform characteristics. Combine with architecture-agnostic metrics for complete profiling picture.

