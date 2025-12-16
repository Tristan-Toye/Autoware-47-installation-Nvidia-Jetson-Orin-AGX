# CARET Build Fix Guide

## Problem Summary

You're getting linker errors like:
```
undefined reference to `ros_trace_message_construct'
undefined reference to `ros_trace_rclcpp_intra_publish'
```

This happens because:
1. ✅ CARET's rclcpp IS being used (good - the undefined symbols prove it)
2. ❌ The linker can't find `libtracetools.so` which provides these symbols

## Root Causes

1. **LD_PRELOAD set before ROS sourcing** - Fixed by moving `LD_PRELOAD` after workspace sourcing in `.bashrc`
2. **LD_LIBRARY_PATH missing CARET's lib directory** - The linker needs this to find `libtracetools.so` during build
3. **CMAKE_PREFIX_PATH order** - Already fixed in `installation.sh`

## Solutions

### Solution 1: Fix LD_LIBRARY_PATH in installation.sh (Recommended)

Add this to `installation.sh` right after line 725 (after `export cumm_DIR=...`):

```bash
# Ensure CARET's lib directory is in LD_LIBRARY_PATH for linker to find tracetools
if [ -d "${SCRIPT_DIR}/ros2_caret_ws/install/lib" ]; then
	if ! echo "$LD_LIBRARY_PATH" | grep -q "${SCRIPT_DIR}/ros2_caret_ws/install/lib"; then
		export LD_LIBRARY_PATH="${SCRIPT_DIR}/ros2_caret_ws/install/lib:${LD_LIBRARY_PATH}"
	fi
fi
```

### Solution 2: Manual Build with Correct Environment

If you want to rebuild manually without modifying `installation.sh`:

```bash
cd /home/tristan-toye/Autoware-47-installation-Nvidia-Jetson-Orin-AGX/autoware

# Source in correct order
source /opt/ros/humble/setup.bash
source ../ros2_caret_ws/install/local_setup.bash
source ../ros2_humble/install/local_setup.bash

# CRITICAL: Add CARET's lib to LD_LIBRARY_PATH
export LD_LIBRARY_PATH="../ros2_caret_ws/install/lib:${LD_LIBRARY_PATH}"

# Verify environment
echo "CMAKE_PREFIX_PATH (first): $(echo "$CMAKE_PREFIX_PATH" | cut -d: -f1)"
echo "LD_LIBRARY_PATH includes CARET: $(echo "$LD_LIBRARY_PATH" | grep -q "ros2_caret_ws" && echo "yes" || echo "no")"

# Build
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
```

### Solution 3: Verify tracetools is Findable

Test if CMake can find tracetools:

```bash
source /opt/ros/humble/setup.bash
source /home/tristan-toye/Autoware-47-installation-Nvidia-Jetson-Orin-AGX/ros2_caret_ws/install/local_setup.bash

cat > /tmp/test_tracetools.cmake << 'EOF'
find_package(tracetools REQUIRED)
if(TARGET tracetools::tracetools)
    message(STATUS "SUCCESS: tracetools::tracetools target found")
else
    message(FATAL_ERROR "FAILED: tracetools::tracetools target NOT found")
endif
EOF

cmake -P /tmp/test_tracetools.cmake
```

If this fails, CMake can't find tracetools, which means `CMAKE_PREFIX_PATH` isn't set correctly.

## Verification Steps

After applying fixes, verify:

1. **Check environment before build:**
```bash
source /opt/ros/humble/setup.bash
source /home/tristan-toye/Autoware-47-installation-Nvidia-Jetson-Orin-AGX/ros2_caret_ws/install/local_setup.bash
echo "CMAKE_PREFIX_PATH first: $(echo "$CMAKE_PREFIX_PATH" | cut -d: -f1)"
echo "LD_LIBRARY_PATH has CARET: $(echo "$LD_LIBRARY_PATH" | grep -q "ros2_caret_ws" && echo "yes" || echo "no")"
```

2. **Test build one package:**
```bash
cd /home/tristan-toye/Autoware-47-installation-Nvidia-Jetson-Orin-AGX/autoware
colcon build --packages-select autoware_dummy_perception_publisher \
  --cmake-clean-cache \
  --symlink-install \
  --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
```

3. **Check if tracetools was linked:**
```bash
ldd install/lib/autoware_dummy_perception_publisher/autoware_dummy_perception_publisher_node | grep tracetools
```

If you see `libtracetools.so` in the output, it's linked correctly!

## Quick Fix Script

Run this to set up the environment correctly:

```bash
#!/bin/bash
cd /home/tristan-toye/Autoware-47-installation-Nvidia-Jetson-Orin-AGX/autoware

# Source in correct order
source /opt/ros/humble/setup.bash
source ../ros2_caret_ws/install/local_setup.bash
source ../ros2_humble/install/local_setup.bash

# Add CARET lib to LD_LIBRARY_PATH
export LD_LIBRARY_PATH="../ros2_caret_ws/install/lib:${LD_LIBRARY_PATH}"

# Verify
echo "Environment check:"
echo "  CMAKE_PREFIX_PATH starts with: $(echo "$CMAKE_PREFIX_PATH" | cut -d: -f1)"
echo "  LD_LIBRARY_PATH includes CARET: $(echo "$LD_LIBRARY_PATH" | grep -q "ros2_caret_ws" && echo "yes" || echo "no")"

# Build
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
```
