#!/bin/bash
# =============================================================================
# CARET Results Analysis Script
# =============================================================================
# This script validates CARET trace data and prepares it for analysis.
#
# Usage: ./analyze_caret_results.sh [TRACE_DIR]
#   TRACE_DIR: Path to CARET trace directory (default: latest in ./trace_data)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find trace directory
if [ -n "$1" ]; then
    TRACE_DIR="$1"
else
    # Find latest trace directory
    TRACE_DIR=$(ls -dt "${SCRIPT_DIR}/trace_data"/caret_trace_* 2>/dev/null | head -1)
    if [ -z "${TRACE_DIR}" ]; then
        echo "ERROR: No trace directory found. Run run_caret_trace.sh first."
        exit 1
    fi
fi

if [ ! -d "${TRACE_DIR}" ]; then
    echo "ERROR: Trace directory not found: ${TRACE_DIR}"
    exit 1
fi

echo "=============================================="
echo "CARET Results Analysis"
echo "=============================================="
echo "Trace directory: ${TRACE_DIR}"
echo "=============================================="

# Source environments
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

# Create results directory
RESULTS_DIR="${SCRIPT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

# Find LTTng trace path
LTTNG_PATH=$(find "${TRACE_DIR}" -name "ust" -type d 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "${LTTNG_PATH}" ]; then
    LTTNG_PATH="${TRACE_DIR}/lttng"
fi

echo "LTTng trace path: ${LTTNG_PATH}"

# Validate trace data using CARET CLI
echo ""
echo "Validating trace data..."
if command -v ros2 &> /dev/null; then
    ros2 caret check_ctf "${LTTNG_PATH}" 2>&1 | tee "${RESULTS_DIR}/validation_report.txt" || true
else
    echo "WARNING: ros2 command not available, skipping validation"
fi

# Export architecture file if caret_autoware_launch config exists
ARCH_DIR="${HOME}/autoware/src/launcher/caret_autoware_launch/architecture"
if [ -d "${ARCH_DIR}" ]; then
    ARCH_FILE=$(find "${ARCH_DIR}" -name "*.yaml" -type f 2>/dev/null | head -1)
    if [ -n "${ARCH_FILE}" ]; then
        echo ""
        echo "Found architecture file: ${ARCH_FILE}"
        cp "${ARCH_FILE}" "${RESULTS_DIR}/architecture.yaml"
        echo "Copied to: ${RESULTS_DIR}/architecture.yaml"
    fi
fi

# Create symbolic link to latest trace
ln -sfn "${TRACE_DIR}" "${SCRIPT_DIR}/trace_data/latest"

# Write analysis config file
cat > "${RESULTS_DIR}/analysis_config.yaml" << EOF
# CARET Analysis Configuration
trace_dir: "${TRACE_DIR}"
lttng_path: "${LTTNG_PATH}"
architecture_file: "${RESULTS_DIR}/architecture.yaml"
output_dir: "${RESULTS_DIR}"

# Analysis parameters
lstrip_s: 5  # Remove first 5 seconds of data
rstrip_s: 2  # Remove last 2 seconds of data

# Graph output settings
graphs_dir: "${SCRIPT_DIR}/graphs"
EOF

echo ""
echo "=============================================="
echo "Analysis preparation complete!"
echo "=============================================="
echo ""
echo "Configuration saved to: ${RESULTS_DIR}/analysis_config.yaml"
echo ""
echo "Next steps:"
echo "  1. Run: python3 visualize_caret.py"
echo "  2. Run: python3 export_node_latency.py"
