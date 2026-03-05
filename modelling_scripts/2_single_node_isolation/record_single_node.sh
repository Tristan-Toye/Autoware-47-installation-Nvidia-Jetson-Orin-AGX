#!/bin/bash
# =============================================================================
# Record Single Node Script
# =============================================================================
# This script automates the recording of a single node using ros2_single_node_replayer.
# It launches Autoware, starts the replayer, plays rosbag, and auto-terminates.
#
# Usage: ./record_single_node.sh <node_name>
#   node_name: Short name of the node to record (from merged_node_data.csv)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"
MERGED_CSV="${SCRIPT_DIR}/merged_node_data.csv"

# Check arguments
if [ -z "$1" ]; then
    echo "Usage: ./record_single_node.sh <node_name>"
    echo ""
    echo "Available nodes:"
    if [ -f "${MERGED_CSV}" ]; then
        tail -n +2 "${MERGED_CSV}" | head -20 | cut -d',' -f2 | tr -d '"'
    fi
    exit 1
fi

NODE_NAME="$1"

echo "=============================================="
echo "Record Single Node: ${NODE_NAME}"
echo "=============================================="

# Find node in merged CSV
NODE_INFO=$(grep ",${NODE_NAME}," "${MERGED_CSV}" || true)
if [ -z "${NODE_INFO}" ]; then
    echo "ERROR: Node '${NODE_NAME}' not found in merged_node_data.csv"
    exit 1
fi

# Parse node info
IFS=',' read -r full_name short_name namespace package executable latency_ms _ _ _ <<< "${NODE_INFO}"
namespace=$(echo "${namespace}" | tr -d '"')
package=$(echo "${package}" | tr -d '"')
executable=$(echo "${executable}" | tr -d '"')

echo "Package:    ${package}"
echo "Executable: ${executable}"
echo "Namespace:  ${namespace}"
echo ""

if [ "${package}" == "Unknown" ]; then
    echo "ERROR: Package is unknown for this node. Cannot record."
    exit 1
fi

# Parse config for paths
parse_yaml_value() {
    grep "$1:" "${CONFIG_FILE}" | cut -d'"' -f2 | envsubst
}

MAP_PATH=$(parse_yaml_value "map_path")
ROSBAG_PATH=$(parse_yaml_value "rosbag_path")
ROSBAG_RATE=$(parse_yaml_value "rosbag_rate")
REPLAYER_PATH=$(parse_yaml_value "replayer_path")
AUTOWARE_PATH=$(parse_yaml_value "autoware_path")
INIT_TIMEOUT=$(parse_yaml_value "autoware_init_timeout")

MAP_PATH="${MAP_PATH:-${HOME}/autoware_map/sample-map-rosbag}"
ROSBAG_PATH="${ROSBAG_PATH:-${HOME}/autoware_map/sample-rosbag}"
ROSBAG_RATE="${ROSBAG_RATE:-0.2}"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPLAYER_PATH="${REPLAYER_PATH:-${PROJECT_ROOT}/ros2_single_node_replayer}"
AUTOWARE_PATH="${AUTOWARE_PATH:-${PROJECT_ROOT}/autoware}"
INIT_TIMEOUT="${INIT_TIMEOUT:-30}"

# Create output directory
OUTPUT_DIR="${SCRIPT_DIR}/single_node_run/${NODE_NAME}"
mkdir -p "${OUTPUT_DIR}"

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    
    # Kill replayer if running
    if [ -n "${REPLAYER_PID}" ] && kill -0 "${REPLAYER_PID}" 2>/dev/null; then
        echo "Stopping single node replayer (sending SIGINT)..."
        kill -SIGINT "${REPLAYER_PID}" 2>/dev/null || true
        sleep 2
        kill -9 "${REPLAYER_PID}" 2>/dev/null || true
    fi
    
    # Kill Autoware if running
    if [ -n "${AUTOWARE_PID}" ] && kill -0 "${AUTOWARE_PID}" 2>/dev/null; then
        echo "Stopping Autoware..."
        kill "${AUTOWARE_PID}" 2>/dev/null || true
        sleep 2
        kill -9 "${AUTOWARE_PID}" 2>/dev/null || true
    fi
    
    wait 2>/dev/null || true
    echo "Cleanup complete"
}
trap cleanup EXIT

