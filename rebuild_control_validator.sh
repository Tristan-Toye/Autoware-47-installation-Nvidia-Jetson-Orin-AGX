#!/bin/bash
set -e

# Set SCRIPT_DIR properly
export SCRIPT_DIR="/home/tristan-toye/Autoware-47-installation-Nvidia-Jetson-Orin-AGX"

echo "=========================================="
echo "Rebuilding angles and autoware_control_validator"
echo "=========================================="

# Navigate to script directory
cd "${SCRIPT_DIR}"

# Remove CARET workspace from environment to avoid conflicts
echo "Clearing CARET workspace from environment..."
unset LD_PRELOAD
export CMAKE_PREFIX_PATH=$(echo "$CMAKE_PREFIX_PATH" | tr ':' '\n' | grep -v "ros2_caret_ws" | tr '\n' ':' | sed 's/:$//')
export AMENT_PREFIX_PATH=$(echo "$AMENT_PREFIX_PATH" | tr ':' '\n' | grep -v "ros2_caret_ws" | tr '\n' ':' | sed 's/:$//')
export ROS_PACKAGE_PATH=$(echo "$ROS_PACKAGE_PATH" | tr ':' '\n' | grep -v "ros2_caret_ws" | tr '\n' ':' | sed 's/:$//')

# Source workspaces in correct order (most specific first)
echo "Sourcing workspaces..."
source "${SCRIPT_DIR}/ros2_humble/install/local_setup.bash"
source /opt/ros/humble/setup.bash

# Set environment variables
export CUDAToolkit_ROOT=/usr/local/cuda
export CMAKE_PREFIX_PATH="${SCRIPT_DIR}/ros2_humble/install:$HOME/.local${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export spconv_DIR="$HOME/.local/lib/cmake/spconv"
export cumm_DIR="$HOME/.local/share/cmake/cumm"

echo "Environment setup complete."
echo "CMAKE_PREFIX_PATH=$CMAKE_PREFIX_PATH"
echo ""

# Step 1: Verify angles CMakeLists.txt fix is applied
echo "=========================================="
echo "Step 1: Verifying angles CMakeLists.txt fix"
echo "=========================================="
ANGLES_CMAKE="${SCRIPT_DIR}/ros2_humble/src/angles/angles/CMakeLists.txt"
if [ -f "${ANGLES_CMAKE}" ]; then
    if grep -q 'INSTALL_INTERFACE:include/angles>' "${ANGLES_CMAKE}"; then
        echo "Applying angles CMakeLists.txt fix..."
        sed -i 's|"$<INSTALL_INTERFACE:include/angles>"|"$<INSTALL_INTERFACE:include>"|g' "${ANGLES_CMAKE}"
        echo "✓ Fixed angles CMakeLists.txt"
    else
        echo "✓ angles CMakeLists.txt already fixed"
    fi
else
    echo "⚠ Warning: angles CMakeLists.txt not found at ${ANGLES_CMAKE}"
fi

# Step 2: Rebuild angles with the fix
echo ""
echo "=========================================="
echo "Step 2: Rebuilding angles package"
echo "=========================================="
cd "${SCRIPT_DIR}/ros2_humble"

# Ensure environment is set
source /opt/ros/humble/setup.bash

# Check install layout - try merge-install first, fallback to isolated
if colcon build --packages-select angles --merge-install --cmake-args -DCMAKE_BUILD_TYPE=Release 2>&1 | grep -q "merge-install"; then
    echo "Falling back to isolated layout..."
    colcon build --packages-select angles --cmake-args -DCMAKE_BUILD_TYPE=Release
else
    echo "✓ Built with merged layout"
fi
echo "✓ Rebuilt angles package"

# Step 3: Rebuild autoware_control_validator
echo ""
echo "=========================================="
echo "Step 3: Rebuilding autoware_control_validator"
echo "=========================================="
cd "${SCRIPT_DIR}/autoware"

# Ensure environment is still correct and ros2_caret_ws is NOT in workspace
# Check if ros2_caret_ws/src exists and exclude it
CARET_DISABLED=false
if [ -d "${SCRIPT_DIR}/ros2_caret_ws/src" ]; then
    echo "Temporarily excluding ros2_caret_ws from workspace..."
    # Temporarily rename or exclude ros2_caret_ws
    mv "${SCRIPT_DIR}/ros2_caret_ws/src" "${SCRIPT_DIR}/ros2_caret_ws/src.disabled" 2>/dev/null || true
    CARET_DISABLED=true
fi

# Source workspaces again
source "${SCRIPT_DIR}/ros2_humble/install/local_setup.bash"
source /opt/ros/humble/setup.bash
export CMAKE_PREFIX_PATH="${SCRIPT_DIR}/ros2_humble/install:$HOME/.local${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export CUDAToolkit_ROOT=/usr/local/cuda
export spconv_DIR="$HOME/.local/lib/cmake/spconv"
export cumm_DIR="$HOME/.local/share/cmake/cumm"

# Remove ros2_caret_ws from any workspace paths
unset LD_PRELOAD
export CMAKE_PREFIX_PATH=$(echo "$CMAKE_PREFIX_PATH" | tr ':' '\n' | grep -v "ros2_caret_ws" | tr '\n' ':' | sed 's/:$//')
export AMENT_PREFIX_PATH=$(echo "$AMENT_PREFIX_PATH" | tr ':' '\n' | grep -v "ros2_caret_ws" | tr '\n' ':' | sed 's/:$//')
export ROS_PACKAGE_PATH=$(echo "$ROS_PACKAGE_PATH" | tr ':' '\n' | grep -v "ros2_caret_ws" | tr '\n' ':' | sed 's/:$//')

echo "Building autoware_control_validator..."
colcon build --packages-up-to autoware_control_validator --symlink-install --cmake-clean-cache --cmake-args -DCMAKE_BUILD_TYPE=Release

# Restore ros2_caret_ws if we disabled it
if [ "$CARET_DISABLED" = true ]; then
    echo "Restoring ros2_caret_ws..."
    mv "${SCRIPT_DIR}/ros2_caret_ws/src.disabled" "${SCRIPT_DIR}/ros2_caret_ws/src" 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo "✓ Build complete!"
echo "=========================================="

