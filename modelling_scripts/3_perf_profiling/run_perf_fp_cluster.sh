#!/bin/bash
# =============================================================================
# Run FP Operations Perf Cluster
# =============================================================================
# Collects the arm_fp_operations cluster (r0075/ASE_SPEC, r0076/VFP_SPEC,
# inst_retired, cpu_cycles, ll_cache_miss_rd, task-clock) on Autoware nodes.
#
# Two modes:
#   --live   Attach to already-running Autoware processes by name (default)
#   --replay Use single-node replayer recordings from experiment 2
#
# Usage:
#   ./run_perf_fp_cluster.sh [all|node_name] [--live|--replay] [--duration SEC]
#
# Examples:
#   ./run_perf_fp_cluster.sh all --live --duration 30
#   ./run_perf_fp_cluster.sh ndt_scan_matcher --replay
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SINGLE_NODE_DIR="${SCRIPT_DIR}/../2_single_node_isolation/single_node_run"
OUTPUT_DIR="${SCRIPT_DIR}/perf_data"

CLUSTER_NAME="arm_fp_operations"
PERF_EVENTS="r0075,r0076,armv8_cortex_a78/inst_retired/,armv8_cortex_a78/cpu_cycles/,armv8_cortex_a78/ll_cache_miss_rd/,task-clock"

NODE_NAME="${1:-all}"
MODE="live"
DURATION=30

shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --live) MODE="live"; shift ;;
        --replay) MODE="replay"; shift ;;
        --duration) DURATION="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "=============================================="
echo "Perf FP Operations Cluster"
echo "=============================================="
echo "  Mode:     ${MODE}"
echo "  Events:   ${PERF_EVENTS}"
echo "  Duration: ${DURATION}s (live mode)"
echo ""

mkdir -p "${OUTPUT_DIR}/raw"

if ! command -v perf &> /dev/null; then
    echo "ERROR: perf command not found"
    exit 1
fi

# Known node-to-process name mappings for live mode
declare -A NODE_PROCESS_MAP=(
    ["ndt_scan_matcher"]="ndt_scan_matcher"
    ["ekf_localizer"]="ekf_localizer"
    ["lidar_centerpoint"]="lidar_centerpoint"
    ["euclidean_cluster"]="euclidean_cluster"
    ["multi_object_tracker"]="multi_object_tracker"
    ["map_based_prediction"]="map_based_prediction"
    ["shape_estimation"]="shape_estimation"
    ["occupancy_grid_map_node"]="occupancy_grid_map"
    ["autonomous_emergency_braking"]="autonomous_emergency"
    ["pointcloud_concatenate_data"]="pointcloud_concatenate"
    ["behavior_planning_container"]="behavior_path_planner"
    ["control_container"]="controller_node"
    ["mission_planner_container"]="mission_planner"
    ["motion_planning_container"]="motion_velocity"
    ["velocity_smoother_container"]="velocity_smoother"
)

profile_live() {
    local node_name="$1"
    local node_output_dir="${OUTPUT_DIR}/raw/${node_name}"
    mkdir -p "${node_output_dir}"

    echo "===== Node: ${node_name} (live) ====="

    local search="${NODE_PROCESS_MAP[$node_name]:-$node_name}"
    local pid
    pid=$(pgrep -f "${search}" 2>/dev/null | head -1)

    if [ -z "${pid}" ]; then
        echo "  WARNING: No running process found matching '${search}'"
        return 1
    fi

    echo "  PID: ${pid} (matched '${search}')"
    local output_file="${node_output_dir}/${CLUSTER_NAME}.txt"

    perf stat -e "${PERF_EVENTS}" -p "${pid}" -o "${output_file}" -- sleep "${DURATION}" 2>&1 || {
        echo "  WARNING: perf stat returned non-zero"
    }

    if [ -f "${output_file}" ]; then
        echo "  Output: ${output_file}"
        grep -E "r0075|r0076|inst_retired|cpu_cycles|ll_cache_miss|task-clock" "${output_file}" 2>/dev/null || true
    fi
}

profile_replay() {
    local node_name="$1"
    local node_dir="${SINGLE_NODE_DIR}/${node_name}"
    local node_output_dir="${OUTPUT_DIR}/raw/${node_name}"
    mkdir -p "${node_output_dir}"

    echo "===== Node: ${node_name} (replay) ====="

    local rosbag_dir
    rosbag_dir=$(find "${node_dir}" -name "rosbag2_*" -type d 2>/dev/null | head -1)
    local yaml_file
    yaml_file=$(find "${node_dir}" -name "*.yaml" -type f 2>/dev/null | head -1)

    if [ -z "${rosbag_dir}" ]; then
        echo "  ERROR: No rosbag found in ${node_dir}"
        return 1
    fi

    echo "  Rosbag: ${rosbag_dir}"
    echo "  Config: ${yaml_file:-none}"

    local output_file="${node_output_dir}/${CLUSTER_NAME}.txt"

    source /opt/ros/humble/setup.bash 2>/dev/null || true
    local PROJECT_ROOT
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
    if [ -f "${PROJECT_ROOT}/autoware/install/setup.bash" ]; then
        source "${PROJECT_ROOT}/autoware/install/setup.bash" 2>/dev/null || true
    fi

    perf stat -e "${PERF_EVENTS}" -o "${output_file}" \
        ros2 bag play "${rosbag_dir}" -s sqlite3 2>&1 || {
        echo "  WARNING: perf stat returned non-zero"
    }

    if [ -f "${output_file}" ]; then
        echo "  Output: ${output_file}"
    fi
}

# Build node list
if [ "${NODE_NAME}" == "all" ]; then
    if [ "${MODE}" == "live" ]; then
        NODES="${!NODE_PROCESS_MAP[*]}"
    else
        NODES=$(ls -d "${SINGLE_NODE_DIR}"/*/ 2>/dev/null | xargs -n1 basename)
    fi
else
    NODES="${NODE_NAME}"
fi

if [ -z "${NODES}" ]; then
    echo "ERROR: No nodes found"
    exit 1
fi

SUCCESS=0
FAILED=0
for node in ${NODES}; do
    if [ "${MODE}" == "live" ]; then
        profile_live "${node}" && SUCCESS=$((SUCCESS + 1)) || FAILED=$((FAILED + 1))
    else
        profile_replay "${node}" && SUCCESS=$((SUCCESS + 1)) || FAILED=$((FAILED + 1))
    fi
    echo ""
done

echo "=============================================="
echo "FP cluster profiling complete!"
echo "  Succeeded: ${SUCCESS}"
echo "  Failed:    ${FAILED}"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. python3 clean_perf_data.py"
echo "  2. python3 compute_perf_roofline.py"
echo "  3. python3 compute_agnostic_metrics.py"
