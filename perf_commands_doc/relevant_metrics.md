# Relevant Metrics for Cross-Architecture Algorithm Evaluation

## Introduction

### Purpose

This document provides a curated list of performance metrics for evaluating algorithms across different hardware architectures. The goal is to measure **algorithm properties** (computational complexity, memory access patterns, control flow) rather than hardware-specific characteristics, enabling fair comparison of algorithmic efficiency independent of the underlying platform.

### Methodology

We use **ARM Cortex-A78-specific performance counters** available on the Nvidia Jetson Orin AGX to measure universal algorithm properties. While the measurement method is ARM-specific, the metrics themselves reflect architecture-agnostic algorithm characteristics. For example:
- `br_mis_pred` (ARM-specific counter) measures branch mispredictions, a universal concept applicable to all CPUs
- `l1d_cache_refill` (ARM-specific) measures L1 data cache misses, which occur on all architectures regardless of cache size

### Reading Guide

**Criticality Levels**:
- **Essential**: Must-measure metrics for any algorithm evaluation. These form the baseline for algorithm comparison.
- **Important**: Valuable metrics for comprehensive analysis. Provide deeper insights into specific performance aspects.
- **Supplementary**: Specialized metrics for specific use cases or advanced analysis.

**Comments Structure**:
Each metric includes two comment sections:
1. **Basic Info - Portability Considerations**: ARM Cortex-A78 implementation details and general cross-architecture guidance
2. **Research-Heavy - Cross-Architecture Analysis**: Detailed comparison across ARM generations, x86 implementations, RISC vs CISC considerations, and quantitative portability guidance

### Target Use Case

Build a **performance model** to predict algorithm behavior on future architectures based on measurements from Jetson Orin AGX. The selected metrics balance architecture-agnostic interpretability with measurement accuracy.

---

## A. Instruction & Execution Metrics

**Category Overview**: These metrics measure the fundamental computational work performed by the algorithm. Instruction count is the most universal metric - all CPUs execute instructions. Cycle count and Instructions Per Cycle (IPC) provide efficiency insights but require normalization for cross-architecture comparison.

---

### instructions / inst_retired

**Generic**: `instructions`  
**ARM Cortex-A78**: `armv8_cortex_a78/inst_retired/`  
**Criticality**: **Essential**

**Explanation**: Counts the total number of instructions retired (successfully executed and committed). This is the most fundamental metric for algorithmic complexity - it directly reflects the amount of work the algorithm performs. Higher instruction counts indicate more computational complexity. This metric is architecture-agnostic because all processors execute instructions, regardless of their internal pipeline design. It's the best proxy for algorithm efficiency: fewer instructions typically mean a more efficient algorithm for the same task.

**Commonly Used With**:
- `cpu-cycles` / `cpu_cycles` - To calculate Instructions Per Cycle (IPC)
- `task-clock` - To calculate instructions per second
- `cache-misses` / `l3d_cache_refill` - To understand if high instruction count correlates with memory bottlenecks

**Example**:
```bash
perf stat -e armv8_cortex_a78/inst_retired/,armv8_cortex_a78/cpu_cycles/ ./ndt_scan_matcher

# Output interpretation:
# 10,000,000,000 inst_retired
# 5,000,000,000 cpu_cycles
# IPC: 2.0 - excellent instruction-level parallelism
# If processing 100K points: 100,000 instructions/point
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78 is a RISC architecture with fixed 32-bit instruction length (or 16-bit Thumb-2)
- ARM instructions are simpler and more uniform than x86 CISC instructions
- Direct comparison: Instruction counts are comparable across architectures when the **same algorithm and compiler optimization level** are used
- Typical range for ARM: RISC tends to have 20-40% more instructions than x86 for equivalent code due to simpler instruction set

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**: A57 → A72 → A78 all use ARMv8-A ISA (instruction set unchanged). Instruction count remains identical for same code across these cores.
- **x86 Comparison**: 
  - Intel (Skylake/Cascade Lake): CISC instructions can perform more work per instruction (e.g., memory-to-memory operations)
  - AMD Zen 2/3: Similar to Intel, CISC architecture
  - x86 typically has 20-40% fewer instructions than ARM for same algorithm, but x86 instructions decode into more micro-ops
- **RISC vs CISC**: 
  - RISC (ARM): Simple instructions, typically 1-2 micro-ops each, more instructions total
  - CISC (x86): Complex instructions, can be 1-4+ micro-ops each, fewer instructions total
  - **Key insight**: Compare instruction count × average micro-ops per instruction for true work comparison
- **Microarchitectural Details**: 
  - ARM Cortex-A78: 4-wide superscalar, can retire 4 instructions/cycle
  - Intel Skylake: 4-wide, can retire 4 micro-ops/cycle
  - AMD Zen 3: 4-wide, can retire 4 micro-ops/cycle
- **Quantitative Portability**: 
  - **Directly comparable**: When same compiler (e.g., GCC 11.0) and optimization level (-O3) used
  - **Requires normalization**: When comparing RISC vs CISC (normalize by expected instruction density difference: ARM typically 1.2-1.4× x86)
  - **Invalid comparison**: Different algorithms, different compilers, or vastly different optimization levels
- **Algorithmic Implications**: 
  - Compute-bound algorithms: Instruction count is highly predictive across architectures
  - Memory-bound algorithms: Instruction count less predictive (memory latency dominates)
  - Recommendation: Always report instructions per data element (e.g., instructions/point for NDT) for normalization

---

### cpu-cycles / cpu_cycles

**Generic**: `cpu-cycles` or `cycles`  
**ARM Cortex-A78**: `armv8_cortex_a78/cpu_cycles/`  
**Criticality**: **Essential**

**Explanation**: Counts the total number of CPU clock cycles elapsed during execution. This is hardware-dependent because different CPUs run at different frequencies (GHz). CPU cycles alone don't indicate efficiency - a slow algorithm on a fast CPU might use more cycles than an efficient algorithm on a slow CPU. Use with `instructions` to calculate IPC (Instructions Per Cycle), which is more meaningful. Modern CPUs also have dynamic frequency scaling, so cycle counts vary with clock speed.

**Commonly Used With**:
- `instructions` / `inst_retired` - To calculate IPC (instructions / cycles)
- `task-clock` - To determine average CPU frequency
- `stalled-cycles-frontend` / `stalled-cycles-backend` - To see where cycles are wasted

**Example**:
```bash
perf stat -e armv8_cortex_a78/cpu_cycles/,armv8_cortex_a78/inst_retired/,task-clock ./ndt_scan_matcher

# Output interpretation:
# 5,000,000,000 cpu_cycles
# 10,000,000,000 inst_retired
# 50 ms task-clock
# IPC: 2.0 - excellent instruction-level parallelism
# Effective frequency: 5,000M cycles / 0.05s = 100 GHz? No - 2 GHz CPU with IPC=2.0
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78 on Jetson Orin AGX runs at ~2.0-2.2 GHz (dynamic frequency scaling)
- Cycle count is absolute (not normalized by frequency), so it varies with CPU clock speed
- Key metric for cross-architecture comparison: **IPC (Instructions Per Cycle)**, not raw cycle count
- ARM Cortex-A78: Theoretical max IPC = 4.0 (4-wide superscalar), typical sustained IPC = 1.5-2.5

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**:
  - Cortex-A57: 3-wide superscalar (max IPC 3.0), typical IPC 1.2-1.8
  - Cortex-A72: 3-wide superscalar (max IPC 3.0), improved branch prediction, typical IPC 1.4-2.0
  - Cortex-A78: 4-wide superscalar (max IPC 4.0), improved execution units, typical IPC 1.5-2.5
  - **Progression**: Each generation improves IPC for same algorithm through better scheduling, wider execution, improved predictors
- **x86 Comparison**:
  - Intel Skylake/Cascade Lake: 4-wide retirement (max 4 micro-ops/cycle), typical IPC 2.0-3.0 for compute-bound code
  - AMD Zen 2/3: 4-wide retirement, typical IPC 1.8-2.8
  - x86 tends to achieve higher IPC on compute-bound code due to better cache hierarchies and execution resources
- **RISC vs CISC**:
  - RISC (ARM): Instructions are simpler, IPC tends to be lower (1.5-2.5) but more predictable
  - CISC (x86): Instructions are complex, IPC can be higher (2.0-3.0) but more variable depending on instruction mix
  - **Key insight**: IPC × frequency = instructions/second is the fair comparison metric
- **Microarchitectural Details**:
  - ARM Cortex-A78: 128-entry reorder buffer, 4-wide dispatch, 8 execution ports
  - Intel Skylake: 224-entry reorder buffer, 4-wide retirement, 8 execution ports
  - Larger reorder buffer (Intel) allows finding more instruction-level parallelism → higher IPC
- **Quantitative Portability**:
  - **IPC is directly comparable** across architectures for same algorithm/compiler
  - Expected ranges: Compute-bound (IPC 1.5-3.0), Memory-bound (IPC 0.3-1.0), Branch-heavy (IPC 1.0-2.0)
  - **Cycle count is NOT comparable** - must normalize by frequency
  - Formula: Time = Cycles / Frequency, so compare Time × Frequency = Cycles across platforms
- **Algorithmic Implications**:
  - High IPC (>2.0): Algorithm has good instruction-level parallelism, few dependencies
  - Low IPC (<1.0): Algorithm is memory-bound or has many data dependencies
  - Use IPC to identify bottlenecks: Low IPC + high cache misses = memory-bound

---

### branches / br_retired

