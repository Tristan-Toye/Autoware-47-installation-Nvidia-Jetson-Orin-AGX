#!/bin/bash
# =============================================================================
# CARET Trace Recording Script
# =============================================================================
# Launches Autoware via caret_autoware_launch (which handles LTTng setup
# internally via caret.launch.py), plays the rosbag, then copies the
# trace output to a local directory.
#
# Usage: ./run_caret_trace.sh [options]
#   Options:
#     --map-path PATH      Path to map folder (default: $HOME/autoware_map/sample-map-rosbag)
#     --rosbag PATH        Path to rosbag (default: $HOME/autoware_map/sample-rosbag)
#     --output-dir DIR     Output directory for trace data (default: ./trace_data)
#     --rosbag-rate RATE   Rosbag playback rate (default: 0.2)
#     --duration SEC       Duration to record after rosbag completes (default: 5)
# =============================================================================

set -e

MAP_PATH="${HOME}/autoware_map/sample-map-rosbag"
ROSBAG_PATH="${HOME}/autoware_map/sample-rosbag"
OUTPUT_DIR="$(cd "$(dirname "$0")" && pwd)/trace_data"
ROSBAG_RATE="0.2"
POST_DURATION=5

while [[ $# -gt 0 ]]; do
    case $1 in
        --map-path) MAP_PATH="$2"; shift 2 ;;
        --rosbag) ROSBAG_PATH="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --rosbag-rate) ROSBAG_RATE="$2"; shift 2 ;;
        --duration) POST_DURATION="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TRACE_DIR="${OUTPUT_DIR}/caret_trace_${TIMESTAMP}"
CARET_SESSION_NAME="autoware_trace_${TIMESTAMP}"
mkdir -p "${TRACE_DIR}"

echo "=============================================="
echo "CARET Trace Recording (caret_autoware_launch)"
echo "=============================================="
echo "Map path:       ${MAP_PATH}"
echo "Rosbag path:    ${ROSBAG_PATH}"
echo "Output dir:     ${TRACE_DIR}"
echo "Rosbag rate:    ${ROSBAG_RATE}"
echo "Session name:   ${CARET_SESSION_NAME}"
echo "=============================================="

# Source ROS2, Autoware, and CARET environments
source /opt/ros/humble/setup.bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/autoware/install/setup.bash"
source "${PROJECT_ROOT}/ros2_caret_ws/install/local_setup.bash"
export LD_PRELOAD="${PROJECT_ROOT}/ros2_caret_ws/install/lib/libcaret.so"

cleanup() {
    echo ""
    echo "Cleaning up..."
    jobs -p | xargs -r kill 2>/dev/null || true
    sleep 2
    wait 2>/dev/null || true

    # Copy trace data from default location to our output directory
    ROS_TRACE_DIR="${HOME}/.ros/tracing/${CARET_SESSION_NAME}"
    if [ -d "${ROS_TRACE_DIR}" ]; then
        echo "Copying trace from ${ROS_TRACE_DIR} to ${TRACE_DIR}/lttng"
        cp -r "${ROS_TRACE_DIR}" "${TRACE_DIR}/lttng"
    else
        echo "WARNING: Trace directory not found at ${ROS_TRACE_DIR}"
        echo "Checking for any active LTTng sessions..."
        lttng stop "${CARET_SESSION_NAME}" 2>/dev/null || true
        lttng destroy "${CARET_SESSION_NAME}" 2>/dev/null || true
        if [ -d "${ROS_TRACE_DIR}" ]; then
            cp -r "${ROS_TRACE_DIR}" "${TRACE_DIR}/lttng"
        fi
    fi
    echo "Trace data saved to: ${TRACE_DIR}"
}
trap cleanup EXIT

# Launch Autoware with CARET tracing via caret_autoware_launch
echo "Launching Autoware with CARET tracing (headless mode)..."
ros2 launch caret_autoware_launch logging_simulator.launch.xml \
    map_path:="${MAP_PATH}" \
    vehicle_model:=sample_vehicle \
    sensor_model:=sample_sensor_kit \
    rviz:=false \
    caret_session:="${CARET_SESSION_NAME}" &
AUTOWARE_PID=$!

echo "Waiting for Autoware to initialize (45 seconds)..."
sleep 45

if ! kill -0 $AUTOWARE_PID 2>/dev/null; then
    echo "ERROR: Autoware failed to start"
    exit 1
fi

echo "Autoware is running. Starting rosbag playback..."
ros2 bag play "${ROSBAG_PATH}" -r "${ROSBAG_RATE}" -s sqlite3

echo "Rosbag playback completed. Recording for ${POST_DURATION} more seconds..."
sleep "${POST_DURATION}"

# Stop Autoware (cleanup trap handles trace copy)
echo "Stopping Autoware..."
kill $AUTOWARE_PID 2>/dev/null || true
wait $AUTOWARE_PID 2>/dev/null || true

echo ""
echo "=============================================="
echo "CARET trace recording complete!"
echo "Trace data location: ${TRACE_DIR}"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Run: ./analyze_caret_results.sh ${TRACE_DIR}"
echo "  2. Run: python3 visualize_caret.py"
echo "  3. Run: python3 export_node_latency.py"
