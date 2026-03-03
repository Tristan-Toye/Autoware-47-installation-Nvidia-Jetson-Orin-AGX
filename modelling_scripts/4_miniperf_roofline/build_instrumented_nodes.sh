#!/bin/bash
# =============================================================================
# Build Instrumented ROS 2 Nodes for miniperf Roofline Analysis
# =============================================================================
# This script recompiles isolated Autoware nodes with the miniperf Clang
# pass plugin injected at compile time. The plugin inserts lightweight LLVM
# IR instrumentation that counts FLOPs and memory bytes per loop at runtime,
# which is what the miniperf roofline scenario collects in pass 2.
#
# Background:
#   The agnostic roofline methodology (Batashev et al.) compiles the target
#   program with an LLVM pass that annotates inner loops with counters for:
#     - Floating-point operations (FLOP count)
#     - Integer operations
#     - Memory load/store bytes
#   These counts are accumulated at runtime and stored into a shared-memory
#   region read by the miniperf `collector` library (libcollector.so).
#   In pass 1, miniperf records PMU hardware counters (cycles, bandwidth).
#   In pass 2, it reruns the instrumented binary to get the loop statistics.
#   Combined, this gives arithmetic intensity (FLOPs/byte) per hotspot.
#
# Usage:
#   ./build_instrumented_nodes.sh [node_name|all] [--dry-run]
#   node_name : name from miniperf_config.yaml (e.g. ekf_localizer)
#               or 'all' to rebuild every target node
#   --dry-run : print the build commands without executing them
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/miniperf_config.yaml"

# ─── Parse arguments ──────────────────────────────────────────────────────────
TARGET_NODE="${1:-all}"
DRY_RUN=false
shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ─── Resolve config values (simple YAML parsing)  ─────────────────────────────
parse_yaml_value() {
    local key="$1"
    grep "^  ${key}:" "${CONFIG_FILE}" | head -1 | sed "s/.*: //" | tr -d '"' | envsubst
}

MINIPERF_ROOT=$(parse_yaml_value "miniperf_root")
PLUGIN_SO=$(parse_yaml_value "clang_plugin")
LIBCOLLECTOR_DIR="${MINIPERF_ROOT}/target/release"
AUTOWARE_ROOT=$(parse_yaml_value "autoware_root")
AUTOWARE_SETUP=$(parse_yaml_value "autoware_setup")
ROS2_SETUP=$(parse_yaml_value "ros2_setup")
CLANG_VER=$(grep "clang_version:" "${CONFIG_FILE}" | head -1 | awk '{print $2}' | tr -d '"')
OPT_LEVEL=$(grep "optimization_level:" "${CONFIG_FILE}" | head -1 | awk '{print $2}' | tr -d '"')
DEBUG_FLAG=$(grep "debug_info:" "${CONFIG_FILE}" | head -1 | awk '{print $2}' | tr -d '"')
EXTRA_FLAGS=$(grep "extra_cxxflags:" "${CONFIG_FILE}" | head -1 | sed 's/.*: //' | tr -d '"')
BUILD_BASE=$(grep "colcon_build_base:" "${CONFIG_FILE}" | head -1 | awk '{print $2}' | tr -d '"')
INSTALL_BASE=$(grep "colcon_install_base:" "${CONFIG_FILE}" | head -1 | awk '{print $2}' | tr -d '"')
OUTPUT_DIR="${SCRIPT_DIR}/instrumented_bins"

echo "============================================================"
echo "  Build Instrumented Nodes — miniperf Roofline"
echo "============================================================"
echo "  Plugin SO      : ${PLUGIN_SO}"
echo "  libcollector   : ${LIBCOLLECTOR_DIR}/libcollector.so"
echo "  Clang version  : ${CLANG_VER}"
echo "  Autoware root  : ${AUTOWARE_ROOT}"
echo "  Output dir     : ${OUTPUT_DIR}"
echo "  Dry run        : ${DRY_RUN}"
echo "============================================================"
echo ""

# ─── Pre-flight checks ────────────────────────────────────────────────────────
check_prerequisites() {
    local fail=false

    if ! command -v "clang-${CLANG_VER}" &>/dev/null; then
        echo "ERROR: clang-${CLANG_VER} not found. Run install_miniperf.sh first."
        fail=true
    fi

    if [ ! -f "${PLUGIN_SO}" ]; then
        echo "ERROR: Clang plugin not found: ${PLUGIN_SO}"
        echo "       Run install_miniperf.sh first."
        fail=true
    fi

    if [ ! -f "${LIBCOLLECTOR_DIR}/libcollector.so" ]; then
        echo "ERROR: libcollector.so not found: ${LIBCOLLECTOR_DIR}/libcollector.so"
        fail=true
    fi

    if [ ! -f "${AUTOWARE_SETUP}" ]; then
        echo "ERROR: Autoware setup not found: ${AUTOWARE_SETUP}"
        echo "       Ensure Autoware is built at: ${AUTOWARE_ROOT}"
        fail=true
    fi

    if [ "${fail}" = true ]; then
        exit 1
    fi
}

if [ "${DRY_RUN}" = false ]; then
    check_prerequisites
fi

