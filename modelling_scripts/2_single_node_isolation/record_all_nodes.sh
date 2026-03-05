#!/bin/bash
# =============================================================================
# Record All Target Nodes in One Autoware Session
# =============================================================================
# Starts Autoware once, then for each of the 15 target nodes:
#   1. Discovers the node's actual namespace from the running system
#   2. Runs ros2_single_node_replayer recorder.py in background
#   3. Plays the rosbag to generate traffic
#   4. Stops the recorder (SIGINT) to finalise the bag
#   5. Copies output to single_node_run/<node>/
# =============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MERGED_CSV="${SCRIPT_DIR}/merged_node_data.csv"
OUTPUT_DIR="${SCRIPT_DIR}/single_node_run"
REPLAYER_DIR="${PROJECT_ROOT}/ros2_single_node_replayer"
REMAP_FILE="no_remapping.yaml"

MAP_PATH="${HOME}/autoware_map/sample-map-rosbag"
ROSBAG_PATH="${HOME}/autoware_map/sample-rosbag"
ROSBAG_RATE="0.2"
MIN_NODES=50

source /opt/ros/humble/setup.bash
source "${PROJECT_ROOT}/autoware/install/setup.bash"

mkdir -p "${OUTPUT_DIR}"

AUTOWARE_PID=""

cleanup() {
    echo ""
    echo "Cleaning up all processes..."
    if [ -n "${AUTOWARE_PID}" ]; then
        kill "${AUTOWARE_PID}" 2>/dev/null || true
        sleep 2
        kill -9 "${AUTOWARE_PID}" 2>/dev/null || true
    fi
    jobs -p 2>/dev/null | xargs -r kill -9 2>/dev/null || true
    wait 2>/dev/null || true
    echo "Done."
}
trap cleanup EXIT

# ── Start Autoware ────────────────────────────────────────────────────────────
echo "=============================================="
echo "Starting Autoware (headless mode)..."
echo "=============================================="

ros2 launch autoware_launch logging_simulator.launch.xml \
    map_path:="${MAP_PATH}" \
    vehicle_model:=sample_vehicle \
    sensor_model:=sample_sensor_kit \
    rviz:=false &
AUTOWARE_PID=$!

echo "Autoware PID: ${AUTOWARE_PID}"

# Wait until enough nodes are running (up to 180s)
echo "Waiting for Autoware nodes to come up (need >= ${MIN_NODES})..."
ELAPSED=0
while [ ${ELAPSED} -lt 180 ]; do
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    NODE_COUNT=$(ros2 node list 2>/dev/null | wc -l)
    echo "  ${ELAPSED}s: ${NODE_COUNT} nodes detected"
    if [ "${NODE_COUNT}" -ge "${MIN_NODES}" ]; then
        echo "  Sufficient nodes running."
        break
    fi
done

if ! kill -0 "${AUTOWARE_PID}" 2>/dev/null; then
    echo "ERROR: Autoware failed to start"
    exit 1
fi

# ── Save discovered node list ────────────────────────────────────────────────
ALL_NODES_FILE=$(mktemp)
ros2 node list 2>/dev/null > "${ALL_NODES_FILE}"
NODE_COUNT=$(wc -l < "${ALL_NODES_FILE}")
echo ""
echo "Discovered ${NODE_COUNT} running nodes."

# ── Helper: find actual namespace for a short node name ──────────────────────
find_node_namespace() {
    local short_name="$1"
    local match
    match=$(grep "/${short_name}$" "${ALL_NODES_FILE}" | head -1)
    if [ -n "${match}" ]; then
        # Extract namespace = everything before the last /short_name
        local ns
        ns=$(echo "${match}" | sed "s|/${short_name}$||")
        if [ -z "${ns}" ]; then
            ns="/"
        fi
        echo "${ns}"
    fi
}

# ── Record each target node ──────────────────────────────────────────────────
TOTAL=0
SUCCESS=0

