# Complete CARET Build Fix Summary

## Problems Identified

1. ✅ **Fixed**: `LD_PRELOAD` was set before ROS workspaces were sourced → moved to after sourcing
2. ✅ **Fixed**: `CMAKE_PREFIX_PATH` wasn't preserving CARET's path → fixed in installation.sh
3. ⚠️ **Needs Fix**: `LD_LIBRARY_PATH` missing CARET's lib directory during build

## The Linker Error Explained

The error `undefined reference to 'ros_trace_message_construct'` means:
- ✅ CARET's rclcpp IS being used (good!)
- ❌ The linker can't find `libtracetools.so` which provides these symbols

## Solution: Add LD_LIBRARY_PATH to installation.sh

**Manual Edit Required:** Open `installation.sh` and add these lines **after line 725** (after `export cumm_DIR=...`):

```bash
# Ensure CARET's lib directory is in LD_LIBRARY_PATH for linker to find tracetools
if [ -d "${SCRIPT_DIR}/ros2_caret_ws/install/lib" ]; then
	if ! echo "$LD_LIBRARY_PATH" | grep -q "${SCRIPT_DIR}/ros2_caret_ws/install/lib"; then
		export LD_LIBRARY_PATH="${SCRIPT_DIR}/ros2_caret_ws/install/lib:${LD_LIBRARY_PATH}"
	fi
fi
```

**Location in file:** Right after line 725 (`export cumm_DIR=...`) and before `# optional: prove it`

## Quick Test (Without Modifying installation.sh)

To test if this fixes the issue:

```bash
cd /home/tristan-toye/Autoware-47-installation-Nvidia-Jetson-Orin-AGX/autoware

# Source in correct order
source /opt/ros/humble/setup.bash
source ../ros2_caret_ws/install/local_setup.bash
source ../ros2_humble/install/local_setup.bash

# CRITICAL: Add CARET's lib to LD_LIBRARY_PATH
export LD_LIBRARY_PATH="../ros2_caret_ws/install/lib:${LD_LIBRARY_PATH}"

# Verify environment
echo "CMAKE_PREFIX_PATH first: $(echo "$CMAKE_PREFIX_PATH" | cut -d: -f1)"
echo "LD_LIBRARY_PATH has CARET: $(echo "$LD_LIBRARY_PATH" | grep -q "ros2_caret_ws" && echo "yes" || echo "no")"

# Test build one package
colcon build --packages-select autoware_dummy_perception_publisher \
  --cmake-clean-cache \
  --symlink-install \
  --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
```

If this works, then add the `LD_LIBRARY_PATH` fix to `installation.sh` permanently.

## Verification Commands

### 1. Check if tracetools symbols exist:
```bash
nm -D /home/tristan-toye/Autoware-47-installation-Nvidia-Jetson-Orin-AGX/ros2_caret_ws/install/lib/libtracetools.so | grep "T ros_trace_message_construct"
```
Expected: `0000000000009a00 T ros_trace_message_construct`

### 2. Check if CMake can find tracetools:
```bash
source /opt/ros/humble/setup.bash
source /home/tristan-toye/Autoware-47-installation-Nvidia-Jetson-Orin-AGX/ros2_caret_ws/install/local_setup.bash
cmake -P - << 'EOF'
find_package(tracetools REQUIRED)
if(TARGET tracetools::tracetools)
    message(STATUS "SUCCESS: tracetools found")
else
    message(FATAL_ERROR "FAILED: tracetools NOT found")
endif
EOF
```

### 3. After successful build, verify linking:
```bash
ldd /home/tristan-toye/Autoware-47-installation-Nvidia-Jetson-Orin-AGX/autoware/install/lib/autoware_dummy_perception_publisher/autoware_dummy_perception_publisher_node | grep tracetools
```
Expected: Should show `libtracetools.so => ...`

## Summary

**The fix is simple:** Add CARET's lib directory (`ros2_caret_ws/install/lib`) to `LD_LIBRARY_PATH` during the build so the linker can find `libtracetools.so`.

This needs to be done in `installation.sh` OR manually before running `colcon build`.