# ─── Source ROS 2 + Autoware environment ─────────────────────────────────────
# shellcheck source=/dev/null
source "${ROS2_SETUP}" 2>/dev/null || true
# shellcheck source=/dev/null
source "${AUTOWARE_SETUP}" 2>/dev/null || true

# ─── Compiler flags including the miniperf plugin ─────────────────────────────
# The plugin flag tells Clang to load and run the miniperf LLVM pass over
# each translation unit's IR before code generation.
MINIPERF_CXXFLAGS="${OPT_LEVEL} ${DEBUG_FLAG} ${EXTRA_FLAGS} \
    -Xclang -fpass-plugin=${PLUGIN_SO}"

MINIPERF_LDFLAGS="-L${LIBCOLLECTOR_DIR} -lcollector \
    -Wl,-rpath,${LIBCOLLECTOR_DIR}"

mkdir -p "${OUTPUT_DIR}"

# ─── Build a single node package ──────────────────────────────────────────────
build_node() {
    local node_name="$1"
    local package="$2"
    local node_output="${OUTPUT_DIR}/${node_name}"

    echo ""
    echo "===== Building: ${node_name} (package: ${package}) ====="

    mkdir -p "${node_output}"

    # colcon build for a single package with instrumented flags
    local build_cmd
    build_cmd="colcon build \
        --packages-select ${package} \
        --cmake-args \
            -DCMAKE_C_COMPILER=clang-${CLANG_VER} \
            -DCMAKE_CXX_COMPILER=clang++-${CLANG_VER} \
            -DCMAKE_CXX_FLAGS='${MINIPERF_CXXFLAGS}' \
            -DCMAKE_EXE_LINKER_FLAGS='${MINIPERF_LDFLAGS}' \
            -DCMAKE_SHARED_LINKER_FLAGS='${MINIPERF_LDFLAGS}' \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        --build-base ${AUTOWARE_ROOT}/${BUILD_BASE}/${package} \
        --install-base ${AUTOWARE_ROOT}/${INSTALL_BASE}/${package}"

    if [ "${DRY_RUN}" = true ]; then
        echo "[DRY-RUN] Would run from ${AUTOWARE_ROOT}:"
        echo "  ${build_cmd}"
        echo "[DRY-RUN] Would copy instrumented binaries to: ${node_output}"
        return 0
    fi

    # Run colcon from Autoware root
    cd "${AUTOWARE_ROOT}"
    eval "${build_cmd}" 2>&1 | tee "${node_output}/build.log"

    # Copy the resulting instrumented binary and shared libs
    local install_dir="${AUTOWARE_ROOT}/${INSTALL_BASE}/${package}"
    if [ -d "${install_dir}" ]; then
        echo "  Copying instrumented files to ${node_output}/"
        cp -r "${install_dir}/." "${node_output}/"
        echo "  ✓ Done: ${node_name}"
    else
        echo "  WARNING: Install directory not found: ${install_dir}"
        echo "           Check build.log for errors."
    fi

    cd "${SCRIPT_DIR}"
}

# ─── Parse node list from YAML ────────────────────────────────────────────────
# Extract node_name and package pairs from config
parse_nodes() {
    local in_node=false
    local node_name="" package=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]node_name:[[:space:]]*\"(.+)\" ]]; then
            # Flush previous pair
            if [ -n "${node_name}" ] && [ -n "${package}" ]; then
                echo "${node_name}|${package}"
            fi
            node_name="${BASH_REMATCH[1]}"
            package=""
            in_node=true
        elif [[ "$line" =~ ^[[:space:]]*package:[[:space:]]*\"(.+)\" ]] && [ "${in_node}" = true ]; then
            package="${BASH_REMATCH[1]}"
        fi
    done < "${CONFIG_FILE}"
    # Flush last pair
    if [ -n "${node_name}" ] && [ -n "${package}" ]; then
        echo "${node_name}|${package}"
    fi
}

NODE_LIST=$(parse_nodes)
TOTAL=$(echo "${NODE_LIST}" | wc -l)

echo "Target nodes found in config: ${TOTAL}"
if [ "${TARGET_NODE}" != "all" ]; then
    echo "Filtering to node: ${TARGET_NODE}"
fi

# ─── Build loop ───────────────────────────────────────────────────────────────
BUILT=0
FAILED=()

while IFS='|' read -r node_name package; do
    if [ "${TARGET_NODE}" != "all" ] && [ "${node_name}" != "${TARGET_NODE}" ]; then
        continue
    fi
    if build_node "${node_name}" "${package}"; then
        BUILT=$((BUILT + 1))
    else
        FAILED+=("${node_name}")
    fi
done <<< "${NODE_LIST}"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  Build complete"
echo "  Built:  ${BUILT}"
echo "  Failed: ${#FAILED[@]}"
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "  Failed nodes:"
    for f in "${FAILED[@]}"; do echo "    - ${f}"; done
fi
echo "============================================================"
echo ""
echo "Instrumented binaries: ${OUTPUT_DIR}/"
echo ""
echo "Next steps:"
echo "  ./run_miniperf_roofline.sh      (full roofline scenario)"
echo "  ./run_miniperf_stat.sh          (quick stats snapshot)"