**Generic**: `branches` or `branch-loads`  
**ARM Cortex-A78**: `armv8_cortex_a78/br_retired/`  
**Criticality**: **Important**

**Explanation**: Counts total branch instructions executed (conditional branches, function calls, returns). This reflects control flow complexity - algorithms with many conditionals, loops, or function calls will have high branch counts. Simple, straight-line code has few branches. Branch density (branches per instruction) indicates code structure: procedural code with many function calls has high branch density, while vectorized or loop-unrolled code has lower branch density.

**Commonly Used With**:
- `branch-misses` / `br_mis_pred` - To calculate branch prediction accuracy
- `instructions` / `inst_retired` - To calculate branch density (branches/instructions)
- `branch-load-misses` - Cache-specific branch behavior

**Example**:
```bash
perf stat -e armv8_cortex_a78/br_retired/,armv8_cortex_a78/inst_retired/ ./behavior_path_planner

# Output interpretation:
# 1,900,000 br_retired
# 10,000,000 inst_retired
# Branch density: 19% - typical for C++ code with many function calls
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78 counts all branch types: conditional, unconditional, calls, returns, indirect
- Branch density is architecture-agnostic: Same algorithm has similar branch density across platforms
- Typical branch densities: Procedural code (15-25%), Tight loops (5-10%), Object-oriented C++ (20-30%)
- ARM RISC architecture typically has higher branch density than x86 CISC due to lack of predicated execution in modern ARM

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**:
  - ARMv7 (A15): Had predicated execution (conditional instruction execution without branches)
  - ARMv8 (A57/A72/A78): Removed most predicated execution, increased branch density by ~10-20%
  - A78: Improved branch predictor compensates for increased branch density
- **x86 Comparison**:
  - x86 has conditional move (CMOV) instructions that reduce branch density by ~5-15%
  - Intel/AMD: Similar branch density to ARM for same high-level code (15-25%)
  - Difference mostly in compiler code generation strategies
- **RISC vs CISC**:
  - RISC (ARM): Lack of conditional execution means more branches
  - CISC (x86): CMOV and SETCC instructions can eliminate branches
  - Compilers aggressively use branch-free code paths on both architectures
  - **Net effect**: Branch density differs by <20% for same algorithm
- **Microarchitectural Details**:
  - ARM Cortex-A78: Branch predictor handles ~2 branches/cycle (4-wide fetch)
  - Branch density >25% can become a bottleneck (front-end supply limit)
- **Quantitative Portability**:
  - **Branch density (branches/instructions) is directly comparable** across architectures
  - Expected ranges: 10-30% for most algorithms
  - **Absolute branch count needs instruction count normalization** (RISC has more instructions)
- **Algorithmic Implications**:
  - High branch density (>25%): Consider loop unrolling, vectorization, or branchless techniques
  - Control-flow intensive algorithms (state machines): Branch density 30-40%
  - Data-parallel algorithms: Branch density <10%

---

### branch-misses / br_mis_pred

**Generic**: `branch-misses`  
**ARM Cortex-A78**: `armv8_cortex_a78/br_mis_pred/`  
**Criticality**: **Essential**

**Explanation**: Counts the number of branch mispredictions - cases where the CPU's branch predictor guessed wrong about which way a conditional branch would go. Branch misses are expensive because the CPU must flush its pipeline and restart from the correct path. High branch miss rates indicate unpredictable control flow (many if/else statements, switch cases, or loop conditions that vary). This metric is algorithm-dependent: algorithms with regular, predictable branches (like simple loops) have low miss rates, while algorithms with data-dependent branching (like tree traversals, sorting) have higher miss rates.

**Commonly Used With**:
- `branches` / `br_retired` - To calculate branch miss rate (misses/total branches)
- `instructions` / `inst_retired` - To see if branch misses dominate execution time
- `cpu-cycles` / `cpu_cycles` - Branch misses add cycles due to pipeline flushes

**Example**:
```bash
perf stat -e armv8_cortex_a78/br_mis_pred/,armv8_cortex_a78/br_retired/ ./multi_object_tracker

# Output interpretation:
# 12,345 br_mis_pred
# 1,234,567 br_retired
# Miss rate: 1.0% - excellent for state machine code
# High miss rates (>5%) suggest unpredictable branching (e.g., data-dependent decisions)
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78 uses **TAGE (Tagged Geometric History Length) branch predictor**
- TAGE is a state-of-the-art predictor with multiple history tables (geometric length progression)
- Branch misprediction penalty on A78: ~11-14 cycles (pipeline depth dependent)
- Typical miss rates: Simple loops (<1%), Complex control flow (2-5%), Data-dependent (>5%)

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**:
  - Cortex-A57: 2-level adaptive predictor, typical miss rate 3-6% for complex code
  - Cortex-A72: Improved TAGE-based predictor, miss rate 2-4%
  - Cortex-A78: Advanced TAGE with longer history, miss rate 1-3%
  - **Progression**: Each generation reduces miss rate by ~0.5-1% through better history tracking
- **x86 Comparison**:
  - Intel (Skylake): TAGE-SC-L (TAGE + Statistical Corrector + Loop predictor), miss rate 1-2.5%
  - AMD (Zen 3): Perceptron-based hybrid predictor, miss rate 1.5-3%
  - **Key difference**: Intel's TAGE-SC-L is most advanced (championship predictor), ~0.5-1% better than ARM A78
- **RISC vs CISC**:
  - Prediction accuracy is architecture-independent (depends on predictor algorithm, not RISC/CISC)
  - **Critical insight**: x86 may have fewer branches (CMOV), but predictor quality matters more than branch count
- **Microarchitectural Details**:
  - ARM A78 TAGE: ~8-12 prediction tables, history length up to 640 branches
  - Intel TAGE-SC-L: ~12-16 tables, history up to 1000+ branches, statistical corrector reduces pathological cases
  - Misprediction penalty: ARM A78 (~13 cycles), Intel Skylake (~16-20 cycles), AMD Zen 3 (~17-19 cycles)
- **Quantitative Portability**:
  - **Miss rate (misses/branches) is comparable** across architectures with similar predictors
  - **Absolute miss counts are NOT directly comparable** due to different predictors and branch densities
  - **Normalization**: Express as "mispredictions per kilo-instruction" (MPKI) for architecture-agnostic comparison
  - Expected MPKI: Predictable code (<5 MPKI), Complex code (5-20 MPKI), Highly unpredictable (>20 MPKI)
  - **Performance impact varies by misprediction penalty**: ARM penalty lower (13 cycles) vs x86 (17-20 cycles)
- **Algorithmic Implications**:
  - Predictor-agnostic optimization: Make branches more predictable (loop invariants, data sorting)
  - Predictor-aware optimization: Intel/ARM TAGE works well with correlated branches; keep branch outcomes consistent
  - **Cross-platform recommendation**: Target <2% miss rate regardless of platform
  - Data-dependent branches (tree traversal, hash tables): Expect 5-15% miss rate even with best predictors

---

## B. Cache & Memory Hierarchy

**Category Overview**: Cache and memory metrics are critical for understanding memory access patterns and data locality. While cache sizes vary dramatically across architectures (ARM A78: 64KB L1, x86: 32KB L1), the **miss rates** and **misses per kilo-instruction (MPKI)** are architecture-agnostic algorithm properties. These metrics identify memory-bound algorithms and guide locality optimizations.

---

### cache-misses / l3d_cache_refill

**Generic**: `cache-misses`  
**ARM Cortex-A78**: `armv8_cortex_a78/l3d_cache_refill/` or generic `cache-misses`  
**Criticality**: **Essential**

**Explanation**: Counts the number of last-level cache (LLC) misses that result in main memory access. This is the most expensive memory operation - missing LLC means going to DRAM which is 100-300 cycles of latency. High cache miss counts indicate poor data locality: the algorithm accesses data in random patterns, or the working set exceeds available cache. This metric is algorithm-dependent: sequential access patterns have low miss rates, while pointer-chasing or hash table lookups have high miss rates.

**Commonly Used With**:
- `cache-references` / `l3d_cache` - To calculate miss rate
- `instructions` / `inst_retired` - Misses per kilo-instruction (MPKI) is a key metric
- `task-clock` - To estimate time spent waiting for memory