while IFS=',' read -r node_name short_name namespace package executable latency_ms rest; do
    # Skip header
    if [ "${node_name}" = "node_name" ]; then
        continue
    fi

    short_name=$(echo "${short_name}" | tr -d '"' | xargs)
    package=$(echo "${package}" | tr -d '"' | xargs)
    executable=$(echo "${executable}" | tr -d '"' | xargs)

    TOTAL=$((TOTAL + 1))

    echo ""
    echo "=============================================="
    echo "[${TOTAL}/15] Recording: ${short_name}"
    echo "  Package: ${package}, Executable: ${executable}"
    echo "=============================================="

    # Find the actual namespace from the running system
    ACTUAL_NS=$(find_node_namespace "${short_name}")

    if [ -z "${ACTUAL_NS}" ]; then
        echo "  WARNING: Node '${short_name}' not found in running system."
        echo "  Trying with namespace '/'..."
        ACTUAL_NS="/"
    fi

    echo "  Using namespace: ${ACTUAL_NS}"

    # Create node output directory
    NODE_DIR="${OUTPUT_DIR}/${short_name}"
    mkdir -p "${NODE_DIR}"

    # Run recorder.py in background
    echo "  Starting recorder..."
    cd "${REPLAYER_DIR}"
    python3 recorder.py "${package}" "${executable}" "${ACTUAL_NS}" "${short_name}" "${REMAP_FILE}" &
    RECORDER_PID=$!

    echo "  Recorder PID: ${RECORDER_PID}"
    echo "  Waiting for recorder initialization (10s)..."
    sleep 10

    if ! kill -0 "${RECORDER_PID}" 2>/dev/null; then
        echo "  WARNING: Recorder exited early for ${short_name}. Checking output..."
        # Recorder may have failed or completed quickly
    else
        # Play rosbag to generate traffic
        echo "  Playing rosbag at rate ${ROSBAG_RATE}..."
        ros2 bag play "${ROSBAG_PATH}" -r "${ROSBAG_RATE}" -s sqlite3 2>&1 || true

        echo "  Rosbag finished. Waiting 3s..."
        sleep 3

        # Stop recorder gracefully
        echo "  Stopping recorder..."
        kill -SIGINT "${RECORDER_PID}" 2>/dev/null || true

        WAIT=0
        while kill -0 "${RECORDER_PID}" 2>/dev/null && [ ${WAIT} -lt 15 ]; do
            sleep 1
            WAIT=$((WAIT + 1))
        done
        kill -9 "${RECORDER_PID}" 2>/dev/null || true
        wait "${RECORDER_PID}" 2>/dev/null || true
    fi

    # Find and copy recorder output
    LATEST_OUTPUT=$(ls -dt "${REPLAYER_DIR}/output"/*"${short_name}"* 2>/dev/null | head -1)
    if [ -z "${LATEST_OUTPUT}" ]; then
        # Try partial match
        LATEST_OUTPUT=$(ls -dt "${REPLAYER_DIR}/output"/* 2>/dev/null | head -1)
    fi

    if [ -n "${LATEST_OUTPUT}" ] && [ -d "${LATEST_OUTPUT}" ]; then
        echo "  Copying output: $(basename "${LATEST_OUTPUT}") -> ${NODE_DIR}/"
        cp -r "${LATEST_OUTPUT}"/* "${NODE_DIR}/" 2>/dev/null || true
        SUCCESS=$((SUCCESS + 1))
        echo "  SUCCESS: ${short_name} recorded."
        ls "${NODE_DIR}/" 2>/dev/null | head -5
    else
        echo "  WARNING: No output found for ${short_name}"
    fi

    cd "${SCRIPT_DIR}"

done < "${MERGED_CSV}"

# ── Stop Autoware ─────────────────────────────────────────────────────────────
echo ""
echo "Stopping Autoware..."
kill "${AUTOWARE_PID}" 2>/dev/null || true
sleep 3
kill -9 "${AUTOWARE_PID}" 2>/dev/null || true
AUTOWARE_PID=""

echo ""
echo "=============================================="
echo "Recording complete!"
echo "  Total:    ${TOTAL}"
echo "  Success:  ${SUCCESS}"
echo "  Output:   ${OUTPUT_DIR}/"
echo "=============================================="
echo ""
for dir in "${OUTPUT_DIR}"/*/; do
    node=$(basename "${dir}")
    files=$(ls "${dir}" 2>/dev/null | wc -l)
    echo "  ${node}: ${files} files"
done
