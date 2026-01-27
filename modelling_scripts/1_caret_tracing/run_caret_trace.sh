#!/bin/bash
# =============================================================================
# CARET Trace Recording Script
# =============================================================================
# This script launches Autoware with CARET tracing enabled and records
# trace data for performance analysis.
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

# Default values
MAP_PATH="${HOME}/autoware_map/sample-map-rosbag"
ROSBAG_PATH="${HOME}/autoware_map/sample-rosbag"
OUTPUT_DIR="$(dirname "$0")/trace_data"
ROSBAG_RATE="0.2"
POST_DURATION=5

# Parse arguments
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

# Create output directory with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TRACE_DIR="${OUTPUT_DIR}/caret_trace_${TIMESTAMP}"
mkdir -p "${TRACE_DIR}"

echo "=============================================="
echo "CARET Trace Recording"
echo "=============================================="
echo "Map path:      ${MAP_PATH}"
echo "Rosbag path:   ${ROSBAG_PATH}"
echo "Output dir:    ${TRACE_DIR}"
echo "Rosbag rate:   ${ROSBAG_RATE}"
echo "=============================================="

# Source ROS2 and CARET environment
# shellcheck source=/dev/null
if [ -f "/opt/ros/humble/setup.bash" ]; then
    source /opt/ros/humble/setup.bash
fi
if [ -f "${HOME}/autoware/install/setup.bash" ]; then
    source "${HOME}/autoware/install/setup.bash"
fi
if [ -f "${HOME}/ros2_caret_ws/install/local_setup.bash" ]; then
    source "${HOME}/ros2_caret_ws/install/local_setup.bash"
fi

# Set CARET environment variables
export LD_PRELOAD=$(find /opt/ros/humble -name 'libcaret*.so' 2>/dev/null | head -1)
if [ -z "$LD_PRELOAD" ] && [ -d "${HOME}/ros2_caret_ws" ]; then
    export LD_PRELOAD=$(find "${HOME}/ros2_caret_ws" -name 'libcaret*.so' 2>/dev/null | head -1)
fi

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "Cleaning up..."
    # Kill all background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    wait 2>/dev/null || true
    echo "Trace data saved to: ${TRACE_DIR}"
}
trap cleanup EXIT

# Start LTTng session for CARET
echo "Starting LTTng session..."
export CARET_SESSION_NAME="autoware_trace_${TIMESTAMP}"

# Create LTTng session
lttng create "${CARET_SESSION_NAME}" --output="${TRACE_DIR}/lttng"

# Enable CARET tracepoints
lttng enable-event -u 'ros2:*'
lttng enable-event -u 'ros2_caret:*'

# Start tracing
lttng start

echo "LTTng session started: ${CARET_SESSION_NAME}"

# Launch Autoware with CARET support (headless mode)
echo "Launching Autoware with CARET tracing (headless mode)..."
ros2 launch caret_autoware_launch autoware.launch.xml \
    map_path:="${MAP_PATH}" \
    vehicle_model:=sample_vehicle \
    sensor_model:=sample_sensor_kit \
    rviz:=false \
    caret_session:="${CARET_SESSION_NAME}" &
AUTOWARE_PID=$!

# Wait for Autoware to initialize
echo "Waiting for Autoware to initialize (30 seconds)..."
sleep 30

# Check if Autoware is still running
if ! kill -0 $AUTOWARE_PID 2>/dev/null; then
    echo "ERROR: Autoware failed to start"
    exit 1
fi

echo "Autoware is running. Starting rosbag playback..."

# Play rosbag
ros2 bag play "${ROSBAG_PATH}" -r "${ROSBAG_RATE}" -s sqlite3

echo "Rosbag playback completed. Recording for ${POST_DURATION} more seconds..."
sleep "${POST_DURATION}"

# Stop LTTng session
echo "Stopping LTTng session..."
lttng stop
lttng destroy "${CARET_SESSION_NAME}"

# Kill Autoware
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
echo "  2. Run: python3 visualize_caret.py ${TRACE_DIR}"
echo "  3. Run: python3 export_node_latency.py ${TRACE_DIR}"