**Example**:
```bash
perf stat -e armv8_cortex_a78/l3d_cache_refill/,armv8_cortex_a78/inst_retired/ ./ndt_scan_matcher

# Output interpretation:
# 45,678 l3d_cache_refill (LLC misses)
# 10,000,000 inst_retired
# MPKI: 4.57 - moderate, voxel hash lookups cause misses
# At 300 cycles/miss: 45,678 × 300 = 13.7M cycles wasted on memory
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78 on Jetson Orin: L3 system cache (shared), size varies by SKU (typically 2-4 MB)
- LLC miss = main memory access, ~200-300 cycles latency on DDR5/LPDDR5
- **MPKI (Misses Per Kilo-Instruction) is architecture-agnostic**: Same algorithm has similar MPKI regardless of cache size
- Typical MPKI ranges: Excellent (<1), Good (1-5), Moderate (5-10), Poor (>10)

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**:
  - Cortex-A57: L2 cache (512KB-2MB) as LLC, miss latency ~40-60 cycles to external memory controller
  - Cortex-A72: L2 cache improved prefetcher, ~10-15% fewer misses for streaming workloads
  - Cortex-A78: L3 system cache (2-4MB), miss latency ~50-80 cycles to memory controller + ~200 cycles DRAM
  - **Key change**: A78 introduced shared L3, reducing LLC miss rate by ~20-30% for multi-core workloads
- **x86 Comparison**:
  - Intel (Skylake/Cascade Lake): L3 LLC (8-32MB), miss latency ~60-80 cycles + ~180-220 cycles DRAM
  - AMD (Zen 3): L3 LLC (16-32MB), miss latency ~40-50 cycles + ~180-200 cycles DRAM
  - **Cache size impact**: x86 L3 is 4-8× larger than ARM, resulting in ~30-50% fewer LLC misses for same algorithm
  - **Critical insight**: Larger caches reduce absolute miss count, but MPKI ratio remains similar for random-access patterns
- **RISC vs CISC**:
  - Cache behavior is architecture-independent (depends on algorithm memory access patterns)
  - x86 may have advantage in cache-conscious code due to larger L3, but MPKI converges for large working sets
- **Microarchitectural Details**:
  - ARM A78 L3: Shared across cores, typically 16-way set associative, 64-byte cache lines
  - Intel L3: Inclusive (also holds L1/L2 contents), non-uniform cache access (NUCA) for large caches
  - AMD L3: Victim cache (holds evicted L2 data), exclusive design
  - **Inclusive vs Exclusive**: Affects absolute miss counts, but MPKI remains comparable for same working set
- **Quantitative Portability**:
  - **MPKI is directly comparable** across all architectures (accounts for instruction count differences)
  - **Absolute miss count varies** with cache size (larger cache = fewer misses)
  - **Miss rate varies** with cache size, but working set locality is universal
  - **Formula**: Expected misses on target platform = MPKI × (instructions on target) / 1000
  - **Normalization**: For cache size differences, use working set size / cache size ratio
- **Algorithmic Implications**:
  - MPKI <1: Algorithm has excellent locality, cache-friendly
  - MPKI 1-10: Moderate locality, optimization possible
  - MPKI >10: Poor locality, memory-bound, needs fundamental algorithmic changes
  - **Cross-platform optimization**: Target MPKI <5 for portable performance
  - Cache-oblivious algorithms: Design for unknown cache size (divide-and-conquer, blocking)

---

### cache-references / l3d_cache

**Generic**: `cache-references`  
**ARM Cortex-A78**: `armv8_cortex_a78/l3d_cache/` or generic `cache-references`  
**Criticality**: **Essential**

**Explanation**: Counts the total number of last-level cache (LLC) accesses. This reflects the working set size and memory access patterns of the algorithm. High cache reference counts indicate the algorithm is accessing a large amount of data that doesn't fit in lower-level caches. This is architecture-agnostic in the sense that it measures "how much data is the algorithm touching" rather than specific cache sizes. Algorithms with good spatial and temporal locality will have fewer cache references because data stays in L1/L2 caches.

**Commonly Used With**:
- `cache-misses` / `l3d_cache_refill` - To calculate LLC hit rate
- `instructions` / `inst_retired` - To measure data access intensity (cache refs per instruction)
- `L1-dcache-load-misses` / `l1d_cache_refill` - To understand cache hierarchy behavior

**Example**:
```bash
perf stat -e armv8_cortex_a78/l3d_cache/,armv8_cortex_a78/l3d_cache_refill/ ./euclidean_cluster

# Output interpretation:
# 100,000 l3d_cache (LLC accesses)
# 10,000 l3d_cache_refill (LLC misses)
# LLC hit rate: 90% - good locality for voxel grid access pattern
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78: LLC accesses occur when data misses L1/L2 caches
- LLC hit rate = (references - misses) / references is architecture-agnostic
- Good hit rates: >85%, Moderate: 70-85%, Poor: <70%
- High LLC access count indicates working set > L1+L2 size (~320KB on A78)

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**:
  - A57/A72: L2 as LLC, typical hit rate 80-90% for working sets <2MB
  - A78: L3 as LLC, typical hit rate 85-95% for working sets <4MB
- **x86 Comparison**:
  - Larger L3 (8-32MB) results in higher hit rates (90-98%) for same algorithm
  - LLC access rate (refs/instruction) remains similar across architectures
- **RISC vs CISC**: LLC access patterns are architecture-independent
- **Quantitative Portability**:
  - **LLC hit rate is comparable** when working set << cache size
  - **Hit rate diverges** when working set approaches cache size (larger x86 L3 has advantage)
  - **LLC accesses per instruction is directly comparable** across architectures
- **Algorithmic Implications**:
  - High LLC access rate (>0.1 refs/instruction): Memory-intensive algorithm
  - Target LLC hit rate >85% for predictable performance across platforms

---

### L1-dcache-load-misses / l1d_cache_refill

**Generic**: `L1-dcache-load-misses`  
**ARM Cortex-A78**: `armv8_cortex_a78/l1d_cache_refill/`  
**Criticality**: **Essential**

**Explanation**: Counts L1 data cache misses - load operations that had to fetch from L2 cache or lower. L1 misses indicate the algorithm's data access pattern doesn't match L1 cache size/associativity. Small working sets with good locality have few L1 misses. Large working sets, strided access, or pointer-chasing cause many L1 misses. This metric reflects algorithm memory access patterns independent of specific L1 implementation.

**Commonly Used With**:
- `L1-dcache-loads` / `l1d_cache` - To calculate L1 miss rate
- `l2d_cache_refill` - To see where misses go (L2 hits vs L2 misses)
- `cache-misses` / `l3d_cache_refill` - To understand full cache hierarchy behavior

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1d_cache_refill/,armv8_cortex_a78/l1d_cache/ ./occupancy_grid_map

# Output interpretation:
# 340,000 l1d_cache_refill (L1D misses)
# 5,000,000 l1d_cache (L1D accesses)
# Miss rate: 6.8% - acceptable for scattered grid updates
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78: L1D cache 64KB, 4-way set associative, 64-byte lines
- L1 miss latency: ~10-14 cycles (L2 hit), ~200-300 cycles (memory)
- **L1 miss rate is comparable** across architectures for same access pattern
- Typical miss rates: Sequential (<2%), Random (5-15%), Pointer-chasing (>15%)

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**:
  - A57: 32KB L1D (2-way), typical miss rate 5-12% for random access
  - A72: 32KB L1D (2-way), improved prefetcher, miss rate 4-10%
  - A78: 64KB L1D (4-way), advanced prefetcher, miss rate 3-8%
  - **Impact**: Larger L1D (64KB vs 32KB) reduces miss rate by ~30-40%
- **x86 Comparison**:
  - Intel/AMD: 32KB L1D (8-way), typical miss rate 4-10%
  - **ARM advantage**: A78's 64KB L1D has ~20-30% lower miss rate than x86 32KB
  - Higher associativity (x86 8-way vs ARM 4-way) partially compensates for smaller size
- **RISC vs CISC**: L1 behavior is architecture-independent (depends on access pattern)
- **Microarchitectural Details**:
  - Associativity impact: 4-way (ARM) suffers more from conflict misses than 8-way (x86)
  - Prefetcher: Both ARM and x86 have stride prefetchers; ARM A78 can detect 3 streams, Intel can detect 16
  - **Net effect**: Miss rate for streaming is similar; random access favors larger cache (ARM)
- **Quantitative Portability**:
  - **L1 miss rate is comparable** for algorithms with working set << 32KB
  - **Miss rate diverges** for working sets 32-64KB (ARM has advantage)
  - **MPKI (L1 misses per kilo-instruction) is directly comparable**
  - Expected L1 MPKI: Excellent (<10), Good (10-30), Moderate (30-80), Poor (>80)
- **Algorithmic Implications**:
  - L1 miss rate >10%: Consider data structure layout (array-of-structures vs structure-of-arrays)
  - Strided access: Ensure stride < 64 bytes (cache line size) for prefetcher effectiveness
  - **Cross-platform target**: L1 miss rate <5% for portable performance

---

### L1-dcache-loads / l1d_cache

**Generic**: `L1-dcache-loads`  
**ARM Cortex-A78**: `armv8_cortex_a78/l1d_cache/`  
**Criticality**: **Essential**

**Explanation**: Counts load operations from L1 data cache. This reflects memory read intensity - how often the algorithm reads data from memory. High L1 cache load counts indicate a data-intensive algorithm. This is relatively architecture-agnostic because it measures "how many data reads" rather than L1 cache size or implementation. Compare across algorithms: matrix operations have very high L1 loads, while compute-bound code (lots of arithmetic, few memory operations) has lower L1 loads.

**Commonly Used With**:
- `L1-dcache-load-misses` / `l1d_cache_refill` - To calculate L1 hit rate
- `instructions` / `inst_retired` - To measure memory vs. compute ratio
- `mem_access` - Total memory operations (ARM-specific)

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1d_cache/,armv8_cortex_a78/inst_retired/ ./shape_estimation

# Output interpretation:
# 3,456,789 l1d_cache (L1D accesses)
# 10,000,000 inst_retired
# Memory intensity: 34.6% - data-intensive (matrix operations in PCA)
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78 counts all L1D accesses (reads and writes)
- Memory intensity (loads per instruction) is architecture-agnostic
- Typical ratios: Compute-bound (<20%), Balanced (20-40%), Memory-bound (>40%)
- Note: ARM `l1d_cache` includes both loads and stores, while generic `L1-dcache-loads` is loads only

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**: A57 → A72 → A78 all have similar L1D access rates for same code (no ISA change)
- **x86 Comparison**:
  - RISC (ARM) may have slightly higher load rate due to load/store architecture
  - CISC (x86) has memory-to-memory operations, fewer explicit loads
  - **Net difference**: ARM typically 10-20% more L1D accesses for same algorithm
