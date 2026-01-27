#!/bin/bash
# =============================================================================
# Run Perf with Clustered Metrics
# =============================================================================
# This script runs perf stat on isolated nodes using clustered metrics.
# Each cluster is run separately due to hardware counter limitations.
#
# Usage: ./run_perf_clusters.sh [node_name] [options]
#   node_name: Specific node to profile (or 'all' for all nodes)
#   --arm-only: Only run ARM-specific clusters
#   --generic-only: Only run generic clusters
#   --cluster NAME: Run specific cluster only
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/perf_config.yaml"
SINGLE_NODE_DIR="${SCRIPT_DIR}/../2_single_node_isolation/single_node_run"
OUTPUT_DIR="${SCRIPT_DIR}/perf_data"

# Parse arguments
NODE_NAME="${1:-all}"
ARM_ONLY=false
GENERIC_ONLY=false
SPECIFIC_CLUSTER=""

shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --arm-only) ARM_ONLY=true; shift ;;
        --generic-only) GENERIC_ONLY=true; shift ;;
        --cluster) SPECIFIC_CLUSTER="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "=============================================="
echo "Perf Profiling with Clustered Metrics"
echo "=============================================="

# Create output directories
mkdir -p "${OUTPUT_DIR}/raw"

# Check if perf is available
if ! command -v perf &> /dev/null; then
    echo "ERROR: perf command not found"
    echo "Install with: sudo apt install linux-tools-generic linux-tools-$(uname -r)"
    exit 1
fi

# Source ROS2 environment
source /opt/ros/humble/setup.bash
if [ -f "${HOME}/autoware/install/setup.bash" ]; then
    source "${HOME}/autoware/install/setup.bash"
fi

# Parse YAML config (simple parsing)
parse_clusters() {
    local arm_filter="$1"
    local in_cluster=false
    local cluster_name=""
    local is_arm=false
    local metrics=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]name:[[:space:]]*\"(.+)\" ]]; then
            # New cluster - output previous if exists
            if [ -n "$cluster_name" ] && [ -n "$metrics" ]; then
                if [ "$arm_filter" == "all" ] || \
                   ([ "$arm_filter" == "arm" ] && [ "$is_arm" == "true" ]) || \
                   ([ "$arm_filter" == "generic" ] && [ "$is_arm" == "false" ]); then
                    echo "${cluster_name}|${metrics}"
                fi
            fi
            cluster_name="${BASH_REMATCH[1]}"
            is_arm=false
            metrics=""
            in_cluster=true
        elif [[ "$line" =~ arm_specific:[[:space:]]*true ]]; then
            is_arm=true
        elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\"(.+)\" ]] && [ "$in_cluster" == "true" ]; then
            if [ -n "$metrics" ]; then
                metrics="${metrics},${BASH_REMATCH[1]}"
            else
                metrics="${BASH_REMATCH[1]}"
            fi
        fi
    done < "${CONFIG_FILE}"
    
    # Output last cluster
    if [ -n "$cluster_name" ] && [ -n "$metrics" ]; then
        if [ "$arm_filter" == "all" ] || \
           ([ "$arm_filter" == "arm" ] && [ "$is_arm" == "true" ]) || \
           ([ "$arm_filter" == "generic" ] && [ "$is_arm" == "false" ]); then
            echo "${cluster_name}|${metrics}"
        fi
    fi
}

# Determine filter
if [ "$ARM_ONLY" == "true" ]; then
    FILTER="arm"
elif [ "$GENERIC_ONLY" == "true" ]; then
    FILTER="generic"
else
    FILTER="all"
fi

# Get clusters
CLUSTERS=$(parse_clusters "$FILTER")

echo "Filter: ${FILTER}"
echo "Clusters to run: $(echo "$CLUSTERS" | wc -l)"
echo ""

# Function to run perf on a node
run_perf_on_node() {
    local node_name="$1"
    local node_dir="${SINGLE_NODE_DIR}/${node_name}"
    local node_output_dir="${OUTPUT_DIR}/raw/${node_name}"
    
    mkdir -p "${node_output_dir}"
    
    echo ""
    echo "===== Node: ${node_name} ====="
    
    # Find the run script and rosbag
    local run_script=$(find "${node_dir}" -name "ros2_run_*" -type f 2>/dev/null | head -1)
    local rosbag_dir=$(find "${node_dir}" -name "rosbag2_*" -type d 2>/dev/null | head -1)
    
    if [ -z "${run_script}" ] || [ -z "${rosbag_dir}" ]; then
        echo "  ERROR: Missing run script or rosbag in ${node_dir}"
        return 1
    fi
    
    # For each cluster
    while IFS='|' read -r cluster_name metrics; do
        if [ -n "$SPECIFIC_CLUSTER" ] && [ "$cluster_name" != "$SPECIFIC_CLUSTER" ]; then
            continue
        fi
        
        echo "  Cluster: ${cluster_name}"
        
        local output_file="${node_output_dir}/${cluster_name}.txt"
        local perf_events="${metrics}"
        
        # Run perf stat
        # We need to run the node and rosbag together
        # Create a temporary script
        local temp_script=$(mktemp)
        cat > "${temp_script}" << EOF
#!/bin/bash
cd "${node_dir}"
bash "$(basename "${run_script}")" &
NODE_PID=\$!
sleep 3
ros2 bag play "${rosbag_dir}" -s sqlite3
kill \$NODE_PID 2>/dev/null || true
wait \$NODE_PID 2>/dev/null || true
EOF
        chmod +x "${temp_script}"
        
        # Run perf stat
        perf stat -e "${perf_events}" -o "${output_file}" bash "${temp_script}" 2>&1 || {
            echo "    WARNING: Some events may not be available"
            # Try running with available events only
            perf stat -e "${perf_events}" -o "${output_file}" --no-aggr bash "${temp_script}" 2>&1 || true
        }
        
        rm "${temp_script}"
        
        if [ -f "${output_file}" ]; then
            echo "    Output: ${output_file}"
        fi
    done <<< "${CLUSTERS}"
}

# Get list of nodes to profile
if [ "${NODE_NAME}" == "all" ]; then
    NODES=$(ls -d "${SINGLE_NODE_DIR}"/*/ 2>/dev/null | xargs -n1 basename)
else
    NODES="${NODE_NAME}"
fi

# Check if any nodes available
if [ -z "${NODES}" ]; then
    echo "ERROR: No recorded nodes found in ${SINGLE_NODE_DIR}"
    echo "Run single node isolation first"
    exit 1
fi

# Profile each node
for node in ${NODES}; do
    run_perf_on_node "${node}" || echo "Failed to profile ${node}"
done

echo ""
echo "=============================================="
echo "Perf profiling complete!"
echo "=============================================="
echo ""
echo "Raw data: ${OUTPUT_DIR}/raw/"
echo ""
echo "Next steps:"
echo "  1. python3 clean_perf_data.py"
echo "  2. python3 analyze_perf.py"
echo "  3. python3 compute_agnostic_metrics.py"
