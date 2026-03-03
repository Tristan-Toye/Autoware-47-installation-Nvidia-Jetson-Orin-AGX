#!/bin/bash
# =============================================================================
# Run miniperf Roofline Analysis on Isolated Autoware Nodes
# =============================================================================
# Executes the miniperf "roofline" scenario on each target node using the
# single-node replayer (from experiment 2) to replay stored rosbag data.
#
# The roofline scenario runs in TWO passes automatically:
#   Pass 1 — PMU hardware counters
#     mperf collects hardware events (cycles, memory bandwidth proxies, etc.)
#     from the Linux perf_event subsystem while the node processes messages.
#   Pass 2 — LLVM IR loop statistics
#     The instrumented binary (compiled with build_instrumented_nodes.sh)
#     runs again and the libcollector.so runtime accumulates per-loop FLOP
#     counts and memory byte counts from the injected LLVM pass counters.
#
# Combining both passes gives:
#   arithmetic_intensity = FLOPs / memory_bytes      [per-loop]
#   performance_gflops   = FLOPs / wall_time_seconds [per-loop]
#
# These are the two axes of the Roofline Model. Points are then compared
# against the hardware ceilings from miniperf_config.yaml.
#
# Usage:
#   ./run_miniperf_roofline.sh [node_name|all] [--repetitions N]
#
# Requires:
#   - miniperf installed (run install_miniperf.sh)
#   - Instrumented binaries built (run build_instrumented_nodes.sh)
#   - Single-node isolation recordings in ../2_single_node_isolation/
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/miniperf_config.yaml"

# ─── Parse arguments ──────────────────────────────────────────────────────────
TARGET_NODE="${1:-all}"
REPETITIONS=3
shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --repetitions) REPETITIONS="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ─── Resolve config values ────────────────────────────────────────────────────
parse_yaml_value() {
    local key="$1"
    grep "^  ${key}:" "${CONFIG_FILE}" | head -1 | sed "s/.*: //" | tr -d '"' | envsubst
}

MPERF=$(parse_yaml_value "mperf_binary")
PLUGIN_SO=$(parse_yaml_value "clang_plugin")
LIBCOLLECTOR_DIR="$(parse_yaml_value "miniperf_root")/target/release"
SINGLE_NODE_DIR="${SCRIPT_DIR}/../2_single_node_isolation/single_node_run"
INSTRUMENTED_DIR="${SCRIPT_DIR}/instrumented_bins"
OUTPUT_DIR="${SCRIPT_DIR}/miniperf_data"
ROS2_SETUP=$(parse_yaml_value "ros2_setup")
AUTOWARE_SETUP=$(parse_yaml_value "autoware_setup")
INSTALL_BASE=$(grep "colcon_install_base:" "${CONFIG_FILE}" | head -1 | awk '{print $2}' | tr -d '"')
AUTOWARE_ROOT=$(parse_yaml_value "autoware_root")

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "============================================================"
echo "  miniperf Roofline Analysis"
echo "============================================================"
echo "  mperf binary   : ${MPERF}"
echo "  Output dir     : ${OUTPUT_DIR}"
echo "  Repetitions    : ${REPETITIONS}"
echo "  Timestamp      : ${TIMESTAMP}"
echo "============================================================"
echo ""

# ─── Pre-flight ───────────────────────────────────────────────────────────────
if [ ! -f "${MPERF}" ]; then
    echo "ERROR: mperf binary not found: ${MPERF}"
    echo "       Run install_miniperf.sh first."
    exit 1
fi

if ! command -v perf &>/dev/null; then
    echo "ERROR: Linux perf not found. Install with:"
    echo "  sudo apt install linux-tools-$(uname -r) linux-tools-generic"
    exit 1
fi

# ─── Source ROS 2 environment ─────────────────────────────────────────────────
# shellcheck source=/dev/null
source "${ROS2_SETUP}" 2>/dev/null || true
# shellcheck source=/dev/null
source "${AUTOWARE_SETUP}" 2>/dev/null || true

mkdir -p "${OUTPUT_DIR}"

