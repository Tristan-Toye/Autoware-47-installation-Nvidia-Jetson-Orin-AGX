#!/bin/bash
# =============================================================================
# Combined Experiment Runner
# =============================================================================
# Runs experiments 2 (node isolation) and 3 (perf profiling) in a single
# Autoware session for efficiency.
#
# Phase 1: Start Autoware, wait for full init
# Phase 2: Run perf stat on all target processes while playing rosbag
# Phase 3: Record standalone nodes with replayer (sequential rosbag plays)
# Phase 4: Shutdown
# =============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PERF_OUTPUT="${SCRIPT_DIR}/3_perf_profiling/perf_data/raw"
ISOLATION_OUTPUT="${SCRIPT_DIR}/2_single_node_isolation/single_node_run"
REPLAYER_DIR="${PROJECT_ROOT}/ros2_single_node_replayer"

MAP_PATH="${HOME}/autoware_map/sample-map-rosbag"
ROSBAG_PATH="${HOME}/autoware_map/sample-rosbag"
ROSBAG_RATE="1.0"
MIN_NODES=50
PERF_DURATION=30

source /opt/ros/humble/setup.bash
source "${PROJECT_ROOT}/autoware/install/setup.bash"

mkdir -p "${PERF_OUTPUT}" "${ISOLATION_OUTPUT}"

AUTOWARE_PID=""

