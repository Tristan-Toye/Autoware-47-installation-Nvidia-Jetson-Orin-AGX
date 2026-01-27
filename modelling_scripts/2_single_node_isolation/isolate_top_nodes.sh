#!/bin/bash
# =============================================================================
# Isolate Top Nodes Script
# =============================================================================
# This script selects the top N nodes by latency from the merged CSV and
# prepares commands for recording each node with ros2_single_node_replayer.
#
# Usage: ./isolate_top_nodes.sh [N]
#   N: Number of top nodes to isolate (default: 10)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"
MERGED_CSV="${SCRIPT_DIR}/merged_node_data.csv"

# Parse arguments
TOP_N="${1:-10}"

echo "=============================================="
echo "Isolate Top ${TOP_N} Nodes"
echo "=============================================="

# Check merged CSV exists
if [ ! -f "${MERGED_CSV}" ]; then
    echo "ERROR: merged_node_data.csv not found"
    echo "Run: python3 merge_latency_with_info.py"
    exit 1
fi

# Create output directory
OUTPUT_DIR="${SCRIPT_DIR}/single_node_run"
mkdir -p "${OUTPUT_DIR}"

# Parse YAML config for replayer path (simple parsing)
REPLAYER_PATH=$(grep "replayer_path:" "${CONFIG_FILE}" | cut -d'"' -f2 | envsubst)
if [ -z "${REPLAYER_PATH}" ]; then
    REPLAYER_PATH="${HOME}/ros2_single_node_replayer"
fi

# Generate recording commands for top N nodes
echo ""
echo "Generating recording commands for top ${TOP_N} nodes..."
echo ""

# Create a master script to record all nodes
MASTER_SCRIPT="${OUTPUT_DIR}/record_all_nodes.sh"
cat > "${MASTER_SCRIPT}" << 'HEADER'
#!/bin/bash
# =============================================================================
# Master Script to Record All Top Nodes
# =============================================================================
# This script records each node one at a time.
# Run while Autoware is NOT running - each node recording will start Autoware.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Recording all top nodes..."
echo ""

HEADER

# Read CSV and process top N nodes (skip header)
COUNT=0
tail -n +2 "${MERGED_CSV}" | while IFS=',' read -r node_name short_name namespace package executable latency_ms pct_total pct_longest in_longest; do
    COUNT=$((COUNT + 1))
    
    if [ ${COUNT} -gt ${TOP_N} ]; then
        break
    fi
    
    # Clean up values (remove quotes if present)
    node_name=$(echo "${node_name}" | tr -d '"')
    short_name=$(echo "${short_name}" | tr -d '"')
    namespace=$(echo "${namespace}" | tr -d '"')
    package=$(echo "${package}" | tr -d '"')
    executable=$(echo "${executable}" | tr -d '"')
    latency_ms=$(echo "${latency_ms}" | tr -d '"')
    
    # Skip if package is Unknown
    if [ "${package}" == "Unknown" ]; then
        echo "  [${COUNT}] SKIP: ${short_name} (package unknown)"
        continue
    fi
    
    # Create node-specific directory
    NODE_DIR="${OUTPUT_DIR}/${short_name}"
    mkdir -p "${NODE_DIR}"
    
    # Create recording script for this node
    NODE_SCRIPT="${NODE_DIR}/record.sh"
    cat > "${NODE_SCRIPT}" << EOF
#!/bin/bash
# Recording script for: ${short_name}
# Package: ${package}
# Executable: ${executable}
# Namespace: ${namespace}
# Latency: ${latency_ms} ms

set -e

SCRIPT_DIR="\$(cd -- "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="\$(dirname "\$(dirname "\${SCRIPT_DIR}")")"

# Source environments
source /opt/ros/humble/setup.bash
source \${HOME}/autoware/install/setup.bash

# Set remapping file path (empty for now - can be customized)
REMAP_FILE=""

echo "Recording node: ${short_name}"
echo "Package: ${package}"
echo "Executable: ${executable}"
echo "Namespace: ${namespace}"

# Navigate to replayer directory
cd "${REPLAYER_PATH}"

# Start recording
# Format: python3 recorder.py <package> <executable> <namespace> <node_name> <remap_file>
python3 recorder.py "${package}" "${executable}" "${namespace}" "${short_name}" "\${REMAP_FILE}"

echo ""
echo "Recording complete for ${short_name}"
echo "Output saved to: ${REPLAYER_PATH}/output/"
EOF
    
    chmod +x "${NODE_SCRIPT}"
    
    # Add to master script
    echo "echo '[${COUNT}/${TOP_N}] Recording: ${short_name}'" >> "${MASTER_SCRIPT}"
    echo "# Uncomment below to auto-run:" >> "${MASTER_SCRIPT}"
    echo "# \"\${SCRIPT_DIR}/${short_name}/record.sh\"" >> "${MASTER_SCRIPT}"
    echo "" >> "${MASTER_SCRIPT}"
    
    echo "  [${COUNT}] ${short_name} - ${package}/${executable} (${latency_ms} ms)"
done

chmod +x "${MASTER_SCRIPT}"

echo ""
echo "=============================================="
echo "Isolation preparation complete!"
echo "=============================================="
echo ""
echo "Created recording scripts in: ${OUTPUT_DIR}"
echo ""
echo "To record a single node:"
echo "  1. Start Autoware in one terminal"
echo "  2. Run the recording script: ./single_node_run/<node_name>/record.sh"
echo "  3. Play rosbag in another terminal"
echo "  4. Wait for rosbag to complete, script will auto-terminate"
echo ""
echo "Or use record_single_node.sh for automated recording:"
echo "  ./record_single_node.sh <node_name>"
