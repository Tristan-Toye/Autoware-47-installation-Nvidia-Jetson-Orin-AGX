#!/bin/bash
# =============================================================================
# Profile Running Autoware with perf stat (no sudo)
# =============================================================================
# Autoware must already be running. Profiles each target process for
# PERF_DURATION seconds while playing the rosbag simultaneously.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/perf_data/raw"
ROSBAG_PATH="${HOME}/autoware_map/sample-rosbag"
PERF_DURATION=30

source /opt/ros/humble/setup.bash
source "${PROJECT_ROOT}/autoware/install/setup.bash"

mkdir -p "${OUTPUT_DIR}"

EVENTS="instructions,cpu-cycles,branches,branch-misses,task-clock,context-switches,L1-dcache-loads,L1-dcache-load-misses,cache-references,cache-misses"

# ── Discover processes ────────────────────────────────────────────────────────
echo "Discovering target processes..."

find_pid() {
    ps aux 2>/dev/null | grep -v grep | grep "$1" | awk '{print $2}' | head -1
}

find_container() {
    ps aux 2>/dev/null | grep component_container | grep -v grep | grep "__node:=$1" | awk '{print $2}' | head -1
}

declare -A TARGETS
TARGETS["ndt_scan_matcher"]=$(find_pid "autoware_ndt_scan_matcher_node")
TARGETS["ekf_localizer"]=$(find_pid "autoware_ekf_localizer_node")
TARGETS["shape_estimation"]=$(find_pid "shape_estimation_node")
TARGETS["multi_object_tracker"]=$(find_pid "multi_object_tracker_node")
TARGETS["map_based_prediction"]=$(find_pid "map_based_prediction[^_]")
TARGETS["velocity_smoother_container"]=$(find_container "velocity_smoother_container")
TARGETS["behavior_planning_container"]=$(find_container "behavior_planning_container")
TARGETS["motion_planning_container"]=$(find_container "motion_planning_container")
TARGETS["mission_planner_container"]=$(find_container "mission_planner_container")
TARGETS["control_container"]=$(find_container "control_container")
TARGETS["pointcloud_container_top"]=$(ps aux 2>/dev/null | grep component_container | grep -v grep | grep "lidar/top" | awk '{print $2}' | head -1)

echo ""
for name in "${!TARGETS[@]}"; do
    pid="${TARGETS[$name]}"
    if [ -n "${pid}" ]; then
        echo "  ${name}: PID=${pid}"
    else
        echo "  ${name}: NOT FOUND"
    fi
done

# ── Play rosbag in background ────────────────────────────────────────────────
echo ""
echo "Starting rosbag playback..."
ros2 bag play "${ROSBAG_PATH}" -r 1.0 -s sqlite3 --clock > /dev/null 2>&1 &
ROSBAG_PID=$!
echo "Rosbag PID: ${ROSBAG_PID}"
sleep 5

# ── Profile each target ──────────────────────────────────────────────────────
for name in "${!TARGETS[@]}"; do
    pid="${TARGETS[$name]}"
    if [ -z "${pid}" ]; then
        continue
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
        echo "${name}: PID ${pid} not running, skip"
        continue
    fi

    node_dir="${OUTPUT_DIR}/${name}"
    mkdir -p "${node_dir}"
    outfile="${node_dir}/core_execution.txt"

    echo "Profiling ${name} (PID=${pid}) for ${PERF_DURATION}s..."
    perf stat -e "${EVENTS}" -p "${pid}" -- sleep "${PERF_DURATION}" > "${outfile}" 2>&1 || {
        echo "  Retry with basic events..."
        perf stat -e "instructions,cpu-cycles,cache-references,cache-misses,branches,branch-misses" \
            -p "${pid}" -- sleep "${PERF_DURATION}" > "${outfile}" 2>&1 || true
    }

    if [ -s "${outfile}" ]; then
        lines=$(wc -l < "${outfile}")
        echo "  -> ${outfile} (${lines} lines)"
    else
        echo "  WARNING: empty output"
    fi
done

# ── Wait for rosbag ──────────────────────────────────────────────────────────
echo ""
echo "Waiting for rosbag to finish..."
wait "${ROSBAG_PID}" 2>/dev/null || true

echo ""
echo "=============================================="
echo "Perf profiling complete!"
echo "=============================================="
for dir in "${OUTPUT_DIR}"/*/; do
    name=$(basename "$dir")
    if [ -f "$dir/core_execution.txt" ]; then
        lines=$(wc -l < "$dir/core_execution.txt")
        echo "  ${name}: ${lines} lines"
    fi
done
echo ""
echo "Next: python3 clean_perf_data.py && python3 analyze_perf.py && python3 compute_agnostic_metrics.py"
