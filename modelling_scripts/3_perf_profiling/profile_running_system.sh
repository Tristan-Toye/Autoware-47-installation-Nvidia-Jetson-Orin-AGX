#!/bin/bash
# =============================================================================
# Profile Running Autoware System with perf stat
# =============================================================================
# Profiles each target node/container process with perf stat while
# a rosbag plays, collecting architecture metrics.
#
# Usage: ./profile_running_system.sh
# Requires: Autoware already running
# =============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/perf_data/raw"
ROSBAG_PATH="${HOME}/autoware_map/sample-rosbag"
ROSBAG_RATE="1.0"

source /opt/ros/humble/setup.bash
source "${PROJECT_ROOT}/autoware/install/setup.bash"

mkdir -p "${OUTPUT_DIR}"

# ── Map target nodes to PIDs ─────────────────────────────────────────────────
declare -A NODE_PIDS

# Standalone processes
find_pid() {
    local pattern="$1"
    ps aux | grep -v grep | grep "${pattern}" | awk '{print $2}' | head -1
}

NODE_PIDS["ndt_scan_matcher"]=$(find_pid "autoware_ndt_scan_matcher_node")
NODE_PIDS["ekf_localizer"]=$(find_pid "autoware_ekf_localizer_node")
NODE_PIDS["shape_estimation"]=$(find_pid "shape_estimation_node" | head -1)
NODE_PIDS["multi_object_tracker"]=$(find_pid "multi_object_tracker_node")
NODE_PIDS["map_based_prediction"]=$(find_pid "map_based_prediction" | head -1)

# Container processes (each container hosts multiple nodes)
find_container_pid() {
    local container_ns="$1"
    ps aux | grep component_container | grep -v grep | grep "__ns:=${container_ns}" | awk '{print $2}' | tail -1
}

NODE_PIDS["behavior_planning_container"]=$(find_container_pid "/planning/scenario_planning/lane_driving/behavior_planning")
NODE_PIDS["motion_planning_container"]=$(find_container_pid "/planning/scenario_planning/lane_driving/motion_planning")
NODE_PIDS["velocity_smoother_container"]=$(find_container_pid "/planning/scenario_planning" | head -1)
NODE_PIDS["mission_planner_container"]=$(find_container_pid "/planning/mission_planning")
NODE_PIDS["control_container"]=$(find_container_pid "/control" | head -1)
NODE_PIDS["pointcloud_container_top"]=$(find_container_pid "/sensing/lidar/top/pointcloud_preprocessor")

echo "=============================================="
echo "Target Process Mapping"
echo "=============================================="
for name in "${!NODE_PIDS[@]}"; do
    pid="${NODE_PIDS[$name]}"
    if [ -n "${pid}" ]; then
        echo "  ${name}: PID=${pid}"
    else
        echo "  ${name}: NOT FOUND"
    fi
done

# ── Metric clusters (generic events, most compatible) ────────────────────────
declare -A CLUSTERS
CLUSTERS["core_execution"]="instructions,cpu-cycles,branches,branch-misses,task-clock,context-switches,cpu-migrations"
CLUSTERS["cache_l1_data"]="L1-dcache-loads,L1-dcache-load-misses,cache-references,cache-misses,instructions"
CLUSTERS["cache_llc"]="LLC-loads,LLC-load-misses,cache-references,cache-misses,instructions"
CLUSTERS["memory_tlb"]="dTLB-loads,dTLB-load-misses,iTLB-loads,iTLB-load-misses,page-faults"
CLUSTERS["branch_analysis"]="branches,branch-misses,instructions"

# ── Profile function ─────────────────────────────────────────────────────────
profile_node() {
    local name="$1"
    local pid="$2"
    local node_dir="${OUTPUT_DIR}/${name}"
    mkdir -p "${node_dir}"

    echo ""
    echo "===== Profiling: ${name} (PID=${pid}) ====="

    for cluster_name in "${!CLUSTERS[@]}"; do
        local events="${CLUSTERS[$cluster_name]}"
        local outfile="${node_dir}/${cluster_name}.txt"

        echo "  Cluster: ${cluster_name}"
        sudo perf stat -e "${events}" -p "${pid}" -o "${outfile}" \
            sleep 30 2>&1 || {
            echo "    WARNING: Some events not available, trying subset..."
            sudo perf stat -e "instructions,cpu-cycles,cache-references,cache-misses" \
                -p "${pid}" -o "${outfile}" sleep 30 2>&1 || true
        }

        if [ -f "${outfile}" ]; then
            echo "    -> ${outfile}"
        fi
    done
}

# ── Play rosbag in background while profiling ────────────────────────────────
echo ""
echo "Starting rosbag playback in background (rate=${ROSBAG_RATE})..."
ros2 bag play "${ROSBAG_PATH}" -r "${ROSBAG_RATE}" -s sqlite3 --clock &
ROSBAG_PID=$!
echo "Rosbag PID: ${ROSBAG_PID}"
sleep 5

# ── Profile each node (30s per cluster × 5 clusters per node) ────────────────
for name in "${!NODE_PIDS[@]}"; do
    pid="${NODE_PIDS[$name]}"
    if [ -z "${pid}" ]; then
        echo "Skipping ${name}: no PID"
        continue
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
        echo "Skipping ${name}: PID ${pid} not running"
        continue
    fi
    profile_node "${name}" "${pid}"
done

# ── Wait for rosbag to finish ────────────────────────────────────────────────
echo ""
echo "Waiting for rosbag to finish..."
wait "${ROSBAG_PID}" 2>/dev/null || true

echo ""
echo "=============================================="
echo "Profiling complete!"
echo "=============================================="
echo "Output: ${OUTPUT_DIR}/"
ls -la "${OUTPUT_DIR}/"
echo ""
echo "Next: python3 clean_perf_data.py && python3 analyze_perf.py && python3 compute_agnostic_metrics.py"
