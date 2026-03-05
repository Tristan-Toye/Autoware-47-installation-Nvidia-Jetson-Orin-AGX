#!/bin/bash
# =============================================================================
# Record Standalone Nodes (non-container nodes only)
# =============================================================================
# Records the 6 nodes that run as standalone processes (not inside
# component containers). Autoware must already be running.
#
# Usage: ./record_standalone_nodes.sh
# =============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/single_node_run"
REPLAYER_DIR="${PROJECT_ROOT}/ros2_single_node_replayer"
REMAP_FILE="no_remapping.yaml"
ROSBAG_PATH="${HOME}/autoware_map/sample-rosbag"
ROSBAG_RATE="0.2"

source /opt/ros/humble/setup.bash
source "${PROJECT_ROOT}/autoware/install/setup.bash"

mkdir -p "${OUTPUT_DIR}"

# Discoverable standalone nodes: short_name|package|executable|namespace
NODES=(
    "ndt_scan_matcher|autoware_ndt_scan_matcher|autoware_ndt_scan_matcher_node|/localization/pose_estimator"
    "ekf_localizer|autoware_ekf_localizer|autoware_ekf_localizer_node|/localization/pose_twist_fusion_filter"
    "multi_object_tracker|autoware_multi_object_tracker|multi_object_tracker_node|/perception/object_recognition/tracking"
    "map_based_prediction|autoware_map_based_prediction|map_based_prediction|/perception/object_recognition/prediction"
    "shape_estimation|autoware_shape_estimation|shape_estimation_node|/perception/object_recognition/detection/clustering"
    "velocity_smoother|autoware_velocity_smoother|velocity_smoother|/planning/scenario_planning"
)

TOTAL=${#NODES[@]}
SUCCESS=0

for i in "${!NODES[@]}"; do
    IFS='|' read -r short_name package executable namespace <<< "${NODES[$i]}"
    IDX=$((i + 1))

    echo ""
    echo "=============================================="
    echo "[${IDX}/${TOTAL}] Recording: ${short_name}"
    echo "  Package: ${package}"
    echo "  Executable: ${executable}"
    echo "  Namespace: ${namespace}"
    echo "=============================================="

    NODE_DIR="${OUTPUT_DIR}/${short_name}"
    mkdir -p "${NODE_DIR}"

    # Verify node is visible
    if ! ros2 node info "${namespace}/${short_name}" >/dev/null 2>&1; then
        echo "  WARNING: Node ${namespace}/${short_name} not discoverable, skipping."
        continue
    fi

    # Run recorder in background
    echo "  Starting recorder..."
    cd "${REPLAYER_DIR}"
    python3 recorder.py "${package}" "${executable}" "${namespace}" "${short_name}" "${REMAP_FILE}" &
    RECORDER_PID=$!
    sleep 10

    if ! kill -0 "${RECORDER_PID}" 2>/dev/null; then
        echo "  WARNING: Recorder failed to start."
        continue
    fi

    # Play rosbag
    echo "  Playing rosbag (rate=${ROSBAG_RATE})..."
    ros2 bag play "${ROSBAG_PATH}" -r "${ROSBAG_RATE}" -s sqlite3 2>&1 || true

    echo "  Rosbag done. Stopping recorder..."
    sleep 3
    kill -SIGINT "${RECORDER_PID}" 2>/dev/null || true

    WAIT=0
    while kill -0 "${RECORDER_PID}" 2>/dev/null && [ ${WAIT} -lt 15 ]; do
        sleep 1
        WAIT=$((WAIT + 1))
    done
    kill -9 "${RECORDER_PID}" 2>/dev/null || true
    wait "${RECORDER_PID}" 2>/dev/null || true

    # Copy output
    LATEST=$(ls -dt "${REPLAYER_DIR}/output"/*"${short_name}"* 2>/dev/null | head -1)
    if [ -n "${LATEST}" ] && [ -d "${LATEST}" ]; then
        cp -r "${LATEST}"/* "${NODE_DIR}/" 2>/dev/null || true
        SUCCESS=$((SUCCESS + 1))
        echo "  SUCCESS: Recorded to ${NODE_DIR}/"
        ls "${NODE_DIR}/"
    else
        echo "  WARNING: No output found."
    fi

    cd "${SCRIPT_DIR}"
done

echo ""
echo "=============================================="
echo "Recording complete: ${SUCCESS}/${TOTAL} succeeded"
echo "Output: ${OUTPUT_DIR}/"
echo "=============================================="
