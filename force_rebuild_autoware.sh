#!/bin/bash
set -e
set -x

# Script to force a complete rebuild of Autoware with CARET
export SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

echo "=========================================="
echo "Force Rebuilding Autoware with CARET"
echo "=========================================="

cd "${SCRIPT_DIR}/autoware"

# Remove build flag to force rebuild
rm -f "${SCRIPT_DIR}/.autoware_build_flag"

# Option 1: Clean build directories (removes all build artifacts)
if [ "$1" = "--clean" ]; then
    echo "Cleaning build and install directories..."
    rm -rf build install log
    echo "✓ Cleaned build directories"
fi

# Source environment in correct order
echo "Sourcing environment..."
source /opt/ros/humble/setup.bash
if [ -f "${SCRIPT_DIR}/ros2_humble/install/local_setup.bash" ]; then
    source "${SCRIPT_DIR}/ros2_humble/install/local_setup.bash"
fi
if [ -f "${SCRIPT_DIR}/ros2_caret_ws/install/local_setup.bash" ]; then
    source "${SCRIPT_DIR}/ros2_caret_ws/install/local_setup.bash"
fi


# Set environment variables
export CUDAToolkit_ROOT=/usr/local/cuda
export CMAKE_PREFIX_PATH="${SCRIPT_DIR}/ros2_humble/install:$HOME/.local${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export spconv_DIR="$HOME/.local/lib/cmake/spconv"
export cumm_DIR="$HOME/.local/share/cmake/cumm"
export CC="/usr/lib/ccache/gcc"
export CXX="/usr/lib/ccache/g++"
export CCACHE_DIR="$HOME/.ccache"

echo "Environment setup complete."
echo "CMAKE_PREFIX_PATH=$CMAKE_PREFIX_PATH"
echo ""

# Verify CARET is in the environment
if [ -z "$AMENT_PREFIX_PATH" ] || ! echo "$AMENT_PREFIX_PATH" | grep -q "ros2_caret_ws"; then
    echo "⚠ Warning: CARET workspace not detected in AMENT_PREFIX_PATH"
    echo "   This may mean packages won't be built with CARET instrumentation"
    exit 1
fi

# Build with CARET
echo "=========================================="
echo "Building Autoware with CARET..."
echo "=========================================="
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF

# Mark as built
touch "${SCRIPT_DIR}/.autoware_build_flag"

echo ""
echo "=========================================="
echo "✓ Build complete!"
echo "=========================================="
echo ""
echo "Verifying CARET instrumentation..."
ros2 caret check_caret_rclcpp ./