# Source environments
echo "Sourcing ROS2 and Autoware environments..."
source /opt/ros/humble/setup.bash
source "${AUTOWARE_PATH}/install/setup.bash"

# Launch Autoware (headless)
echo ""
echo "Launching Autoware (headless mode)..."
ros2 launch autoware_launch logging_simulator.launch.xml \
    map_path:="${MAP_PATH}" \
    vehicle_model:=sample_vehicle \
    sensor_model:=sample_sensor_kit \
    rviz:=false &
AUTOWARE_PID=$!

echo "Autoware PID: ${AUTOWARE_PID}"
echo "Waiting for Autoware to initialize (${INIT_TIMEOUT}s)..."
sleep "${INIT_TIMEOUT}"

# Check if Autoware is still running
if ! kill -0 "${AUTOWARE_PID}" 2>/dev/null; then
    echo "ERROR: Autoware failed to start"
    exit 1
fi

echo "Autoware is running"
echo ""

# Start single node replayer in background
echo "Starting ros2_single_node_replayer for ${NODE_NAME}..."
cd "${REPLAYER_PATH}"
python3 recorder.py "${package}" "${executable}" "${namespace}" "${NODE_NAME}" "" &
REPLAYER_PID=$!

echo "Replayer PID: ${REPLAYER_PID}"
echo "Waiting for replayer to initialize (5s)..."
sleep 5

# Check if replayer is running
if ! kill -0 "${REPLAYER_PID}" 2>/dev/null; then
    echo "ERROR: Single node replayer failed to start"
    exit 1
fi

echo "Replayer is running"
echo ""

# Play rosbag (foreground - blocks until complete)
echo "Starting rosbag playback at rate ${ROSBAG_RATE}..."
echo "=============================================="
ros2 bag play "${ROSBAG_PATH}" -r "${ROSBAG_RATE}" -s sqlite3

echo ""
echo "=============================================="
echo "Rosbag playback complete"
echo ""

# Send SIGINT to replayer to stop gracefully (equivalent to Ctrl-C)
echo "Stopping replayer with SIGINT..."
if kill -0 "${REPLAYER_PID}" 2>/dev/null; then
    kill -SIGINT "${REPLAYER_PID}"
    
    # Wait for replayer to finish (with timeout)
    WAIT_COUNT=0
    while kill -0 "${REPLAYER_PID}" 2>/dev/null && [ ${WAIT_COUNT} -lt 10 ]; do
        sleep 1
        WAIT_COUNT=$((WAIT_COUNT + 1))
    done
fi

# Find and copy output
echo ""
echo "Locating recorded data..."
RECORDING_DIR=$(ls -dt "${REPLAYER_PATH}/output"/*_${NODE_NAME} 2>/dev/null | head -1)

if [ -n "${RECORDING_DIR}" ] && [ -d "${RECORDING_DIR}" ]; then
    echo "Found recording: ${RECORDING_DIR}"
    
    # Copy to our output directory
    cp -r "${RECORDING_DIR}"/* "${OUTPUT_DIR}/"
    
    echo ""
    echo "=============================================="
    echo "Recording complete!"
    echo "=============================================="
    echo ""
    echo "Output saved to: ${OUTPUT_DIR}"
    echo ""
    echo "Contents:"
    ls -la "${OUTPUT_DIR}"
    echo ""
    echo "To replay the isolated node:"
    echo "  1. cd ${OUTPUT_DIR}"
    echo "  2. bash ros2_run_${package}_${executable}"
    echo "  3. In another terminal: ros2 bag play rosbag2_*"
else
    echo "WARNING: Could not find recording output"
    echo "Check ${REPLAYER_PATH}/output/ manually"
fi
