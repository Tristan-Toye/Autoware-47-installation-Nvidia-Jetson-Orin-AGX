# Architecture-Agnostic Perf Commands

These performance counters measure algorithmic behavior and execution characteristics that are relatively independent of the underlying hardware architecture. While no metric is truly architecture-agnostic, these events reflect algorithm properties (complexity, memory access patterns, control flow) rather than specific microarchitectural features.

---

## Instruction & Execution Metrics

### instructions

**Explanation**: Counts the total number of instructions retired (successfully executed and committed). This is the most fundamental metric for algorithmic complexity - it directly reflects the amount of work the algorithm performs. Higher instruction counts indicate more computational complexity. This metric is architecture-agnostic because all processors execute instructions, regardless of their internal pipeline design. It's the best proxy for algorithm efficiency: fewer instructions typically mean a more efficient algorithm for the same task.

**Commonly Used With**:
- `cpu-cycles` - To calculate Instructions Per Cycle (IPC)
- `task-clock` - To calculate instructions per second
- `cache-misses` - To understand if high instruction count correlates with memory bottlenecks

**Example**:
```bash
perf stat -e instructions ./ndt_scan_matcher

# Output interpretation:
# 1,234,567,890 instructions
# If processing 100K points, that's ~12,345 instructions/point
# Compare across algorithms: NDT vs ICP vs other localization methods
```

---

### branch-misses

**Explanation**: Counts the number of branch mispredictions - cases where the CPU's branch predictor guessed wrong about which way a conditional branch would go. Branch misses are expensive because the CPU must flush its pipeline and restart from the correct path. High branch miss rates indicate unpredictable control flow (many if/else statements, switch cases, or loop conditions that vary). This metric is algorithm-dependent: algorithms with regular, predictable branches (like simple loops) have low miss rates, while algorithms with data-dependent branching (like tree traversals, sorting) have higher miss rates.

**Commonly Used With**:
- `branches` or `branch-loads` - To calculate branch miss rate (misses/total branches)
- `instructions` - To see if branch misses dominate execution time
- `cpu-cycles` - Branch misses add cycles due to pipeline flushes

**Example**:
```bash
perf stat -e branch-misses,branches ./multi_object_tracker

# Output interpretation:
# 12,345 branch-misses
# 1,234,567 branches
# Miss rate: 1.0% - excellent for state machine code
# High miss rates (>5%) suggest unpredictable branching (e.g., data-dependent decisions)
```

---

### branch-loads

**Explanation**: Counts total branch instructions executed (conditional branches, function calls, returns). This reflects control flow complexity - algorithms with many conditionals, loops, or function calls will have high branch counts. Simple, straight-line code has few branches. Branch density (branches per instruction) indicates code structure: procedural code with many function calls has high branch density, while vectorized or loop-unrolled code has lower branch density.

**Commonly Used With**:
- `branch-misses` - To calculate branch prediction accuracy
- `instructions` - To calculate branch density (branches/instructions)
- `branch-load-misses` - Cache-specific branch behavior

**Example**:
```bash
perf stat -e branch-loads,instructions ./behavior_path_planner

# Output interpretation:
# 234,567 branch-loads
# 1,234,567 instructions
# Branch density: 19% - typical for scene module switching logic
```

---

### branch-load-misses

**Explanation**: Counts branch instructions that missed in the Branch Target Buffer (BTB) or required fetching from lower cache levels. While related to cache hierarchy, this metric reflects control flow locality - whether branch targets are repeatedly accessed (good locality) or scattered (poor locality). Algorithms with many unique function call sites or indirect branches (virtual functions, function pointers) will have higher branch load misses.

**Commonly Used With**:
- `branch-loads` - To calculate branch cache miss rate
- `L1-icache-load-misses` - Related instruction cache effects
- `branch-misses` - Combined branch prediction and caching analysis

**Example**:
```bash
perf stat -e branch-load-misses,branch-loads ./lidar_centerpoint

# Output interpretation:
# 1,234 branch-load-misses
# 234,567 branch-loads  
# Miss rate: 0.5% - good branch target locality in neural network inference
```

---

## Cache & Memory Access Patterns

### cache-references

**Explanation**: Counts the total number of last-level cache (LLC) accesses. This reflects the working set size and memory access patterns of the algorithm. High cache reference counts indicate the algorithm is accessing a large amount of data that doesn't fit in lower-level caches. This is architecture-agnostic in the sense that it measures "how much data is the algorithm touching" rather than specific cache sizes. Algorithms with good spatial and temporal locality will have fewer cache references because data stays in L1/L2 caches.