# ─── Parse node list ──────────────────────────────────────────────────────────
parse_nodes() {
    local in_node=false
    local node_name="" package="" executable=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]node_name:[[:space:]]*\"(.+)\" ]]; then
            if [ -n "${node_name}" ] && [ -n "${package}" ]; then
                echo "${node_name}|${package}|${executable}"
            fi
            node_name="${BASH_REMATCH[1]}"
            package=""; executable=""
        elif [[ "$line" =~ ^[[:space:]]*package:[[:space:]]*\"(.+)\" ]]; then
            package="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*executable:[[:space:]]*\"(.+)\" ]]; then
            executable="${BASH_REMATCH[1]}"
        fi
    done < "${CONFIG_FILE}"
    if [ -n "${node_name}" ] && [ -n "${package}" ]; then
        echo "${node_name}|${package}|${executable}"
    fi
}

# ─── Run roofline for a single node ───────────────────────────────────────────
run_roofline_node() {
    local node_name="$1"
    local package="$2"
    local executable="$3"

    echo ""
    echo "===== Roofline: ${node_name} ====="

    # Locate the single-node replay environment
    local replay_dir="${SINGLE_NODE_DIR}/${node_name}"
    if [ ! -d "${replay_dir}" ]; then
        echo "  WARNING: No replay recording found: ${replay_dir}"
        echo "           Run experiment 2 (single_node_isolation) first."
        return 1
    fi

    local rosbag_dir
    rosbag_dir=$(find "${replay_dir}" -name "rosbag2_*" -type d 2>/dev/null | head -1)
    if [ -z "${rosbag_dir}" ]; then
        echo "  WARNING: No rosbag found in ${replay_dir}"
        return 1
    fi

    # Locate the instrumented executable
    local instrumented_install="${AUTOWARE_ROOT}/${INSTALL_BASE}/${package}"
    local instrumented_bin
    instrumented_bin=$(find "${instrumented_install}" -name "${executable}" -type f 2>/dev/null | head -1)

    if [ -z "${instrumented_bin}" ]; then
        # Fallback: look in our copied instrumented bins directory
        instrumented_bin=$(find "${INSTRUMENTED_DIR}/${node_name}" -name "${executable}" -type f 2>/dev/null | head -1)
    fi

    if [ -z "${instrumented_bin}" ]; then
        echo "  WARNING: Instrumented binary '${executable}' not found."
        echo "           Run build_instrumented_nodes.sh ${node_name} first."
        return 1
    fi

    echo "  Instrumented binary: ${instrumented_bin}"
    echo "  Rosbag:              ${rosbag_dir}"

    local node_output="${OUTPUT_DIR}/${node_name}"
    mkdir -p "${node_output}"

    # Location where miniperf will write its profile directory
    local profile_dir="${node_output}/roofline_${TIMESTAMP}"

    # Build a wrapper script that:
    #   (a) sources ROS 2 environment
    #   (b) starts the instrumented node
    #   (c) plays the rosbag (experiment stimulus)
    #   (d) exits cleanly
    local wrapper_script="${node_output}/run_wrapper.sh"
    cat > "${wrapper_script}" << WRAPPER_EOF
#!/bin/bash
source "${ROS2_SETUP}" 2>/dev/null || true
source "${AUTOWARE_SETUP}" 2>/dev/null || true

# Ensure libcollector.so is loadable (needed for LLVM pass runtime)
export LD_LIBRARY_PATH="${LIBCOLLECTOR_DIR}:\${LD_LIBRARY_PATH}"

# Override binary with instrumented version
export ROS2_EXECUTABLE="${instrumented_bin}"

# Start the node (using the stored run script or the binary directly)
cd "${replay_dir}"
RUN_SCRIPT=\$(find . -name "ros2_run_*" -type f 2>/dev/null | head -1)
if [ -n "\${RUN_SCRIPT}" ]; then
    bash "\${RUN_SCRIPT}" &
else
    "${instrumented_bin}" &
fi
NODE_PID=\$!

# Wait for node to initialise
sleep 5

# Play the rosbag (provides real sensor/message stimulus)
ros2 bag play "${rosbag_dir}" -s sqlite3 --clock

# Allow node to finish processing
sleep 2

kill \${NODE_PID} 2>/dev/null || true
wait \${NODE_PID} 2>/dev/null || true
WRAPPER_EOF
    chmod +x "${wrapper_script}"

    # ── Run miniperf roofline (both passes) ──────────────────────────────────
    # miniperf handles the two passes internally; we simply specify scenario=roofline.
    # Pass 1: collect PMU counters while running the wrapper
    # Pass 2: collect LLVM IR loop stats while running the wrapper again
    local rep_results=()
    for rep in $(seq 1 "${REPETITIONS}"); do
        local rep_output="${profile_dir}_rep${rep}"
        echo "  [Pass ${rep}/${REPETITIONS}] Recording..."

        "${MPERF}" record \
            -s roofline \
            -o "${rep_output}" \
            -- bash "${wrapper_script}" 2>&1 | tee "${node_output}/mperf_rep${rep}.log"

        if [ -d "${rep_output}" ]; then
            rep_results+=("${rep_output}")
            echo "  ✓ Rep ${rep} done: ${rep_output}"
        else
            echo "  ⚠ Rep ${rep}: output directory not created, check log"
        fi
    done

    # Show the last result
    if [ ${#rep_results[@]} -gt 0 ]; then
        local last_result="${rep_results[-1]}"
        echo ""
        echo "  miniperf show output:"
        "${MPERF}" show "${last_result}" 2>/dev/null | head -40 \
            | tee "${node_output}/roofline_summary.txt"
    fi

    echo "  Output: ${node_output}/"
}

# ─── Main loop ────────────────────────────────────────────────────────────────
NODE_LIST=$(parse_nodes)
SUCCESS=0
FAILED=()

while IFS='|' read -r node_name package executable; do
    if [ "${TARGET_NODE}" != "all" ] && [ "${node_name}" != "${TARGET_NODE}" ]; then
        continue
    fi
    if run_roofline_node "${node_name}" "${package}" "${executable}"; then
        SUCCESS=$((SUCCESS + 1))
    else
        FAILED+=("${node_name}")
    fi
done <<< "${NODE_LIST}"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  Roofline recording complete"
echo "  Succeeded : ${SUCCESS}"
echo "  Failed    : ${#FAILED[@]}"
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "  Failed nodes:"
    for f in "${FAILED[@]}"; do echo "    - ${f}"; done
fi
echo "============================================================"
echo ""
echo "Raw miniperf data: ${OUTPUT_DIR}/"
echo ""
echo "Next steps:"
echo "  python3 parse_miniperf_results.py"
echo "  python3 plot_roofline.py"
