#!/bin/bash
# =============================================================================
# Profile All Target Processes in PARALLEL
# =============================================================================
# Starts Autoware, plays rosbag, and profiles ALL target processes
# simultaneously using parallel perf stat invocations.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/perf_data/raw"
ROSBAG_PATH="${HOME}/autoware_map/sample-rosbag"
MAP_PATH="${HOME}/autoware_map/sample-map-rosbag"
PERF_DURATION=60

source /opt/ros/humble/setup.bash
source "${PROJECT_ROOT}/autoware/install/setup.bash"

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

EVENTS="instructions,cpu-cycles,branches,branch-misses,task-clock,context-switches,L1-dcache-loads,L1-dcache-load-misses,cache-references,cache-misses"

# ── Start Autoware ───────────────────────────────────────────────────────────
echo "Starting Autoware..."
ros2 launch autoware_launch logging_simulator.launch.xml \
    map_path:="${MAP_PATH}" \
    vehicle_model:=sample_vehicle \
    sensor_model:=sample_sensor_kit \
    rviz:=false > /dev/null 2>&1 &
AW_PID=$!
echo "Autoware PID: ${AW_PID}"

echo "Waiting 60s for full initialization..."
sleep 60

if ! kill -0 "${AW_PID}" 2>/dev/null; then
    echo "ERROR: Autoware died"
    exit 1
fi

NODE_COUNT=$(ros2 node list 2>/dev/null | wc -l)
echo "Nodes running: ${NODE_COUNT}"

# ── Discover PIDs ────────────────────────────────────────────────────────────
echo ""
echo "Discovering target processes..."

declare -A TARGETS

# Standalone nodes
for pattern in \
    "ndt_scan_matcher:autoware_ndt_scan_matcher_node" \
    "ekf_localizer:autoware_ekf_localizer_node" \
    "shape_estimation:shape_estimation_node" \
    "multi_object_tracker:multi_object_tracker_node" \
    "map_based_prediction:map_based_prediction[^_]"; do

    IFS=':' read name grep_pat <<< "${pattern}"
    PID=$(ps aux 2>/dev/null | grep -v grep | grep "${grep_pat}" | awk '{print $2}' | head -1)
    if [ -n "${PID}" ]; then
        TARGETS["${name}"]="${PID}"
        echo "  ${name}: PID=${PID}"
    else
        echo "  ${name}: NOT FOUND"
    fi
done

# Container nodes
for cname in \
    "velocity_smoother_container" \
    "behavior_planning_container" \
    "motion_planning_container" \
    "mission_planner_container" \
    "control_container"; do

    PID=$(ps aux 2>/dev/null | grep component_container | grep -v grep | grep "__node:=${cname}" | awk '{print $2}' | head -1)
    if [ -n "${PID}" ]; then
        TARGETS["${cname}"]="${PID}"
        echo "  ${cname}: PID=${PID}"
    else
        echo "  ${cname}: NOT FOUND"
    fi
done

# Pointcloud container
PID=$(ps aux 2>/dev/null | grep component_container | grep -v grep | grep "lidar/top" | awk '{print $2}' | head -1)
if [ -n "${PID}" ]; then
    TARGETS["pointcloud_container_top"]="${PID}"
    echo "  pointcloud_container_top: PID=${PID}"
fi

echo ""
echo "Found ${#TARGETS[@]} processes to profile"

# ── Play rosbag in background ────────────────────────────────────────────────
echo "Starting rosbag playback (rate=1.0)..."
ros2 bag play "${ROSBAG_PATH}" -r 1.0 -s sqlite3 --clock > /dev/null 2>&1 &
ROSBAG_PID=$!
sleep 5

# ── Launch ALL perf stat instances simultaneously ─────────────────────────────
echo "Launching parallel perf stat (${PERF_DURATION}s each)..."

PERF_PIDS=()
for name in "${!TARGETS[@]}"; do
    pid="${TARGETS[$name]}"
    if ! kill -0 "${pid}" 2>/dev/null; then
        echo "  ${name}: PID ${pid} not running, skip"
        continue
    fi

    node_dir="${OUTPUT_DIR}/${name}"
    mkdir -p "${node_dir}"
    outfile="${node_dir}/core_execution.txt"

    echo "  Starting perf for ${name} (PID=${pid})"
    perf stat -e "${EVENTS}" -p "${pid}" -- sleep "${PERF_DURATION}" > "${outfile}" 2>&1 &
    PERF_PIDS+=($!)
done

echo ""
echo "Waiting ${PERF_DURATION}s for all perf instances to complete..."
sleep $((PERF_DURATION + 5))

# Wait for all perf processes to finish
for ppid in "${PERF_PIDS[@]}"; do
    wait "${ppid}" 2>/dev/null || true
done

echo ""
echo "Waiting for rosbag to finish..."
wait "${ROSBAG_PID}" 2>/dev/null || true

# ── Stop Autoware ─────────────────────────────────────────────────────────────
echo "Stopping Autoware..."
kill "${AW_PID}" 2>/dev/null || true
sleep 3
kill -9 "${AW_PID}" 2>/dev/null || true

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=============================================="
echo "Perf profiling complete!"
echo "=============================================="
for dir in "${OUTPUT_DIR}"/*/; do
    name=$(basename "$dir")
    if [ -f "$dir/core_execution.txt" ]; then
        lines=$(wc -l < "$dir/core_execution.txt")
        size=$(wc -c < "$dir/core_execution.txt")
        echo "  ${name}: ${lines} lines, ${size} bytes"
    fi
done
echo ""
echo "Next: python3 clean_perf_data.py"