- **RISC vs CISC**:
  - RISC load/store: All operations on registers, explicit memory loads
  - CISC: Operations can have memory operands, fewer explicit loads
  - **Example**: x86 `ADD [mem], reg` = ARM `LDR + ADD + STR` (3 memory ops)
- **Quantitative Portability**:
  - **Loads per instruction is comparable** when normalized for RISC/CISC
  - **Formula**: ARM_loads ≈ x86_loads × 1.15 (RISC overhead)
  - **Direct comparison**: Use memory intensity = loads / (loads + compute_instructions)
- **Algorithmic Implications**:
  - High memory intensity (>40%): Algorithm is memory-bound, focus on cache optimization
  - Low memory intensity (<20%): Algorithm is compute-bound, focus on instruction optimization
  - **Cross-platform**: Memory intensity ratio is more portable than absolute load counts

---


### L1-icache-load-misses / l1i_cache_refill

**Generic**: `L1-icache-load-misses`  
**ARM Cortex-A78**: `armv8_cortex_a78/l1i_cache_refill/`  
**Criticality**: **Important**

**Explanation**: Counts L1 instruction cache misses - instruction fetches that missed L1 and had to fetch from L2 or lower. I-cache misses indicate large code footprint that doesn't fit in L1, or poor code locality (jumping between distant functions). Algorithms with many small functions called infrequently will have higher I-cache misses than algorithms with tight loops.

**Commonly Used With**:
- `L1-icache-loads` / `l1i_cache` - To calculate miss rate
- `branch-load-misses` - Related to function call patterns
- `instructions` / `inst_retired` - Instruction fetch efficiency

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1i_cache_refill/,armv8_cortex_a78/l1i_cache/ ./behavior_path_planner

# Output interpretation:
# 5,678 l1i_cache_refill (I-cache misses)
# 20,000,000 l1i_cache (I-cache accesses)
# Miss rate: 0.028% - modular scene architecture but good locality
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78: L1I cache 64KB, 4-way set associative
- I-cache miss latency: ~10-14 cycles (L2 hit)
- Typical miss rates: Tight loops (<0.1%), Modular code (0.1-1%), Large codebases (>1%)
- I-cache behavior is architecture-agnostic for same code structure

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**:
  - A57/A72: 32KB L1I, miss rate 0.2-1.5% for complex C++ code
  - A78: 64KB L1I, miss rate 0.1-0.8% (50% reduction)
- **x86 Comparison**:
  - Intel/AMD: 32KB L1I (8-way), miss rate 0.15-1.0%
  - ARM A78 advantage: 64KB vs 32KB reduces misses by ~40%
- **RISC vs CISC**:
  - RISC (ARM): Fixed 32-bit instructions, predictable I-cache usage
  - CISC (x86): Variable-length instructions (1-15 bytes), less predictable
  - **Net effect**: Similar I-cache miss rates for same code complexity
- **Quantitative Portability**:
  - **I-cache miss rate is directly comparable** across architectures
  - **MPKI (I-cache misses per kilo-instruction)** is the best cross-platform metric
  - Expected I-cache MPKI: Excellent (<1), Good (1-5), Poor (>5)
- **Algorithmic Implications**:
  - I-cache miss rate >0.5%: Consider function inlining, code layout optimization
  - Large template-heavy C++: Expect 1-2% miss rate due to code bloat
  - **Cross-platform target**: <0.5% miss rate for portable performance

---

### L1-icache-loads / l1i_cache

**Generic**: `L1-icache-loads`  
**ARM Cortex-A78**: `armv8_cortex_a78/l1i_cache/`  
**Criticality**: **Important**

**Explanation**: Counts instruction fetches from L1 instruction cache. This reflects code size and instruction fetch patterns. High I-cache loads indicate large code footprint or many function calls. Tight loops with small code have few I-cache loads (instructions are cached and reused). Large switch statements, many inline functions, or template-heavy C++ code increase I-cache loads.

**Commonly Used With**:
- `L1-icache-load-misses` / `l1i_cache_refill` - To calculate instruction cache hit rate
- `instructions` / `inst_retired` - Some instructions reuse cached data
- `branch-loads` / `br_retired` - Function calls cause instruction fetches

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1i_cache/,armv8_cortex_a78/l1i_cache_refill/ ./mission_planner

# Output interpretation:
# 2,000,000 l1i_cache (I-cache accesses)
# 1,000 l1i_cache_refill (I-cache misses)
# Miss rate: 0.05% - excellent, tight Dijkstra loop
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78: 4-wide instruction fetch (fetch 4 instructions per cycle)
- I-cache access rate reflects code reuse and loop structure
- Typical patterns: Tight loops (high reuse), Function-heavy code (low reuse)

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**: A57 → A78 all have similar I-cache access patterns for same code
- **x86 Comparison**: CISC variable-length instructions may have different fetch patterns
- **Quantitative Portability**:
  - **I-cache accesses per instruction** varies with fetch width and instruction reuse
  - **I-cache hit rate is directly comparable** across architectures
- **Algorithmic Implications**:
  - Monitor I-cache access rate relative to instruction count
  - High access rate with low miss rate indicates good code locality

---

### l2d_cache / l2d_cache_refill

**Generic**: N/A (ARM-specific)  
**ARM Cortex-A78**: `armv8_cortex_a78/l2d_cache/` and `armv8_cortex_a78/l2d_cache_refill/`  
**Criticality**: **Important**

**Explanation**: ARM Cortex-A78 count of L2 cache accesses and refills. L2 is accessed on L1 misses. High L2 access counts indicate working set exceeds L1 but may fit in L2. L2 refills (L2 misses) indicate working set exceeds L2 capacity. ARM-specific L2 cache monitoring provides intermediate cache level insights.

**Commonly Used With**:
- `l1d_cache_refill` - L1 misses feed into L2 accesses
- `l3d_cache` / `cache-references` - L2 misses feed into L3 accesses
- `instructions` / `inst_retired` - For L2 MPKI calculation

**Example**:
```bash
perf stat -e armv8_cortex_a78/l2d_cache/,armv8_cortex_a78/l2d_cache_refill/ ./euclidean_cluster

# Output interpretation:
# 500,000 l2d_cache (L2 accesses)
# 50,000 l2d_cache_refill (L2 misses)
# L2 hit rate: 90% - working set fits mostly in L2
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78: L2 cache 256-512KB (implementation dependent), 8-way set associative
- L2 hit latency: ~10-14 cycles, L2 miss latency: ~50-80 cycles (to L3) + memory
- L2 hit rate is architecture-agnostic for same working set relative to cache size

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**:
  - A57: 512KB-2MB L2 (also LLC on A57)
  - A72: 512KB-4MB L2, improved prefetcher
  - A78: 256-512KB L2 (private per core) + shared L3
  - **Change**: A78 moved to smaller private L2 + larger shared L3 architecture
- **x86 Comparison**:
  - Intel: 256KB-1MB private L2 per core
  - AMD Zen 3: 512KB private L2 per core
  - **Similar architecture**: Both ARM and x86 use private L2 + shared L3
- **Quantitative Portability**:
  - **L2 hit rate is comparable** when working set < smallest L2 size (256KB)
  - **L2 MPKI is directly comparable** across architectures
  - Expected L2 MPKI: Excellent (<5), Good (5-20), Poor (>20)
- **Algorithmic Implications**:
  - L2 hit rate <80%: Working set exceeds L2, focus on L3/memory optimization
  - Target working set <256KB for portable L2 performance

---

### LLC-loads / ll_cache_rd, LLC-load-misses / ll_cache_miss_rd

**Generic**: `LLC-loads`, `LLC-load-misses`  
**ARM Cortex-A78**: `armv8_cortex_a78/ll_cache_rd/`, `armv8_cortex_a78/ll_cache_miss_rd/`  
**Criticality**: **Important**

**Explanation**: Counts load operations from Last Level Cache (LLC) and LLC read misses. LLC loads occur when data misses in L1 and L2, representing the last chance before main memory. High LLC load counts indicate a working set larger than L1+L2 capacity. LLC misses are identical to `cache-misses` on most systems - the most expensive memory events.

**Commonly Used With**:
- `cache-misses` / `l3d_cache_refill` - Should match LLC-load-misses
- `instructions` / `inst_retired` - For LLC MPKI calculation
- `L1-dcache-load-misses` - To understand cache hierarchy

**Example**:
```bash
perf stat -e armv8_cortex_a78/ll_cache_rd/,armv8_cortex_a78/ll_cache_miss_rd/ ./lidar_centerpoint

# Output interpretation:
# 123,456 ll_cache_rd (LLC loads)
# 45,678 ll_cache_miss_rd (LLC misses)
# LLC hit rate: 63% - neural network weights span L2/L3/memory
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78: LLC is L3 system cache (2-4MB shared)
- LLC hit rate varies significantly with cache size (ARM 2-4MB vs x86 8-32MB)
- **LLC MPKI is the most portable metric** - accounts for cache size differences

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**:
  - A57/A72: L2 as LLC (512KB-2MB), typical LLC MPKI 10-30 for large working sets
  - A78: L3 as LLC (2-4MB), typical LLC MPKI 5-15 (50% reduction)
- **x86 Comparison**:
  - Intel/AMD: 8-32MB L3, typical LLC MPKI 2-8 for same working sets
  - **Critical difference**: x86's larger LLC dramatically reduces absolute miss count
  - **Portable metric**: MPKI remains similar for random-access patterns
