# Experiment 4: miniperf LLVM Roofline Analysis

This experiment applies the **architecture-agnostic roofline modelling** technique
to the same Autoware nodes identified in the CARET tracing experiment (experiment 1).

The method is described in:
> A. Batashev et al., *"Architecture-Agnostic Roofline Modelling Using LLVM IR"*
> (included as `../agnostic_risc_paper.pdf`)

---

## How It Works

### The Roofline Model

The Roofline Model (Williams et al., 2009) visualises the performance of a program
relative to two hardware limits:

```
Performance (GFLOPs/s)
      ^
      |   Peak Compute ─────────────────────────────────────
      |                                          /
      |                                   roof  /
      |                                       /
      |             Memory BW slope         /
      |          (slope = peak_BW)         /
      |                                   /
      +──────────────────────────────────┴────────────────────>
                                   Ridge              AI (FLOPs/byte)
```

- **X-axis**: Arithmetic Intensity (AI) = total FLOPs ÷ total memory bytes transferred
- **Y-axis**: Measured performance in GFLOPs/s
- **Memory-bound regime** (left of ridge): performance ∝ AI × Peak_BW
- **Compute-bound regime** (right of ridge): performance ≤ Peak_FLOPS

A node's operating point `(AI, Perf)` shows *where* it sits relative to the hardware
ceiling, and *how much headroom* there is before that ceiling is hit.

### The LLVM IR Instrumentation Approach

This is the core insight from the paper. Instead of estimating FLOP counts from PMU
counters (imprecise on modern out-of-order CPUs), miniperf injects a compiler pass
that counts operations **at the LLVM Intermediate Representation (IR) level**:

1. **Compile with the miniperf Clang plugin** (`-fpass-plugin=miniperf_plugin.so`)
   The LLVM pass traverses each function's IR and inserts lightweight integer
   counters at every loop body for:
   - `fadd`, `fmul`, `fma`, `fdiv` etc. → floating-point operation count
   - `load`, `store` instructions → memory byte count (typed from IR types)

2. **Link with `libcollector.so`**
   The Clang plugin's runtime companion accumulates counters into a shared-memory
   region during execution and exposes them via a structured interface.

3. **Two-pass miniperf collection** (`mperf record -s roofline`):
   - **Pass 1** — PMU hardware counters (cycles, memory bandwidth proxies from
     `perf_event`) are sampled while the instrumented binary runs.
   - **Pass 2** — The instrumented binary runs again; this time `libcollector`
     is queried at each loop boundary for accumulated FLOP/byte counts.

4. **`mperf show <profile_dir>`** combines both passes and outputs:
   - Per-loop arithmetic intensity
   - Absolute performance (GFLOPs/s)
   - Bound classification (Memory / Compute / Interconnect)

### Why This is Architecture-Agnostic

Unlike `perf stat`-based approaches (experiment 3) which rely on architecture-
specific PMU event names (e.g. `armv8_cortex_a78/...`), the LLVM IR pass counts
operations at a level that is *independent of microarchitecture*. The per-hotspot
AI is determined by the program's memory access pattern, not the CPU's PMU.

This means:
- Results can be compared across ARM, x86, RISC-V targets without reconfiguration
- No risk of multiplexing errors from too many concurrent PMU events
- Fine-grained visibility: per-loop rather than per-process

---

## Workflow

### Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| Rust toolchain | stable ≥ 1.75 | via rustup |
| Clang + LLVM | 19 | via `apt.llvm.org` |
| Linux perf | ≥ 5.15 | `linux-tools-$(uname -r)` |
| Python 3 | ≥ 3.10 | for parsing/plotting |
| Python packages | — | `pandas numpy matplotlib pyyaml mpld3` |
| Experiment 2 complete | — | single-node isolation recordings |

### Step 1 — Install miniperf

```bash
./install_miniperf.sh
# Options:
#   --prefix ~/miniperf    install location (default: ~/miniperf)
#   --skip-rust            if Rust is already installed
#   --skip-llvm            if Clang 19 is already installed
```