cleanup() {
    echo ""
    echo "=== CLEANUP ==="
    if [ -n "${AUTOWARE_PID}" ]; then
        kill "${AUTOWARE_PID}" 2>/dev/null || true
        sleep 2
        kill -9 "${AUTOWARE_PID}" 2>/dev/null || true
    fi
    jobs -p 2>/dev/null | xargs -r kill -9 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup EXIT

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ Phase 1: Start Autoware                                                 ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║ Phase 1: Starting Autoware                  ║"
echo "╚══════════════════════════════════════════════╝"

ros2 launch autoware_launch logging_simulator.launch.xml \
    map_path:="${MAP_PATH}" \
    vehicle_model:=sample_vehicle \
    sensor_model:=sample_sensor_kit \
    rviz:=false > /tmp/autoware_launch.log 2>&1 &
AUTOWARE_PID=$!

echo "Autoware PID: ${AUTOWARE_PID}"
echo "Waiting for nodes to come up (need >= ${MIN_NODES})..."

ELAPSED=0
while [ ${ELAPSED} -lt 300 ]; do
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    if ! kill -0 "${AUTOWARE_PID}" 2>/dev/null; then
        echo "ERROR: Autoware died"
        exit 1
    fi
    NODE_COUNT=$(ros2 node list 2>/dev/null | wc -l)
    echo "  ${ELAPSED}s: ${NODE_COUNT} nodes"
    if [ "${NODE_COUNT}" -ge "${MIN_NODES}" ]; then
        echo "  Ready!"
        break
    fi
done

# Extra wait for all components to load
echo "Extra 15s for component loading..."
sleep 15

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ Phase 2: Perf Profiling                                                 ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║ Phase 2: Perf Profiling                     ║"
echo "╚══════════════════════════════════════════════╝"

# Map target nodes/containers to PIDs
find_standalone_pid() {
    ps aux 2>/dev/null | grep -v grep | grep "$1" | awk '{print $2}' | head -1 || true
}
find_container_pid() {
    ps aux 2>/dev/null | grep component_container | grep -v grep | grep "__node:=$1" | awk '{print $2}' | head -1 || true
}

# Build process map: name|pid|type
PROCS_FILE=$(mktemp)
: > "${PROCS_FILE}"

# Standalone nodes
for pattern in "autoware_ndt_scan_matcher_node" "autoware_ekf_localizer_node" "shape_estimation_node" "multi_object_tracker_node" "map_based_prediction"; do
    PID=$(find_standalone_pid "${pattern}")
    NAME=$(echo "${pattern}" | sed 's/autoware_//;s/_node$//')
    if [ -n "${PID}" ]; then
        echo "${NAME}|${PID}|standalone" >> "${PROCS_FILE}"
    fi
done

# Container nodes
for name in velocity_smoother_container behavior_planning_container motion_planning_container mission_planner_container control_container pointcloud_container; do
    PID=$(find_container_pid "${name}")
    if [ -n "${PID}" ]; then
        echo "${name}|${PID}|container" >> "${PROCS_FILE}"
    fi
done

echo "Target processes:"
cat "${PROCS_FILE}" | while IFS='|' read name pid type; do
    echo "  ${name} (${type}): PID=${pid}"
done

# Play rosbag in background
echo ""
echo "Playing rosbag in background (rate=${ROSBAG_RATE})..."
ros2 bag play "${ROSBAG_PATH}" -r "${ROSBAG_RATE}" -s sqlite3 --clock > /dev/null 2>&1 &
ROSBAG_PID=$!
sleep 5

# Profile each process with perf stat (all clusters combined for simplicity)
EVENTS="instructions,cpu-cycles,branches,branch-misses,task-clock,context-switches,L1-dcache-loads,L1-dcache-load-misses,cache-references,cache-misses,dTLB-loads,dTLB-load-misses,page-faults"

while IFS='|' read -r name pid type; do
    if ! kill -0 "${pid}" 2>/dev/null; then
        echo "  ${name}: PID ${pid} not running, skip"
        continue
    fi

    node_dir="${PERF_OUTPUT}/${name}"
    mkdir -p "${node_dir}"
    outfile="${node_dir}/core_execution.txt"

    echo "  Profiling ${name} (PID=${pid}) for ${PERF_DURATION}s..."
    perf stat -e "${EVENTS}" -p "${pid}" -- sleep "${PERF_DURATION}" > "${outfile}" 2>&1 || {
        echo "  Retrying with basic events..."
        perf stat -e "instructions,cpu-cycles,cache-references,cache-misses,branches,branch-misses" \
            -p "${pid}" -- sleep "${PERF_DURATION}" > "${outfile}" 2>&1 || true
    }

    if [ -s "${outfile}" ]; then
        echo "  -> ${outfile} ($(wc -l < "${outfile}") lines)"
    else
        echo "  WARNING: empty output"
    fi
done < "${PROCS_FILE}"

# Wait for rosbag
echo "Waiting for rosbag to finish..."
wait "${ROSBAG_PID}" 2>/dev/null || true

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ Phase 3: Record Standalone Nodes                                        ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║ Phase 3: Recording Standalone Nodes         ║"
echo "╚══════════════════════════════════════════════╝"

# Nodes discoverable as standalone processes
STANDALONE_NODES=(
    "ndt_scan_matcher|autoware_ndt_scan_matcher|autoware_ndt_scan_matcher_node|/localization/pose_estimator"
    "ekf_localizer|autoware_ekf_localizer|autoware_ekf_localizer_node|/localization/pose_twist_fusion_filter"
    "multi_object_tracker|autoware_multi_object_tracker|multi_object_tracker_node|/perception/object_recognition/tracking"
    "map_based_prediction|autoware_map_based_prediction|map_based_prediction|/perception/object_recognition/prediction"
    "shape_estimation|autoware_shape_estimation|shape_estimation_node|/perception/object_recognition/detection/clustering"
    "velocity_smoother|autoware_velocity_smoother|velocity_smoother|/planning/scenario_planning"
)

RECORD_SUCCESS=0
for entry in "${STANDALONE_NODES[@]}"; do
    IFS='|' read -r short_name package executable namespace <<< "${entry}"

    echo ""
    echo "--- Recording: ${short_name} ---"

    NODE_DIR="${ISOLATION_OUTPUT}/${short_name}"
    mkdir -p "${NODE_DIR}"

    # Verify node is visible
    if ! ros2 node info "${namespace}/${short_name}" >/dev/null 2>&1; then
        echo "  Node not discoverable at ${namespace}/${short_name}, skipping"
        continue
    fi

    cd "${REPLAYER_DIR}"
    python3 recorder.py "${package}" "${executable}" "${namespace}" "${short_name}" "no_remapping.yaml" &
    RPID=$!
    sleep 10

    if ! kill -0 "${RPID}" 2>/dev/null; then
        echo "  Recorder failed to start"
        continue
    fi

    echo "  Playing rosbag (rate=0.5)..."
    ros2 bag play "${ROSBAG_PATH}" -r 0.5 -s sqlite3 2>/dev/null || true
    sleep 3

    kill -SIGINT "${RPID}" 2>/dev/null || true
    W=0; while kill -0 "${RPID}" 2>/dev/null && [ $W -lt 15 ]; do sleep 1; W=$((W+1)); done
    kill -9 "${RPID}" 2>/dev/null || true
    wait "${RPID}" 2>/dev/null || true

    LATEST=$(ls -dt "${REPLAYER_DIR}/output"/*"${short_name}"* 2>/dev/null | head -1)
    if [ -n "${LATEST}" ] && [ -d "${LATEST}" ]; then
        cp -r "${LATEST}"/* "${NODE_DIR}/" 2>/dev/null || true
        RECORD_SUCCESS=$((RECORD_SUCCESS + 1))
        echo "  SUCCESS: $(ls "${NODE_DIR}/" | wc -l) files"
    else
        echo "  No output found"
    fi

    cd "${SCRIPT_DIR}"
done

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ Phase 4: Shutdown                                                        ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║ Phase 4: Shutdown                           ║"
echo "╚══════════════════════════════════════════════╝"

kill "${AUTOWARE_PID}" 2>/dev/null || true
sleep 3
kill -9 "${AUTOWARE_PID}" 2>/dev/null || true
AUTOWARE_PID=""

echo ""
echo "══════════════════════════════════════════════"
echo "EXPERIMENT RESULTS"
echo "══════════════════════════════════════════════"
echo ""
echo "Perf data:"
for dir in "${PERF_OUTPUT}"/*/; do
    name=$(basename "$dir")
    size=$(du -sh "$dir" 2>/dev/null | cut -f1)
    echo "  ${name}: ${size}"
done
echo ""
echo "Recorded nodes: ${RECORD_SUCCESS}"
for dir in "${ISOLATION_OUTPUT}"/*/; do
    name=$(basename "$dir")
    files=$(ls "$dir" 2>/dev/null | wc -l)
    echo "  ${name}: ${files} files"
done
echo ""
echo "Next: cd 3_perf_profiling && python3 clean_perf_data.py && python3 analyze_perf.py && python3 compute_agnostic_metrics.py"
