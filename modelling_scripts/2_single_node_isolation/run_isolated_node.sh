#!/bin/bash
# =============================================================================
# Run Isolated Node Script
# =============================================================================
# Template script to run an isolated node for profiling.
# This script is for running the node AFTER it has been recorded.
#
# Usage: ./run_isolated_node.sh <node_name>
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check arguments
if [ -z "$1" ]; then
    echo "Usage: ./run_isolated_node.sh <node_name>"
    echo ""
    echo "Available recorded nodes:"
    ls -d "${SCRIPT_DIR}/single_node_run"/*/ 2>/dev/null | xargs -n1 basename || echo "  (none)"
    exit 1
fi

NODE_NAME="$1"
NODE_DIR="${SCRIPT_DIR}/single_node_run/${NODE_NAME}"

# Check node directory exists
if [ ! -d "${NODE_DIR}" ]; then
    echo "ERROR: Node directory not found: ${NODE_DIR}"
    echo "Run record_single_node.sh first to record the node"
    exit 1
fi

echo "=============================================="
echo "Run Isolated Node: ${NODE_NAME}"
echo "=============================================="

# Source ROS2 environment
source /opt/ros/humble/setup.bash
source "${HOME}/autoware/install/setup.bash"

# Find the run command
RUN_SCRIPT=$(find "${NODE_DIR}" -name "ros2_run_*" -type f | head -1)
if [ -z "${RUN_SCRIPT}" ]; then
    echo "ERROR: No ros2_run_* script found in ${NODE_DIR}"
    exit 1
fi

# Find the rosbag
ROSBAG_DIR=$(find "${NODE_DIR}" -name "rosbag2_*" -type d | head -1)
if [ -z "${ROSBAG_DIR}" ]; then
    echo "ERROR: No rosbag2_* directory found in ${NODE_DIR}"
    exit 1
fi

echo "Run script: ${RUN_SCRIPT}"
echo "Rosbag: ${ROSBAG_DIR}"
echo ""
echo "=============================================="
echo "Instructions:"
echo "=============================================="
echo ""
echo "This requires TWO terminals:"
echo ""
echo "Terminal 1 - Run the node:"
echo "  source /opt/ros/humble/setup.bash"
echo "  source \$HOME/autoware/install/setup.bash"
echo "  bash ${RUN_SCRIPT}"
echo ""
echo "Terminal 2 - Play the rosbag:"
echo "  source /opt/ros/humble/setup.bash"
echo "  ros2 bag play ${ROSBAG_DIR}"
echo ""
echo "=============================================="
echo ""
echo "For PERF profiling, use the scripts in 3_perf_profiling/"
echo ""

# Ask user what to do
read -p "Would you like to start the node now? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Starting node... (use Ctrl+C to stop)"
    echo "Remember to play the rosbag in another terminal!"
    echo ""
    cd "${NODE_DIR}"
    bash "$(basename "${RUN_SCRIPT}")"
fi
