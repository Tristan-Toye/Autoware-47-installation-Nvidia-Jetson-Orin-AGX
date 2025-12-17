#!/usr/bin/env bash
# NOTE: do NOT use `set -u` here, it breaks /opt/ros/... setup scripts
set -eo pipefail

ROOT="$HOME/Autoware-47-installation-Nvidia-Jetson-Orin-AGX"

echo "=== Setting up CARET build+run environment ==="
# Temporarily allow unset vars while sourcing ROS setup files
set +u 2>/dev/null || true
source /opt/ros/humble/setup.bash
source "$ROOT/ros2_humble/install/local_setup.bash"
source "$ROOT/ros2_caret_ws/install/local_setup.bash"

set -e 2>/dev/null || true

cd "$ROOT/autoware"


rm -rf build install log
rm -f "${SCRIPT_DIR}/.autoware_build_flag"
echo "✓ Cleaned build directories"
{
	echo "=== Build Environment ==="
	echo "CMAKE_PREFIX_PATH=$CMAKE_PREFIX_PATH"
	echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
	echo "spconv_DIR=$spconv_DIR"
	echo "cumm_DIR=$cumm_DIR"
	echo "========================="
} | sudo tee "${ROOT}/test_autoware_dummy_perception_publisher_env.txt"

echo
echo "=== Rebuilding autoware_dummy_perception_publisher only ==="
colcon build --packages-up-to autoware_dummy_perception_publisher \
  --cmake-clean-cache \
  --symlink-install \
  --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF

echo
echo "=== Checking that the node links libtracetools & librclcpp ==="
ldd install/lib/autoware_dummy_perception_publisher/autoware_dummy_perception_publisher_node \
  | grep -E 'tracetools|rclcpp' || echo "WARNING: tracetools or rclcpp not shown in ldd output"

echo
echo "=== Checking CARET instrumentation for this package ==="
ros2 caret check_caret_rclcpp .

echo
echo "Done. If there are no undefined reference errors and the package is not listed as 'not built with caret-rclcpp', the installation is OK."