This clones [github.com/alexbatashev/miniperf](https://github.com/alexbatashev/miniperf),
builds `mperf` (Rust binary), and compiles the Clang IR plugin (CMake/Ninja).

### Step 2 — Configure

Edit `miniperf_config.yaml` to confirm:
- `paths.mperf_binary` — path to the `mperf` binary
- `paths.clang_plugin` — path to the built `.so` plugin
- `paths.single_node_run_dir` — relative path to experiment 2 recordings

### Step 3 — Build Instrumented Nodes

```bash
./build_instrumented_nodes.sh [node_name|all]
```

Recompiles each ROS 2 package via `colcon` with:
- `CMAKE_CXX_COMPILER=clang-19`
- `CMAKE_CXX_FLAGS` including `-fpass-plugin=<plugin.so>`
- Linked against `libcollector.so`

Instrumented binaries are installed to `./instrumented_bins/<node_name>/`.

### Step 4 — Run Roofline Collection

```bash
./run_miniperf_roofline.sh [node_name|all] [--repetitions N]
```

Launches the instrumented node via the single-node replayer rosbag, then runs
`mperf record -s roofline`. Results written to:

```
miniperf_data/
└── <node_name>/
    ├── run_wrapper.sh
    ├── roofline_<timestamp>_rep1/   ← miniperf profile directory
    ├── mperf_rep1.log
    └── roofline_summary.txt         ← mperf show output
```

### Step 5 — Run Stat Collection (optional, but recommended)

```bash
./run_miniperf_stat.sh [node_name|all] [--repetitions N]
```

Runs `mperf stat` (snapshot mode, **no** instrumented binary needed) for a quick
sanity check against the perf results from experiment 3.

### Step 6 — Parse Results

```bash
python3 parse_miniperf_results.py
```

Produces:
- `results/miniperf_roofline.csv` — per-hotspot AI and performance
- `results/miniperf_roofline_agg.csv` — one row per node (aggregated)
- `results/miniperf_stat.csv` — averaged counter values from stat mode
- `results/miniperf_summary.csv` — combined summary table

### Step 7 — Plot the Roofline

```bash
python3 plot_roofline.py [--no-caret] [--linear]
```

Produces:
- `graphs/roofline_plot.png` — main roofline figure (log-log, dark theme)
- `graphs/roofline_interactive.html` — interactive version (requires mpld3)

Node colours reflect CARET latency rank (red = highest latency) if the CARET
ranking CSV from experiment 1 is present, allowing cross-experiment correlation.

---

## Output File Reference

| File | Contents |
|---|---|
| `miniperf_data/<node>/roofline_summary.txt` | Raw `mperf show` table |
| `results/miniperf_roofline.csv` | Per-hotspot: node, AI, GFLOPs/s, bound |
| `results/miniperf_roofline_agg.csv` | Per-node aggregate roofline metrics |
| `results/miniperf_stat.csv` | Per-node PMU counter snapshot |
| `results/miniperf_summary.csv` | Combined summary |
| `graphs/roofline_plot.png` | Roofline model figure |
| `graphs/roofline_interactive.html` | Interactive roofline (mpld3) |

---

## Jetson Orin AGX Hardware Ceilings

| Metric | Value |
|---|---|
| Peak FP32 SIMD (ASIMD FMA, 128-bit) | 422.4 GFLOPs/s |
| Peak FP32 scalar | 105.6 GFLOPs/s |
| Peak FP64 scalar | 52.8 GFLOPs/s |
| Peak LPDDR5 bandwidth | 204.8 GB/s |
| Ridge point (FP32 SIMD) | **2.06 FLOPs/byte** |
| Ridge point (FP32 scalar) | **0.52 FLOPs/byte** |

Values from the Nvidia Jetson Orin AGX datasheet (ARM Cortex-A78AE × 12 @ 2.2 GHz,
LPDDR5 × 256-bit bus @ 6400 Mbps).

---

## Comparison with Experiment 3 (perf)

See `../5_methodology_comparison/` for a quantitative cross-methodology comparison.

Key differences between the two approaches:

| Aspect | Experiment 3 (perf stat) | Experiment 4 (miniperf roofline) |
|---|---|---|
| FLOP counting | Indirect (cache miss proxy) | Direct (LLVM IR instrumentation) |
| Architecture-specific setup | Required (PMU event names) | Not required |
| Granularity | Per-process | Per-loop hotspot |
| Overhead | Very low (<1%) | Low (counter increment per iteration) |
| Requires recompilation | No | Yes (Clang + plugin) |
| Output | Counter table | Roofline chart + AI values |