- **Quantitative Portability**:
  - **LLC MPKI is directly comparable** - best cross-platform cache metric
  - **Absolute miss counts vary** by 2-4× between ARM (2-4MB L3) and x86 (8-32MB L3)
  - **Formula for prediction**: Target_misses ≈ ARM_MPKI × Target_instructions / 1000
- **Algorithmic Implications**:
  - LLC MPKI <5: Good portability across cache sizes
  - LLC MPKI >10: Performance heavily dependent on LLC size
  - **Design principle**: Optimize for working sets <2MB for portable performance

---

## C. TLB & Virtual Memory

**Category Overview**: Translation Lookaside Buffer (TLB) metrics measure virtual-to-physical address translation efficiency. High TLB miss rates indicate poor page locality - accessing data scattered across many memory pages. TLB behavior is architecture-agnostic (depends on algorithm's spatial locality), though TLB sizes vary across platforms.

---

### dTLB-load-misses / dtlb_walk

**Generic**: `dTLB-load-misses`  
**ARM Cortex-A78**: `armv8_cortex_a78/dtlb_walk/`  
**Criticality**: **Essential**

**Explanation**: Counts data TLB misses - virtual address translations that missed the TLB and required page table walk. TLB misses are expensive (10-100 cycles for page table walk). High TLB miss rates indicate accessing data across many memory pages with poor temporal locality. Algorithms that process large arrays sequentially have low TLB miss rates. Algorithms with pointer-chasing or random access across large memory have high TLB miss rates.

**Commonly Used With**:
- `dTLB-loads` / `l1d_tlb` - To calculate miss rate
- `page-faults` - Related memory management events
- `L1-dcache-load-misses` - TLB and cache misses often correlate

**Example**:
```bash
perf stat -e armv8_cortex_a78/dtlb_walk/,armv8_cortex_a78/l1d_tlb/ ./ndt_scan_matcher

# Output interpretation:
# 1,234 dtlb_walk (TLB misses requiring page walks)
# 3,456,789 l1d_tlb (TLB lookups)
# Miss rate: 0.036% - excellent, NDT voxel grid has good page locality
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78: Two-level TLB (48-entry L1 DTLB, 1024-entry L2 TLB)
- Page table walk latency: ~10-50 cycles (4-level page table)
- Typical miss rates: Sequential access (<0.1%), Random access (0.1-1%), Scattered (>1%)
- TLB miss rate is architecture-agnostic (depends on page access pattern)

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**:
  - A57: 32-entry L1 DTLB, 512-entry L2 TLB, miss rate 0.2-2%
  - A72: 48-entry L1 DTLB, 1024-entry L2 TLB, miss rate 0.1-1%
  - A78: 48-entry L1 DTLB, 1024-entry L2 TLB (same as A72)
  - **Progression**: Larger TLBs reduce miss rate by ~50% across generations
- **x86 Comparison**:
  - Intel: 64-entry L1 DTLB, 1536-entry L2 TLB, typical miss rate 0.05-0.5%
  - AMD Zen 3: 64-entry L1 DTLB, 2048-entry L2 TLB, typical miss rate 0.05-0.4%
  - **x86 advantage**: Larger TLBs result in ~50% fewer TLB misses than ARM for same algorithm
- **RISC vs CISC**: TLB behavior is architecture-independent (depends on page access pattern)
- **Microarchitectural Details**:
  - Page size: 4KB standard (ARM/x86), 2MB huge pages reduce TLB pressure by 512×
  - Page table depth: Both ARM and x86 use 4-level page tables (similar walk latency)
- **Quantitative Portability**:
  - **TLB miss rate is comparable** for algorithms with similar page access patterns
  - **Absolute miss counts vary** with TLB size (x86 ~50% fewer than ARM)
  - **MPKI (TLB misses per kilo-instruction) is directly comparable**
  - Expected dTLB MPKI: Excellent (<0.1), Good (0.1-1), Poor (>1)
- **Algorithmic Implications**:
  - TLB miss rate >0.5%: Consider data layout to improve spatial locality (page-aligned structures)
  - Large working sets (>4MB): Use huge pages (2MB) to reduce TLB pressure by 512×
  - **Cross-platform target**: <0.2% TLB miss rate for portable performance

---

### dTLB-loads / l1d_tlb

**Generic**: `dTLB-loads`  
**ARM Cortex-A78**: `armv8_cortex_a78/l1d_tlb/`  
**Criticality**: **Essential**

**Explanation**: Counts data Translation Lookaside Buffer (TLB) lookups - virtual to physical address translations for data accesses. TLB loads reflect memory access diversity: accessing many different memory pages requires many TLB lookups. Algorithms with poor spatial locality (accessing data scattered across many pages) have high TLB loads relative to cache accesses.

**Commonly Used With**:
- `dTLB-load-misses` / `dtlb_walk` - To calculate TLB hit rate
- `page-faults` - TLB misses can lead to page faults if page not in RAM
- `L1-dcache-loads` / `l1d_cache` - TLB lookups happen on memory access

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1d_tlb/,armv8_cortex_a78/L1-dcache-loads/ ./multi_object_tracker

# Output interpretation:
# 3,456,789 l1d_tlb (TLB lookups)
# 3,456,789 l1d_cache (L1 accesses)
# One TLB lookup per data access - normal for scattered object access
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78: TLB lookup happens for every memory access (unless already in TLB)
- TLB covers virtual-to-physical translation (OS manages page mapping)
- Typical pattern: l1d_tlb ≈ l1d_cache (one TLB lookup per memory access)

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**: TLB lookup rate is identical across ARM generations (ISA-level feature)
- **x86 Comparison**: Similar TLB lookup rate (one per memory access)
- **Quantitative Portability**:
  - **TLB lookups per memory access is always ~1** (architecture-independent)
  - **TLB hit rate is directly comparable** across architectures
- **Algorithmic Implications**:
  - Monitor TLB hit rate (1 - misses/loads) rather than absolute lookup count
  - Target >99.5% TLB hit rate for predictable performance

---

### iTLB-load-misses / itlb_walk

**Generic**: `iTLB-load-misses`  
**ARM Cortex-A78**: `armv8_cortex_a78/itlb_walk/`  
**Criticality**: **Important**

**Explanation**: Counts instruction TLB misses - instruction fetches that missed iTLB and required page table walk. High iTLB miss rates indicate very large code spread across many pages. This is more common in large C++ applications with extensive template usage or dynamic linking.

**Commonly Used With**:
- `iTLB-loads` / `l1i_tlb` - To calculate miss rate
- `L1-icache-load-misses` - Related instruction cache behavior
- `instructions` / `inst_retired` - Instruction TLB efficiency

**Example**:
```bash
perf stat -e armv8_cortex_a78/itlb_walk/,armv8_cortex_a78/l1i_tlb/ ./behavior_path_planner

# Output interpretation:
# 123 itlb_walk (iTLB misses)
# 123,456 l1i_tlb (iTLB lookups)
# Miss rate: 0.1% - compact code footprint
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78: 48-entry L1 iTLB, 1024-entry L2 iTLB
- iTLB miss = page table walk for instruction fetch (~10-50 cycles)
- Typical miss rates: Small programs (<0.05%), Large C++ (0.1-0.5%)

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**: A57 (32-entry) → A72/A78 (48-entry) reduces miss rate by ~30%
- **x86 Comparison**: Intel 64-entry L1 iTLB has ~25% fewer misses than ARM
- **Quantitative Portability**:
  - **iTLB miss rate is directly comparable** across architectures
  - Expected iTLB MPKI: Excellent (<0.05), Good (0.05-0.2), Poor (>0.2)
- **Algorithmic Implications**:
  - iTLB miss rate >0.2%: Code spans too many pages (>200 pages = >800KB)
  - Template-heavy C++: Expect 0.1-0.3% miss rate
  - **Cross-platform target**: <0.1% iTLB miss rate

---

### iTLB-loads / l1i_tlb

**Generic**: `iTLB-loads`  
**ARM Cortex-A78**: `armv8_cortex_a78/l1i_tlb/`  
**Criticality**: **Important**

**Explanation**: Counts instruction TLB lookups - virtual address translations for instruction fetches. High iTLB loads indicate large code footprint across many memory pages. Algorithms with small, tight code have few iTLB loads.

**Commonly Used With**:
- `iTLB-load-misses` / `itlb_walk` - To calculate instruction TLB hit rate
- `L1-icache-loads` / `l1i_cache` - Related instruction fetch behavior
- `branch-loads` / `br_retired` - Function calls to distant code cause iTLB loads

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1i_tlb/,armv8_cortex_a78/L1-icache-loads/ ./velocity_smoother

# Output interpretation:
# 123,456 l1i_tlb (iTLB lookups)
# 1,234,567 l1i_cache (I-cache accesses)
# ~10% of instruction fetches require TLB lookup - moderate code size
```

**Comments**:

*Basic Info - Portability Considerations*:
- iTLB lookup rate depends on code locality and cache line reuse
- Well-localized code: Low iTLB lookup rate (instructions cached, TLB entry reused)

*Research-Heavy - Cross-Architecture Analysis*:
- **Quantitative Portability**: iTLB hit rate >99.5% is standard across all architectures
- **Algorithmic Implications**: Monitor iTLB hit rate rather than absolute lookup count

---

### l1d_tlb_refill, l2d_tlb / l2d_tlb_refill

**Generic**: N/A (ARM-specific two-level TLB)  
**ARM Cortex-A78**: `armv8_cortex_a78/l1d_tlb_refill/`, `armv8_cortex_a78/l2d_tlb/`, `armv8_cortex_a78/l2d_tlb_refill/`  
**Criticality**: **Important**

**Explanation**: ARM-specific two-level TLB metrics. L1 TLB refills indicate L1 TLB misses that hit in L2 TLB (cheaper than page walk). L2 TLB accesses and refills indicate when even L2 TLB misses, requiring expensive page table walk.

**Commonly Used With**:
- `dtlb_walk` - L2 TLB refills should match page table walks
- `dTLB-loads` / `l1d_tlb` - Multi-level TLB behavior analysis

**Example**:
```bash
perf stat -e armv8_cortex_a78/l1d_tlb_refill/,armv8_cortex_a78/dtlb_walk/ ./map_based_prediction

# Output interpretation:
# 500 l1d_tlb_refill (L1 TLB misses)
# 100 dtlb_walk (L2 TLB misses requiring page walk)
# 80% of L1 TLB misses hit in L2 TLB - good page locality
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78: Two-level TLB (L1: 48 entries, L2: 1024 entries)
- L1 TLB miss → L2 TLB lookup (~5-10 cycles)
- L2 TLB miss → Page table walk (~10-50 cycles)

*Research-Heavy - Cross-Architecture Analysis*:
- **x86 Comparison**: Intel/AMD also have two-level TLBs (similar architecture)
- **Quantitative Portability**:
  - **L1 TLB hit rate is comparable** across architectures
  - **L2 TLB hit rate** reflects page locality (architecture-agnostic)
- **Algorithmic Implications**:
  - High L1 TLB refills but low page walks: Good L2 TLB coverage
  - High page walks: Very poor page locality, consider huge pages

---

### page-faults / minor-faults / major-faults

**Generic**: `page-faults`, `minor-faults`, `major-faults`  
**ARM Cortex-A78**: Same generic events  
**Criticality**: **Important**

**Explanation**: Page faults occur when a program accesses a memory page not currently mapped or in physical RAM. Minor faults are cheap (page in memory but not mapped). Major faults require disk I/O (swap or memory-mapped files) and are extremely expensive (milliseconds). For real-time systems, major faults are unacceptable.

**Commonly Used With**:
- `dTLB-load-misses` / `dtlb_walk` - Page faults often follow TLB misses
- `task-clock` - Major faults dramatically increase execution time

**Example**:
```bash
perf stat -e page-faults,major-faults,minor-faults ./pointcloud_map_loader

# Output interpretation:
# 12,345 page-faults
# 0 major-faults
# 12,345 minor-faults
# All minor - good, map loaded but not fully mapped yet
```

**Comments**:

*Basic Info - Portability Considerations*:
- Page faults are OS-level events (Linux kernel), architecture-independent
- Minor fault latency: ~1-10 microseconds
- Major fault latency: ~1-50 milliseconds (disk I/O)
- Real-time systems: Zero major faults mandatory

*Research-Heavy - Cross-Architecture Analysis*:
- **Architecture Independence**: Page faults depend on OS memory management, not CPU architecture
- **Quantitative Portability**: Page fault counts are directly comparable across all platforms
- **Algorithmic Implications**:
  - Minor faults: Acceptable during startup, problematic during steady-state
  - Major faults: Indicate insufficient RAM or memory leaks
  - **Cross-platform target**: Zero major faults, minimize minor faults (<100/sec)

---

## D. Branch Prediction & Control Flow (Additional Metrics)

---

### branch-load-misses

**Generic**: `branch-load-misses`  
**ARM Cortex-A78**: Similar behavior to generic  
**Criticality**: **Important**

**Explanation**: Counts branch instructions that missed in the Branch Target Buffer (BTB) or required fetching from lower cache levels. This metric reflects control flow locality - whether branch targets are repeatedly accessed (good locality) or scattered (poor locality). Algorithms with many unique function call sites or indirect branches (virtual functions, function pointers) have higher branch load misses.

**Commonly Used With**:
- `branch-loads` / `br_retired` - To calculate branch cache miss rate
- `L1-icache-load-misses` - Related instruction cache effects
- `branch-misses` / `br_mis_pred` - Combined branch prediction and caching analysis

**Example**:
```bash
perf stat -e branch-load-misses,branch-loads ./lidar_centerpoint

# Output interpretation:
# 1,234 branch-load-misses (BTB misses)
# 234,567 branch-loads
# Miss rate: 0.5% - good branch target locality in neural network inference
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78: BTB caches branch target addresses (where branches jump to)
- BTB miss = need to compute/fetch target address (adds cycles)
- Typical miss rates: Direct branches (<0.5%), Indirect branches (5-20%)

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**:
  - A57: Small BTB (~2K entries), miss rate 1-3%
  - A72: Larger BTB (~4K entries), miss rate 0.5-2%
  - A78: Advanced BTB (~6K entries), miss rate 0.3-1%
- **x86 Comparison**:
  - Intel: Large BTB (~5-8K entries), miss rate 0.2-0.8%
  - AMD: Medium BTB (~4-6K entries), miss rate 0.3-1%
- **RISC vs CISC**: BTB behavior is similar (both architectures use BTB caching)
- **Quantitative Portability**:
  - **BTB miss rate is comparable** across architectures for direct branches
  - **Indirect branch behavior varies** with BTB size and algorithm
  - Expected BTB miss rate: Direct (<1%), Indirect (2-10%)
- **Algorithmic Implications**:
  - High BTB miss rate (>2%): Many indirect branches (virtual functions, function pointers)
  - Optimization: Use direct calls instead of virtual functions when possible
  - **Cross-platform target**: <1% BTB miss rate for predictable control flow

---

### br_mis_pred_retired, br_pred (ARM-specific)

**Generic**: N/A  
**ARM Cortex-A78**: `armv8_cortex_a78/br_mis_pred_retired/`, `armv8_cortex_a78/br_pred/`  
**Criticality**: **Important** (ARM-specific insights)

**Explanation**: ARM-specific branch prediction counters. `br_mis_pred_retired` counts mispredicted branches that actually completed (vs speculative). `br_pred` counts branches where prediction occurred. These provide deeper insight into ARM's speculation and prediction behavior.

**Commonly Used With**:
- `br_mis_pred` - Compare speculative vs committed mispredictions
- `br_retired` - Fraction of branches that are predicted

**Example**:
```bash
perf stat -e armv8_cortex_a78/br_mis_pred_retired/,armv8_cortex_a78/br_retired/ ./mission_planner

# Output interpretation:
# 5,678 br_mis_pred_retired (committed mispredictions)
# 234,567 br_retired (total branches)
# 2.4% misprediction rate - slightly higher due to graph traversal
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM-specific: Distinguishes speculative vs committed mispredictions
- Provides insight into speculation efficiency (speculative work wasted)

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM-specific feature**: Most useful for ARM-specific optimization
- **Limited portability**: No direct x86 equivalent (different speculation model)
- **Algorithmic Implications**: Use for ARM-specific tuning, not cross-platform modeling

---

## E. System & Scheduling Metrics

**Category Overview**: System metrics measure OS-level overhead (context switches, migrations) and execution time. These are critical for real-time performance and understanding total latency vs. CPU time.

---

### task-clock

**Generic**: `task-clock`  
**ARM Cortex-A78**: Same generic event  
**Criticality**: **Essential**

**Explanation**: Measures task CPU time in milliseconds. This is the primary metric for execution time - actual CPU time used by the algorithm (excluding time spent sleeping, waiting for I/O, or blocked). Lower task-clock means faster execution. Compare task-clock across different algorithms to determine which is more efficient for the same task.

**Commonly Used With**:
- `instructions` / `inst_retired` - To measure MIPS (millions of instructions per second)
- `cpu-cycles` / `cpu_cycles` - To determine average CPU frequency
- `cache-misses` / `l3d_cache_refill` - To see if execution is memory-bound
- `duration_time` - To calculate CPU utilization

**Example**:
```bash
perf stat -e task-clock,armv8_cortex_a78/inst_retired/,cache-misses ./shape_estimation

# Output interpretation:
# 12.345 ms task-clock (CPU time)
# 50,000,000 inst_retired
# 1,234 cache-misses
# Execution rate: 50M / 0.012345s = 4.05 GIPS
# Low cache misses → compute-bound
```

**Comments**:

*Basic Info - Portability Considerations*:
- Task-clock measures actual CPU time (architecture-independent OS metric)
- Execution time is the ultimate performance metric
- Compare across platforms: Same algorithm should have similar CPU time for same clock speed

*Research-Heavy - Cross-Architecture Analysis*:
- **Architecture Independence**: Task-clock is OS-reported CPU time (portable)
- **Quantitative Portability**: **Directly comparable** when normalized by CPU frequency
- **Formula**: Normalized_time = task_clock × (Target_GHz / ARM_GHz)
- **Algorithmic Implications**:
  - Primary metric for algorithm efficiency
  - **Cross-platform target**: Measure task-clock, normalize by frequency for comparisons

---

### duration_time

**Generic**: `duration_time`  
**ARM Cortex-A78**: Same generic event  
**Criticality**: **Essential**

**Explanation**: Measures total elapsed wall-clock time in nanoseconds from start to finish. This includes CPU time plus waiting time (I/O, synchronization, sleeping). For single-threaded programs, duration_time ≈ task-clock. For multi-threaded or I/O-bound programs, duration_time > task-clock. Use this to measure overall latency, but use task-clock to measure computational efficiency.

**Commonly Used With**:
- `task-clock` - To calculate CPU utilization (task-clock / duration_time)
- `context-switches` - High switches increase duration vs. CPU time

**Example**:
```bash
perf stat -e duration_time,task-clock,context-switches ./velocity_smoother

# Output interpretation:
# 15.678 ms duration_time (wall-clock)
# 14.234 ms task-clock (CPU time)
# CPU utilization: 90.8% - mostly compute, some blocking
```

**Comments**:

*Basic Info - Portability Considerations*:
- Duration_time is wall-clock measurement (architecture-independent)
- Difference between duration and task-clock indicates blocking/waiting
- Real-time systems: duration_time is the critical latency metric

*Research-Heavy - Cross-Architecture Analysis*:
- **Architecture Independence**: Wall-clock time is universally portable
- **Quantitative Portability**: **Directly comparable** for same algorithm
- **Algorithmic Implications**:
  - Duration >> task-clock: Algorithm is I/O-bound or heavily synchronized
  - Duration ≈ task-clock: Algorithm is CPU-bound (good for modeling)
  - **Cross-platform**: Duration_time is the end-user latency metric

---

### context-switches

**Generic**: `context-switches`  
**ARM Cortex-A78**: Same generic event  
**Criticality**: **Important**

**Explanation**: Counts the number of times the scheduler switched the CPU from one thread to another. Context switches are expensive (1-10 microseconds) due to cache flushing, TLB invalidation, and kernel overhead. High context switch counts indicate either many threads competing for CPU, or frequent blocking.

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
# 0.45 switches/ms - acceptable for 10 Hz real-time control
```

**Comments**:

*Basic Info - Portability Considerations*:
- Context switch cost: ~1-10 microseconds (OS dependent, architecture-independent)
- Real-time systems: Minimize context switches for deterministic latency

*Research-Heavy - Cross-Architecture Analysis*:
- **Architecture Independence**: OS-level scheduling event (portable)
- **Quantitative Portability**: Context switch count is directly comparable
- **Algorithmic Implications**:
  - High switch rate (>100/sec): Threading or synchronization issues
  - **Cross-platform target**: <10 context switches per 100ms for real-time

---

### cpu-migrations

**Generic**: `cpu-migrations`  
**ARM Cortex-A78**: Same generic event  
**Criticality**: **Important**

**Explanation**: Counts the number of times a thread was migrated from one CPU core to another. CPU migrations are expensive because they invalidate the thread's cache state on the new core. High migration counts indicate poor thread affinity or scheduler thrashing. Well-designed real-time systems pin threads to cores to avoid migrations.

**Commonly Used With**:
- `context-switches` - Migrations often happen during context switches
- `cache-misses` - Migrations cause cache misses on the new core

**Example**:
```bash
perf stat -e cpu-migrations,cache-misses ./autonomous_emergency_braking

# Output interpretation:
# 2 cpu-migrations
# 12,345 cache-misses
# Very low migrations - critical for real-time safety node
```

**Comments**:

*Basic Info - Portability Considerations*:
- Migration cost: Entire cache state invalidated (~10-50 microseconds)
- ARM Cortex-A78: 64KB L1 + 256-512KB L2 per core (lost on migration)

*Research-Heavy - Cross-Architecture Analysis*:
- **Architecture Independence**: OS-level scheduling (portable)
- **Migration cost varies** with cache size (larger caches = higher migration penalty)
- **Quantitative Portability**: Migration count is comparable, but impact varies
- **Algorithmic Implications**:
  - Real-time systems: Use CPU pinning (taskset) to eliminate migrations
  - **Cross-platform target**: Zero migrations for latency-critical tasks

---

### cpu-clock

**Generic**: `cpu-clock`  
**ARM Cortex-A78**: Same generic event  
**Criticality**: **Supplementary** (duplicate of task-clock)

**Explanation**: Measures actual CPU time in nanoseconds. Essentially identical to task-clock but reported in nanoseconds instead of milliseconds. Provided for compatibility.

**Comments**:

*Basic Info*: Use task-clock instead (more convenient millisecond units)

---

## F. Pipeline Efficiency Metrics

**Category Overview**: Pipeline metrics measure CPU frontend (instruction fetch/decode) and backend (execution) efficiency. Stalls indicate wasted cycles. These metrics are microarchitecture-specific but provide insight into whether algorithms are instruction-supply limited or data-supply limited.

---

### stalled-cycles-frontend / stall_frontend

**Generic**: `stalled-cycles-frontend`  
**ARM Cortex-A78**: `armv8_cortex_a78/stall_frontend/`  
**Criticality**: **Important**

**Explanation**: Counts cycles where the CPU frontend (instruction fetch/decode) was stalled - no new instructions entering the pipeline. Frontend stalls occur due to instruction cache misses, branch mispredictions, or complex instruction decoding. High frontend stalls indicate instruction supply problems.

**Commonly Used With**:
- `cpu-cycles` / `cpu_cycles` - To calculate frontend stall rate
- `L1-icache-load-misses` - Frontend stalls often due to I-cache misses
- `branch-misses` / `br_mis_pred` - Branch mispredictions cause frontend stalls
- `stalled-cycles-backend` / `stall_backend` - To see if frontend or backend dominates

**Example**:
```bash
perf stat -e armv8_cortex_a78/stall_frontend/,armv8_cortex_a78/cpu_cycles/ ./behavior_path_planner

# Output interpretation:
# 500,000,000 stall_frontend
# 5,000,000,000 cpu_cycles
# 10% frontend stall - acceptable, mostly due to branch mispredictions
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78: 4-wide fetch frontend, can fetch 4 instructions/cycle
- Frontend stall rate reflects instruction supply efficiency
- Typical rates: Tight loops (<5%), Branch-heavy (10-20%), I-cache intensive (>20%)

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**:
  - A57: 3-wide fetch, typical frontend stall 15-25%
  - A72: 3-wide fetch, improved branch predictor, stall 10-20%
  - A78: 4-wide fetch, advanced predictor, stall 8-15%
- **x86 Comparison**:
  - Intel: 4-6 wide fetch (macro-fusion), typical frontend stall 5-12%
  - AMD Zen 3: 4-wide fetch, typical stall 8-15%
- **Microarchitecture Dependency**: Frontend stall rate varies significantly with pipeline design
- **Quantitative Portability**:
  - **Frontend stall rate is NOT directly comparable** across architectures
  - **Use as diagnostic**: Low frontend stalls + high backend stalls = data-bound algorithm
  - **Cross-platform interpretation**: Stall source (I-cache, branch) is portable, percentage is not

---

### stalled-cycles-backend / stall_backend

**Generic**: `stalled-cycles-backend`  
**ARM Cortex-A78**: `armv8_cortex_a78/stall_backend/`  
**Criticality**: **Important**

**Explanation**: Counts cycles where the CPU backend (execution units) was stalled - instructions decoded but waiting to execute. Backend stalls occur due to data dependencies, cache misses, or resource conflicts. High backend stalls indicate data supply problems or insufficient execution resources.

**Commonly Used With**:
- `cpu-cycles` / `cpu_cycles` - To calculate backend stall rate
- `cache-misses` / `l3d_cache_refill` - Backend stalls often due to cache misses
- `L1-dcache-load-misses` - Data cache misses cause backend stalls

**Example**:
```bash
perf stat -e armv8_cortex_a78/stall_backend/,armv8_cortex_a78/cpu_cycles/,cache-misses ./occupancy_grid_map

# Output interpretation:
# 2,000,000,000 stall_backend
# 5,000,000,000 cpu_cycles
# 40% backend stall - memory-bound, raycasting causes many cache misses
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78: Backend includes 8 execution ports
- Backend stall rate indicates data supply or execution bottlenecks
- Typical rates: Compute-bound (10-25%), Memory-bound (>30%)

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM Evolution**: A57 (30-50% backend stall) → A78 (20-40% stall) for memory-bound code
- **x86 Comparison**: Intel/AMD typical backend stall 25-45% for memory-bound
- **Microarchitecture Dependency**: Backend stall rate varies with execution resources
- **Quantitative Portability**:
  - **Backend stall rate is NOT directly comparable** in absolute terms
  - **Ratio stall_backend/cpu_cycles indicates memory-boundedness** (portable concept)
  - High backend stalls (>30%) + high cache MPKI = memory-bound (portable conclusion)

---

### stall_backend_mem (ARM-specific)

**Generic**: N/A  
**ARM Cortex-A78**: `armv8_cortex_a78/stall_backend_mem/`  
**Criticality**: **Important**

**Explanation**: ARM Cortex-A78 count of backend stalls specifically due to memory operations. Isolates memory-related backend stalls from other causes (resource conflicts, data dependencies). High values indicate memory bandwidth or latency bottleneck.

**Commonly Used With**:
- `stall_backend` - Memory vs. other backend stalls
- `cache-misses` / `l3d_cache_refill` - Cache misses cause memory stalls

**Example**:
```bash
perf stat -e armv8_cortex_a78/stall_backend_mem/,armv8_cortex_a78/stall_backend/ ./lidar_centerpoint

# Output interpretation:
# 1,200,000,000 stall_backend_mem
# 1,500,000,000 stall_backend
# 80% of backend stalls are memory - neural network is memory-bound
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM-specific attribution of backend stalls to memory subsystem
- Provides clear diagnosis: memory-bound vs compute/resource-bound

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM-specific feature**: Direct measurement not available on x86
- **Limited portability**: Use for ARM-specific diagnosis
- **Cross-platform equivalent**: Infer from cache MPKI and backend stall correlation

---

### inst_spec / op_spec (ARM-specific)

**Generic**: N/A  
**ARM Cortex-A78**: `armv8_cortex_a78/inst_spec/`, `armv8_cortex_a78/op_spec/`  
**Criticality**: **Supplementary**

**Explanation**: ARM-specific count of speculatively executed instructions/micro-operations. Modern CPUs speculatively execute beyond branches. If prediction correct, instructions commit. If wrong, they're discarded. High speculation relative to retirement indicates either aggressive speculation or many mispredictions.

**Commonly Used With**:
- `inst_retired` / `op_retired` - Ratio shows speculation efficiency
- `br_mis_pred` - Mispredictions waste speculative work

**Example**:
```bash
perf stat -e armv8_cortex_a78/inst_spec/,armv8_cortex_a78/inst_retired/ ./multi_object_tracker

# Output interpretation:
# 110,000,000 inst_spec (speculative)
# 100,000,000 inst_retired (committed)
# 10% speculation overhead - acceptable for branch-heavy tracking logic
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78: Out-of-order speculative execution
- Speculation overhead = (inst_spec - inst_retired) / inst_retired

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM-specific metric**: Not directly available on x86 perf counters
- **Limited portability**: Use for ARM-specific speculation analysis
- **Algorithmic Implications**: High speculation overhead (>20%) indicates branch misprediction issues

---

## G. Memory Operations (ARM-Specific)

---

### mem_access

**Generic**: N/A  
**ARM Cortex-A78**: `armv8_cortex_a78/mem_access/`  
**Criticality**: **Important**

**Explanation**: ARM Cortex-A78 count of memory operations (loads and stores). This is total memory access count including all cache levels. High mem_access indicates memory-intensive algorithm. ARM-specific total memory operation counting.

**Commonly Used With**:
- `inst_retired` - To calculate memory operations per instruction
- `l1d_cache` - Subset of mem_access
- `cache-misses` / `l3d_cache_refill` - To see what fraction goes to DRAM

**Example**:
```bash
perf stat -e armv8_cortex_a78/mem_access/,armv8_cortex_a78/inst_retired/ ./shape_estimation

# Output interpretation:
# 3,000,000 mem_access
# 10,000,000 inst_retired
# 30% memory operations - typical for matrix-heavy PCA
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM-specific total memory operation counter
- Memory intensity (mem_access / instructions) is architecture-agnostic concept

*Research-Heavy - Cross-Architecture Analysis*:
- **ARM-specific feature**: Direct counter not available on x86 generic events
- **Cross-platform equivalent**: Combine L1-dcache-loads + stores for similar metric
- **Quantitative Portability**: Memory operation ratio is comparable across architectures
- **Algorithmic Implications**:
  - Memory intensity >40%: Memory-bound algorithm
  - Use to classify algorithm characteristics (compute vs memory intensive)

---

### bus_access / bus_cycles

**Generic**: `bus-cycles`, `bus_access` (ARM)  
**ARM Cortex-A78**: `armv8_cortex_a78/bus_access/`, `armv8_cortex_a78/bus_cycles/`  
**Criticality**: **Important**

**Explanation**: ARM Cortex-A78 count of bus accesses and cycles spent on bus transactions. Bus accesses include reads/writes to external memory or peripherals. High bus_cycles suggests memory bandwidth bottleneck or high external memory latency.

**Commonly Used With**:
- `cpu_cycles` - To calculate bus cycle ratio
- `mem_access` - Total memory operations
- `l3d_cache_refill` - L3 misses lead to bus accesses

**Example**:
```bash
perf stat -e armv8_cortex_a78/bus_cycles/,armv8_cortex_a78/cpu_cycles/,cache-misses ./lidar_centerpoint

# Output interpretation:
# 800,000,000 bus_cycles
# 4,000,000,000 cpu_cycles
# 20% bus utilization - memory-intensive neural network inference
```

**Comments**:

*Basic Info - Portability Considerations*:
- ARM Cortex-A78: Bus connects to DRAM and peripherals
- Bus cycle ratio indicates off-chip memory pressure

*Research-Heavy - Cross-Architecture Analysis*:
- **Platform-specific**: Bus architecture varies (ARM SoC vs x86 chipset)
- **Limited portability**: Use as diagnostic for memory bandwidth issues on ARM
- **Algorithmic Implications**: High bus cycles (>15%) indicates DRAM bandwidth saturation

---

## H. Code Quality Indicators

---

### alignment-faults

**Generic**: `alignment-faults`  
**ARM Cortex-A78**: Same generic event  
**Criticality**: **Supplementary**

**Explanation**: Counts misaligned memory accesses that caused CPU faults. Modern CPUs require data alignment (e.g., 4-byte int at address divisible by 4). Misaligned accesses are slow or cause faults. Well-written code should have zero alignment faults.

**Commonly Used With**:
- `instructions` - Alignment faults add overhead
- `emulation-faults` - Both indicate code quality issues

**Example**:
```bash
perf stat -e alignment-faults,instructions ./lidar_centerpoint

# Output interpretation:
# 0 alignment-faults
# 500,000,000 instructions
# Perfect - no alignment issues
```

**Comments**:

*Basic Info*: Zero alignment faults is expected for production code. Non-zero indicates serious bug.

*Research-Heavy*: Architecture-independent concept. Zero expected on all platforms.

---

### emulation-faults

**Generic**: `emulation-faults`  
**ARM Cortex-A78**: Same generic event  
**Criticality**: **Supplementary**

**Explanation**: Counts instructions that had to be emulated by the OS kernel. Occurs for deprecated or unsupported instructions. Modern well-written code should have zero emulation faults.

**Commonly Used With**:
- `instructions` - Emulation adds massive overhead (1000× slower)

**Example**:
```bash
perf stat -e emulation-faults,instructions ./multi_object_tracker

# Output interpretation:
# 0 emulation-faults
# 100,000,000 instructions
# Good - no instruction emulation needed
```

**Comments**:

*Basic Info*: Zero emulation faults is expected. Non-zero indicates compatibility issue.

*Research-Heavy*: Architecture-independent concept. Zero expected on all platforms.

---

## Summary and Usage Recommendations

### Essential Metrics (Must-Measure)

These 12-15 metrics form the minimum set for cross-architecture algorithm evaluation:

1. **instructions** / **inst_retired** - Computational complexity baseline
2. **cpu-cycles** / **cpu_cycles** - With instructions, calculate IPC
3. **task-clock** - Execution time (ultimate performance metric)
4. **duration_time** - Total latency including blocking
5. **branch-misses** / **br_mis_pred** - Control flow predictability
6. **branches** / **br_retired** - Control flow complexity
7. **cache-misses** / **l3d_cache_refill** - Most expensive memory events (LLC MPKI)
8. **cache-references** / **l3d_cache** - LLC access patterns
9. **L1-dcache-load-misses** / **l1d_cache_refill** - L1 data locality
10. **L1-dcache-loads** / **l1d_cache** - Memory access intensity
11. **dTLB-load-misses** / **dtlb_walk** - Page locality
12. **dTLB-loads** / **l1d_tlb** - TLB pressure

### Key Cross-Platform Metrics

**Most Portable** (directly comparable across all architectures):
- **IPC** (instructions per cycle)
- **MPKI** (misses per kilo-instruction) for all cache levels
- **Branch miss rate** (misses / branches)
- **TLB miss rate** (misses / loads)
- **Task-clock** (when normalized by CPU frequency)

**Requires Normalization**:
- Absolute instruction count (RISC vs CISC: ARM ~1.2-1.4× x86)
- Absolute cycle count (normalize by frequency)
- Absolute cache miss count (normalize by cache size differences)

**Architecture-Specific** (use for ARM optimization, limited portability):
- Pipeline stall percentages (stall_frontend, stall_backend)
- ARM-specific counters (inst_spec, mem_access, bus_access)
- Two-level TLB details (l1d_tlb_refill, l2d_tlb)

### Building Cross-Architecture Models

**Step 1: Measure on Jetson Orin AGX (ARM Cortex-A78)**
```bash
perf stat -e armv8_cortex_a78/inst_retired/,armv8_cortex_a78/cpu_cycles/,\
armv8_cortex_a78/br_retired/,armv8_cortex_a78/br_mis_pred/,\
armv8_cortex_a78/l3d_cache_refill/,task-clock \
./your_algorithm
```

**Step 2: Calculate Portable Metrics**
- IPC = inst_retired / cpu_cycles
- LLC MPKI = (l3d_cache_refill / inst_retired) × 1000
- Branch miss rate = br_mis_pred / br_retired
- MIPS = inst_retired / (task_clock × 1000)

**Step 3: Predict on Target Architecture**
- Target instructions ≈ ARM instructions × ISA_ratio (x86: 0.75-0.85, other ARM: 1.0)
- Target LLC misses ≈ ARM_MPKI × Target_instructions / 1000
- Target time ≈ (Target_instructions / Target_IPC) / Target_GHz
- Adjust for cache size: If Target_LLC > ARM_LLC, reduce LLC misses by ~20-40%

**Step 4: Validate**
- Measure on target platform
- Compare predicted vs actual
- Refine model with correction factors

### Critical Portability Guidelines

1. **Always report normalized metrics** (IPC, MPKI, miss rates) not absolute counts
2. **Document ARM Cortex-A78 specifics** (64KB L1, 256-512KB L2, 2-4MB L3, TAGE predictor)
3. **Use instruction count as baseline** - scale all metrics by instructions
4. **Account for RISC/CISC differences** - ARM typically 1.2-1.4× more instructions than x86
5. **Cache size matters** - Larger x86 L3 (8-32MB) reduces absolute miss counts by 30-50%
6. **IPC and MPKI are most portable** - use these as primary cross-platform metrics
7. **Validate assumptions** - Measure on multiple platforms when possible

---

**End of Documentation**

