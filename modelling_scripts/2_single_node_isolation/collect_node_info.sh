#!/bin/bash
# =============================================================================
# Collect Node Information Script
# =============================================================================
# This script runs the node_info_to_csv.py script to collect metadata about
# all running ROS 2 nodes (package name, executable, namespace, node name).
#
# IMPORTANT: Run this script while Autoware is fully running.
#
# Usage: ./collect_node_info.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
IDENTIFY_NODES_DIR="${PROJECT_ROOT}/identify_nodes"

echo "=============================================="
echo "Collect Node Information"
echo "=============================================="

# Check if identify_nodes script exists
if [ ! -f "${IDENTIFY_NODES_DIR}/node_info_to_csv.py" ]; then
    echo "ERROR: node_info_to_csv.py not found at ${IDENTIFY_NODES_DIR}"
    exit 1
fi

# Source ROS2 environment
if [ -f "/opt/ros/humble/setup.bash" ]; then
    source /opt/ros/humble/setup.bash
fi
if [ -f "${HOME}/autoware/install/setup.bash" ]; then
    source "${HOME}/autoware/install/setup.bash"
fi

# Check if ROS 2 is running
echo "Checking for running ROS 2 nodes..."
NODE_COUNT=$(ros2 node list 2>/dev/null | wc -l)

if [ "${NODE_COUNT}" -eq 0 ]; then
    echo ""
    echo "WARNING: No ROS 2 nodes detected!"
    echo ""
    echo "Make sure Autoware is running before executing this script."
    echo "Start Autoware with:"
    echo "  ros2 launch autoware_launch logging_simulator.launch.xml \\"
    echo "    map_path:=\$HOME/autoware_map/sample-map-rosbag \\"
    echo "    vehicle_model:=sample_vehicle sensor_model:=sample_sensor_kit"
    echo ""
    exit 1
fi

echo "Found ${NODE_COUNT} nodes running"
echo ""

# Run the Python script
echo "Running node_info_to_csv.py..."
cd "${SCRIPT_DIR}"
python3 "${IDENTIFY_NODES_DIR}/node_info_to_csv.py"

# Move output to this directory if it was created elsewhere
if [ -f "${IDENTIFY_NODES_DIR}/ros2_node_inventory.csv" ]; then
    mv "${IDENTIFY_NODES_DIR}/ros2_node_inventory.csv" "${SCRIPT_DIR}/"
fi

# Verify output
if [ -f "${SCRIPT_DIR}/ros2_node_inventory.csv" ]; then
    echo ""
    echo "=============================================="
    echo "Node inventory collection complete!"
    echo "=============================================="
    echo ""
    echo "Output: ${SCRIPT_DIR}/ros2_node_inventory.csv"
    echo ""
    echo "Preview (first 10 lines):"
    head -n 10 "${SCRIPT_DIR}/ros2_node_inventory.csv"
    echo ""
    echo "Total nodes recorded: $(tail -n +2 "${SCRIPT_DIR}/ros2_node_inventory.csv" | wc -l)"
else
    echo "ERROR: Failed to create ros2_node_inventory.csv"
    exit 1
fi