**Commonly Used With**:
- `cache-misses` - To calculate LLC hit rate
- `instructions` - To measure data access intensity (cache refs per instruction)
- `L1-dcache-load-misses` - To understand cache hierarchy behavior

**Example**:
```bash
perf stat -e cache-references,cache-misses ./euclidean_cluster

# Output interpretation:
# 12,345 cache-references
# 1,234 cache-misses
# LLC hit rate: 90% - good locality for voxel grid access pattern
```

---

### cache-misses

**Explanation**: Counts the number of last-level cache (LLC) misses that result in main memory access. This is the most expensive memory operation - missing LLC means going to DRAM which is 100-300 cycles of latency. High cache miss counts indicate poor data locality: the algorithm accesses data in random patterns, or the working set exceeds available cache. This metric is algorithm-dependent: sequential access patterns have low miss rates, while pointer-chasing or hash table lookups have high miss rates.

**Commonly Used With**:
- `cache-references` - To calculate miss rate
- `instructions` - Misses per kilo-instruction (MPKI) is a key metric
- `task-clock` - To estimate time spent waiting for memory

**Example**:
```bash
perf stat -e cache-misses,instructions ./ndt_scan_matcher

# Output interpretation:
# 45,678 cache-misses
# 10,000,000 instructions
# MPKI: 4.57 - moderate, voxel hash lookups cause misses
```

---

### L1-dcache-loads

**Explanation**: Counts load operations from L1 data cache. This reflects memory read intensity - how often the algorithm reads data from memory. High L1 cache load counts indicate a data-intensive algorithm. This is relatively architecture-agnostic because it measures "how many data reads" rather than L1 cache size or implementation. Compare across algorithms: matrix operations have very high L1 loads, while compute-bound code (lots of arithmetic, few memory operations) has lower L1 loads.

**Commonly Used With**:
- `L1-dcache-load-misses` - To calculate L1 hit rate
- `instructions` - To measure memory vs. compute ratio
- `L1-icache-loads` - To compare data vs. instruction fetches

**Example**:
```bash
perf stat -e L1-dcache-loads,instructions ./shape_estimation

# Output interpretation:
# 3,456,789 L1-dcache-loads
# 10,000,000 instructions
# Load ratio: 34.6% - data-intensive (matrix operations in PCA)
```

---

### L1-dcache-load-misses

**Explanation**: Counts L1 data cache misses - load operations that had to fetch from L2 cache or lower. L1 misses indicate the algorithm's data access pattern doesn't match L1 cache size/associativity. Small working sets with good locality have few L1 misses. Large working sets, strided access, or pointer-chasing cause many L1 misses. This metric reflects algorithm memory access patterns independent of specific L1 implementation.

**Commonly Used With**:
- `L1-dcache-loads` - To calculate L1 miss rate
- `L2d_cache_refill` (arch-specific) - To see where misses go
- `cache-misses` - To understand full cache hierarchy behavior

**Example**:
```bash
perf stat -e L1-dcache-load-misses,L1-dcache-loads ./occupancy_grid_map

# Output interpretation:
# 234,567 L1-dcache-load-misses
# 3,456,789 L1-dcache-loads
# Miss rate: 6.8% - acceptable for scattered grid updates
```

---

### L1-icache-loads

**Explanation**: Counts instruction fetches from L1 instruction cache. This reflects code size and instruction fetch patterns. High I-cache loads indicate large code footprint or many function calls. Tight loops with small code have few I-cache loads (instructions are cached and reused). Large switch statements, many inline functions, or template-heavy C++ code increase I-cache loads.

**Commonly Used With**:
- `L1-icache-load-misses` - To calculate instruction cache hit rate
- `instructions` - Some instructions reuse cached data
- `branch-loads` - Function calls cause instruction fetches

**Example**:
```bash
perf stat -e L1-icache-loads,L1-icache-load-misses ./mission_planner

# Output interpretation:
# 1,234,567 L1-icache-loads
# 1,234 L1-icache-load-misses
# Miss rate: 0.1% - excellent, small Dijkstra implementation
```

---

### L1-icache-load-misses

**Explanation**: Counts L1 instruction cache misses - instruction fetches that missed L1 and had to fetch from L2 or lower. I-cache misses indicate large code footprint that doesn't fit in L1, or poor code locality (jumping between distant functions). Algorithms with many small functions called infrequently will have higher I-cache misses than algorithms with tight loops.

**Commonly Used With**:
- `L1-icache-loads` - To calculate miss rate
- `branch-load-misses` - Related to function call patterns
- `instructions` - Instruction fetch efficiency

