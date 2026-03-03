#!/bin/bash
# =============================================================================
# Run miniperf Stat (Snapshot) on Isolated Autoware Nodes
# =============================================================================
# This script runs the miniperf "snapshot" scenario, which is equivalent to
# `perf stat` but uses the same miniperf tooling.
#
# Unlike the roofline scenario, snapshot mode does NOT require instrumented
# binaries — it collects raw PMU hardware counter statistics from the regular
# (unmodified) node binary. This is useful for:
#   - Quick sanity checks before committing to full roofline instrumentation
#   - Comparing counter readings between miniperf and experiment 3 (perf)
#   - Nodes where instrumented compilation fails
#
# Collected metrics (similar to perf stat):
#   cycles, instructions, IPC,
#   LLC references/misses, branch misses,
#   stalled_cycles_backend, stalled_cycles_frontend,
#   cpu_clock, page_faults, context_switches
#
# Usage:
#   ./run_miniperf_stat.sh [node_name|all] [--repetitions N]
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/miniperf_config.yaml"

# ─── Parse arguments ──────────────────────────────────────────────────────────
TARGET_NODE="${1:-all}"
REPETITIONS="${2:-5}"
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
SINGLE_NODE_DIR="${SCRIPT_DIR}/../2_single_node_isolation/single_node_run"
OUTPUT_DIR="${SCRIPT_DIR}/miniperf_data"
ROS2_SETUP=$(parse_yaml_value "ros2_setup")
AUTOWARE_SETUP=$(parse_yaml_value "autoware_setup")
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "============================================================"
echo "  miniperf Stat (Snapshot) Mode"
echo "============================================================"
echo "  mperf binary : ${MPERF}"
echo "  Output dir   : ${OUTPUT_DIR}"
echo "  Repetitions  : ${REPETITIONS}"
echo "============================================================"
echo ""

# ─── Pre-flight ───────────────────────────────────────────────────────────────
if [ ! -f "${MPERF}" ]; then
    echo "ERROR: mperf binary not found: ${MPERF}"
    echo "       Run install_miniperf.sh first."
    exit 1
fi

# shellcheck source=/dev/null
source "${ROS2_SETUP}" 2>/dev/null || true
# shellcheck source=/dev/null
source "${AUTOWARE_SETUP}" 2>/dev/null || true

mkdir -p "${OUTPUT_DIR}"

# ─── Parse node list ──────────────────────────────────────────────────────────
parse_nodes() {
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

# ─── Run stat on a single node ────────────────────────────────────────────────
run_stat_node() {
    local node_name="$1"

    echo ""
    echo "===== Stat: ${node_name} ====="

    local replay_dir="${SINGLE_NODE_DIR}/${node_name}"
    if [ ! -d "${replay_dir}" ]; then
        echo "  WARNING: No replay recording found: ${replay_dir}"
        echo "           Run experiment 2 first."
        return 1
    fi

    local rosbag_dir
    rosbag_dir=$(find "${replay_dir}" -name "rosbag2_*" -type d 2>/dev/null | head -1)
    if [ -z "${rosbag_dir}" ]; then
        echo "  WARNING: No rosbag in ${replay_dir}"
        return 1
    fi

    local node_output="${OUTPUT_DIR}/${node_name}"
    mkdir -p "${node_output}"

    # Build wrapper script (same pattern as roofline, but without instrumented binary)
    local wrapper_script="${node_output}/stat_wrapper.sh"
    cat > "${wrapper_script}" << WRAPPER_EOF
#!/bin/bash
source "${ROS2_SETUP}" 2>/dev/null || true
source "${AUTOWARE_SETUP}" 2>/dev/null || true
cd "${replay_dir}"
RUN_SCRIPT=\$(find . -name "ros2_run_*" -type f 2>/dev/null | head -1)
if [ -n "\${RUN_SCRIPT}" ]; then
    bash "\${RUN_SCRIPT}" &
else
    echo "No run script found in ${replay_dir}" && exit 1
fi
NODE_PID=\$!
sleep 5
ros2 bag play "${rosbag_dir}" -s sqlite3 --clock
sleep 2
kill \${NODE_PID} 2>/dev/null || true
wait \${NODE_PID} 2>/dev/null || true
WRAPPER_EOF
    chmod +x "${wrapper_script}"

    local stat_file="${node_output}/stat_${TIMESTAMP}.txt"
    local all_reps=()

    for rep in $(seq 1 "${REPETITIONS}"); do
        local rep_file="${node_output}/stat_rep${rep}_${TIMESTAMP}.txt"
        echo "  [Rep ${rep}/${REPETITIONS}]"

        # mperf stat runs the snapshot scenario (no instrumented binary needed)
        "${MPERF}" stat -- bash "${wrapper_script}" \
            2>&1 | tee "${rep_file}"

        all_reps+=("${rep_file}")
    done

    # Concatenate all reps into one summary file
    cat "${all_reps[@]}" > "${stat_file}"
    echo ""
    echo "  Stat results written to: ${stat_file}"
    echo ""
    # Print last table
    tail -30 "${all_reps[-1]}"
}

# ─── Main loop ────────────────────────────────────────────────────────────────
NODE_LIST=$(parse_nodes)
SUCCESS=0
FAILED=()

while IFS='|' read -r node_name package executable; do
    if [ "${TARGET_NODE}" != "all" ] && [ "${node_name}" != "${TARGET_NODE}" ]; then
        continue
    fi
    if run_stat_node "${node_name}"; then
        SUCCESS=$((SUCCESS + 1))
    else
        FAILED+=("${node_name}")
    fi
done <<< "${NODE_LIST}"

echo ""
echo "============================================================"
echo "  Stat collection complete"
echo "  Succeeded : ${SUCCESS}"
echo "  Failed    : ${#FAILED[@]}"
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "  Failed nodes:"
    for f in "${FAILED[@]}"; do echo "    - ${f}"; done
fi
echo "============================================================"
echo ""
echo "Next step: python3 parse_miniperf_results.py"