**Example**:
```bash
perf stat -e L1-icache-load-misses,instructions ./behavior_path_planner

# Output interpretation:
# 5,678 L1-icache-load-misses
# 20,000,000 instructions
# Very low - modular scene architecture but good code locality
```

---

### LLC-loads

**Explanation**: Counts load operations from Last Level Cache (LLC, typically L3). LLC loads occur when data misses in L1 and L2, representing the last chance before main memory. High LLC load counts indicate a working set larger than L1+L2 capacity, or access patterns that evict data before reuse. This metric reflects algorithm working set size and locality in an architecture-agnostic way.

**Commonly Used With**:
- `LLC-load-misses` - To calculate LLC hit rate
- `cache-misses` - LLC misses are the same as cache-misses
- `L1-dcache-load-misses` - To understand cache hierarchy

**Example**:
```bash
perf stat -e LLC-loads,LLC-load-misses ./lidar_centerpoint

# Output interpretation:
# 123,456 LLC-loads
# 45,678 LLC-load-misses
# LLC hit rate: 63% - working set (neural network weights) spans L2/L3 boundary
```

---

### LLC-load-misses

**Explanation**: Counts LLC misses resulting in main memory access. This is identical to `cache-misses` on most systems. LLC misses are the most expensive memory events (~300 cycles latency). High LLC miss counts indicate very large working sets or poor memory access patterns. Optimizing algorithms to reduce LLC misses has the highest impact on performance.

**Commonly Used With**:
- `LLC-loads` - To calculate miss rate
- `instructions` - MPKI at LLC level
- `page-faults` - Sometimes LLC misses correlate with paging

**Example**:
```bash
perf stat -e LLC-load-misses,instructions,task-clock ./map_based_prediction

# Output interpretation:
# 12,345 LLC-load-misses
# 50,000,000 instructions
# MPKI: 0.25 - excellent, small working set for path generation
```

---

### dTLB-loads

**Explanation**: Counts data Translation Lookaside Buffer (TLB) lookups - virtual to physical address translations for data accesses. TLB loads reflect memory access diversity: accessing many different memory pages requires many TLB lookups. Algorithms with poor spatial locality (accessing data scattered across many pages) have high TLB loads. This is architecture-agnostic in measuring "how scattered are memory accesses."

**Commonly Used With**:
- `dTLB-load-misses` - To calculate TLB hit rate
- `page-faults` - TLB misses can lead to page faults if page not in RAM
- `L1-dcache-loads` - TLB lookups happen on L1 cache access

**Example**:
```bash
perf stat -e dTLB-loads,L1-dcache-loads ./multi_object_tracker

# Output interpretation:
# 3,456,789 dTLB-loads
# 3,456,789 L1-dcache-loads  
# One TLB lookup per data access - normal for scattered object access
```

---

### dTLB-load-misses

**Explanation**: Counts data TLB misses - virtual address translations that missed the TLB and required page table walk. TLB misses are expensive (10-100 cycles for page table walk). High TLB miss rates indicate accessing data across many memory pages with poor temporal locality. Algorithms that process large arrays sequentially have low TLB miss rates (sequential pages stay in TLB). Algorithms with pointer-chasing or random access across large memory have high TLB miss rates.

**Commonly Used With**:
- `dTLB-loads` - To calculate miss rate
- `page-faults` - Related memory management events
- `L1-dcache-load-misses` - TLB and cache misses often correlate

**Example**:
```bash
perf stat -e dTLB-load-misses,dTLB-loads ./ndt_scan_matcher

# Output interpretation:
# 1,234 dTLB-load-misses
# 3,456,789 dTLB-loads
# Miss rate: 0.036% - excellent, NDT voxel grid has good page locality
```

---

### iTLB-loads

**Explanation**: Counts instruction TLB lookups - virtual address translations for instruction fetches. High iTLB loads indicate large code footprint across many memory pages. Algorithms with small, tight code have few iTLB loads. Large codebases with many libraries or template instantiations have high iTLB loads.

**Commonly Used With**:
- `iTLB-load-misses` - To calculate instruction TLB hit rate
- `L1-icache-loads` - Related instruction fetch behavior
- `branch-loads` - Function calls to distant code cause iTLB loads

**Example**:
```bash
perf stat -e iTLB-loads,L1-icache-loads ./velocity_smoother

# Output interpretation:
# 123,456 iTLB-loads
# 1,234,567 L1-icache-loads
# ~10% of instruction fetches require TLB lookup - moderate code size
```

---

### iTLB-load-misses

**Explanation**: Counts instruction TLB misses - instruction fetches that missed iTLB and required page table walk. High iTLB miss rates indicate very large code spread across many pages. This is more common in large C++ applications with extensive template usage or dynamic linking.

**Commonly Used With**:
- `iTLB-loads` - To calculate miss rate
- `L1-icache-load-misses` - Related instruction cache behavior
- `instructions` - Instruction TLB efficiency

**Example**:
```bash
perf stat -e iTLB-load-misses,iTLB-loads ./behavior_path_planner

# Output interpretation:
# 234 iTLB-load-misses
# 123,456 iTLB-loads
# Miss rate: 0.19% - low, code fits in reasonable page count
```

---

## System & Scheduling Metrics

### context-switches

**Explanation**: Counts the number of times the scheduler switched the CPU from one thread to another. Context switches are expensive (1-10 microseconds) due to cache flushing, TLB invalidation, and kernel overhead. High context switch counts indicate either many threads competing for CPU, or frequent blocking (waiting for I/O, locks, or synchronization). This metric is algorithm/system design dependent: single-threaded algorithms have zero context switches, while poorly synchronized multi-threaded algorithms have many.

**Commonly Used With**:
- `cpu-migrations` - To see if threads move between cores
- `task-clock` - To measure context switch overhead
- `cache-misses` - Context switches cause cache pollution

**Example**:
```bash
perf stat -e context-switches,task-clock ./trajectory_follower_controller

# Output interpretation:
# 45 context-switches
# 100 ms task-clock
# 0.45 switches/ms - acceptable for real-time control (10 Hz operation)
```

---

### cpu-migrations

**Explanation**: Counts the number of times a thread was migrated from one CPU core to another. CPU migrations are expensive because they invalidate the thread's cache state on the new core. High migration counts indicate poor thread affinity or scheduler thrashing. Well-designed real-time systems pin threads to cores to avoid migrations. This metric reflects system design and workload characteristics.

**Commonly Used With**:
- `context-switches` - Migrations often happen during context switches
- `cache-misses` - Migrations cause cache misses on the new core
- `task-clock` - To see if migrations impact execution time

**Example**:
```bash
perf stat -e cpu-migrations,cache-misses ./autonomous_emergency_braking

# Output interpretation:
# 2 cpu-migrations
# 12,345 cache-misses
# Very low migrations - critical for real-time safety node
```

---

### page-faults

**Explanation**: Counts total page faults (minor + major). A page fault occurs when a program accesses a memory page not currently in physical RAM. Minor faults are cheap (page is in memory but not mapped); major faults require disk I/O. High page fault counts indicate large memory footprint, memory access patterns that span many pages, or memory pressure. This is algorithm/dataset dependent: processing large point clouds or maps causes many page faults.

**Commonly Used With**:
- `major-faults` - To distinguish expensive vs. cheap faults
- `minor-faults` - To see mapping overhead
- `dTLB-load-misses` - Page faults often follow TLB misses

**Example**:
```bash
perf stat -e page-faults,major-faults,minor-faults ./pointcloud_map_loader

# Output interpretation:
# 12,345 page-faults
# 0 major-faults  
# 12,345 minor-faults
# All minor - good, map loaded but not fully mapped yet
```

---

### major-faults

**Explanation**: Counts major page faults - page faults that require reading data from disk (swap or memory-mapped files). Major faults are extremely expensive (milliseconds of latency). High major fault counts indicate insufficient RAM, forcing the OS to page to disk. For real-time systems, major faults are unacceptable. This metric reflects system memory pressure more than algorithm design.

**Commonly Used With**:
- `page-faults` - To calculate major fault ratio
- `task-clock` - Major faults dramatically increase execution time
- `cache-misses` - After major fault, data must load through cache hierarchy

**Example**:
```bash
perf stat -e major-faults,page-faults ./ndt_scan_matcher

# Output interpretation:
# 0 major-faults
# 1,234 page-faults
# Perfect - no disk I/O, all data in RAM (critical for real-time)
```

---

### minor-faults

**Explanation**: Counts minor page faults - faults where the page is in RAM but not yet mapped to the process's address space. Minor faults are relatively cheap (few microseconds) but still measurable. Common during process startup (demand paging) or when accessing memory-mapped files. High minor fault counts during steady-state execution indicate dynamic memory allocation patterns.

**Commonly Used With**:
- `page-faults` - Minor faults are typically the majority
- `major-faults` - To ensure faults are not disk I/O bound
- `task-clock` - To measure page mapping overhead

**Example**:
```bash
perf stat -e minor-faults,page-faults ./mission_planner

# Output interpretation:
# 234 minor-faults
# 234 page-faults
# All faults are minor - normal for graph data structure allocation
```

---

### cpu-clock

**Explanation**: Measures actual CPU time in nanoseconds that the program used. This is wall-clock time minus time spent sleeping, waiting for I/O, or blocked. CPU clock time reflects actual computation time. For comparing algorithms, use CPU clock rather than wall-clock time to avoid measuring I/O or synchronization overhead. This is the fundamental "how long did the algorithm take" metric.

**Commonly Used With**:
- `task-clock` - Often identical, measures CPU time
- `instructions` - To calculate instructions per second
- `cpu-cycles` - To convert time to cycles

**Example**:
```bash
perf stat -e cpu-clock,instructions ./euclidean_cluster

# Output interpretation:
# 45.678 ms cpu-clock
# 123,456,789 instructions
# 2.7 billion instructions/second - execution rate
```

---

### task-clock

**Explanation**: Measures task CPU time in milliseconds. Essentially the same as `cpu-clock` but reported in milliseconds for convenience. This is the primary metric for execution time. Lower task-clock means faster execution. Compare task-clock across different algorithms to determine which is more efficient for the same task.

**Commonly Used With**:
- `instructions` - To measure MIPS (millions of instructions per second)
- `cpu-cycles` - To see if execution is cycle-bound
- `cache-misses` - To see if execution is memory-bound

**Example**:
```bash
perf stat -e task-clock,instructions,cache-misses ./shape_estimation

# Output interpretation:
# 12.345 ms task-clock
# 50,000,000 instructions
# 1,234 cache-misses
# 4050 MIPS - compute-bound (low cache misses relative to time)
```

---

### duration_time

**Explanation**: Measures total elapsed wall-clock time in nanoseconds from start to finish. This includes CPU time plus waiting time (I/O, synchronization, sleeping). For single-threaded programs, duration_time ≈ task-clock. For multi-threaded or I/O-bound programs, duration_time > task-clock. Use this to measure overall latency, but use task-clock to measure computational efficiency.

**Commonly Used With**:
- `task-clock` - To calculate CPU utilization (task-clock / duration_time)
- `context-switches` - High switches increase duration vs. CPU time
- All metrics - duration_time is the baseline measurement window

**Example**:
```bash
perf stat -e duration_time,task-clock,context-switches ./velocity_smoother

# Output interpretation:
# 15.678 ms duration_time
# 14.234 ms task-clock
# CPU utilization: 90.8% - mostly compute, some blocking
```

---

### alignment-faults

**Explanation**: Counts misaligned memory accesses that caused CPU faults. Modern CPUs require data to be aligned to natural boundaries (e.g., 4-byte int at address divisible by 4). Misaligned accesses are either handled in hardware (slow) or cause faults (very slow). High alignment fault counts indicate incorrect data structure layout or type-punning. Well-written code should have zero alignment faults. This reflects code quality.

**Commonly Used With**:
- `instructions` - Alignment faults can add significant overhead
- `emulation-faults` - Both indicate code quality issues
- `L1-dcache-load-misses` - Misalignment can cause cache inefficiency

**Example**:
```bash
perf stat -e alignment-faults,instructions ./lidar_centerpoint

# Output interpretation:
# 0 alignment-faults
# 500,000,000 instructions
# Perfect - no alignment issues in optimized neural network code
```

---

### emulation-faults

**Explanation**: Counts instructions that had to be emulated by the OS kernel. This typically happens for deprecated or privileged instructions, or instructions not supported by the hardware. High emulation fault counts indicate either very old code, or incorrect instruction usage. Modern well-written code should have zero emulation faults. This is a code quality metric.

**Commonly Used With**:
- `instructions` - Emulation adds massive overhead (1000× slower)
- `alignment-faults` - Both are code quality issues
- `task-clock` - Emulation dramatically increases execution time

**Example**:
```bash
perf stat -e emulation-faults,instructions ./multi_object_tracker

# Output interpretation:
# 0 emulation-faults
# 100,000,000 instructions
# Good - no instruction emulation needed
```

---

## Summary

These 25 metrics provide insight into algorithm behavior independent of specific hardware:

- **Computational Complexity**: instructions, branches
- **Control Flow**: branch-misses, branch patterns
- **Memory Access Patterns**: cache references/misses at all levels
- **Memory Management**: TLB behavior, page faults
- **System Overhead**: context switches, migrations
- **Execution Time**: cpu-clock, task-clock, duration
- **Code Quality**: alignment/emulation faults

Use these metrics to compare algorithms across different platforms and to identify algorithmic inefficiencies rather than hardware-specific bottlenecks.

