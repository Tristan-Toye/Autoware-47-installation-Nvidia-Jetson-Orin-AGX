# CARET Linking Fix for autoware_accel_brake_map_calibrator and autoware_dummy_perception_publisher

## Problem

The build was failing for these two packages with linker errors:
```
undefined reference to `ros_trace_message_construct'
undefined reference to `ros_trace_rclcpp_intra_publish'
```

## Root Cause

1. **CARET's rclcpp is being used** (good - the undefined symbols prove it)
2. **The linker can't find CARET's `libtracetools.so`** which provides these symbols
3. **CMake's `find_package(tracetools)` was finding the system version** from `/opt/ros/humble` instead of CARET's instrumented version

The issue was that after sourcing ROS and CARET workspaces, `CMAKE_PREFIX_PATH` had `/opt/ros/humble` before CARET's install directory, causing CMake to find the system tracetools first (which lacks CARET-specific symbols).

## Solution

The fix includes three key changes:

### 1. Reorder CMAKE_PREFIX_PATH
After sourcing the workspaces, explicitly reorder `CMAKE_PREFIX_PATH` to put CARET's install directory FIRST:

```bash
CARET_INSTALL="${SCRIPT_DIR}/ros2_caret_ws/install"
if [ -d "${CARET_INSTALL}" ]; then
	CARET_PATH=$(echo "$CMAKE_PREFIX_PATH" | tr ':' '\n' | grep -F "${CARET_INSTALL}" | head -n1)
	if [ -n "${CARET_PATH}" ]; then
		CMAKE_PREFIX_PATH=$(echo "$CMAKE_PREFIX_PATH" | tr ':' '\n' | grep -vF "${CARET_INSTALL}" | paste -sd: -)
		export CMAKE_PREFIX_PATH="${CARET_PATH}:${CMAKE_PREFIX_PATH}"
	else
		export CMAKE_PREFIX_PATH="${CARET_INSTALL}:${CMAKE_PREFIX_PATH}"
	fi
fi
```

### 2. Set tracetools_DIR Environment Variable
Explicitly set `tracetools_DIR` to force CMake to use CARET's tracetools:

```bash
if [ -f "${SCRIPT_DIR}/ros2_caret_ws/install/share/tracetools/cmake/tracetoolsConfig.cmake" ]; then
	export tracetools_DIR="${SCRIPT_DIR}/ros2_caret_ws/install/share/tracetools/cmake"
fi
```

### 3. Pass tracetools_DIR to colcon build
Add `-Dtracetools_DIR` to CMake args when building:

```bash
CARET_TRACETOOLS_DIR="${SCRIPT_DIR}/ros2_caret_ws/install/share/tracetools/cmake"
CMAKE_ARGS="-DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF"
if [ -f "${CARET_TRACETOOLS_DIR}/tracetoolsConfig.cmake" ]; then
	CMAKE_ARGS="${CMAKE_ARGS} -Dtracetools_DIR=${CARET_TRACETOOLS_DIR}"
fi

colcon build --symlink-install --cmake-clean-cache \
  --cmake-args ${CMAKE_ARGS} \
  --continue-on-error
```

## Verification

After the fix, verify that:
1. The build completes without undefined reference errors
2. The built binaries link against CARET's tracetools:
   ```bash
   ldd autoware/install/lib/autoware_dummy_perception_publisher/autoware_dummy_perception_publisher_node | grep tracetools
   ```
   Should show: `libtracetools.so => .../ros2_caret_ws/install/lib/libtracetools.so`

## Node Purposes

### autoware_accel_brake_map_calibrator

**Purpose**: Automatically calibrates the acceleration and brake control maps used by the vehicle control system.

**Function**:
- Calibrates `accel_map.csv` and `brake_map.csv` files used in `raw_vehicle_cmd_converter`
- Updates the base control maps iteratively with real driving data
- Ensures accurate translation of acceleration/braking commands into physical vehicle actions

**Why it's needed**: Without proper calibration, the vehicle may not respond correctly to control commands, leading to unsafe or inaccurate behavior.

### autoware_dummy_perception_publisher

**Purpose**: Publishes simulated/dummy perception data (objects, obstacles) for testing and development.

**Function**:
- Simulates perception data by publishing dummy objects
- Useful for testing planning and control modules without real sensor data
- Allows developers to validate the system when sensors aren't available

**Why it's needed**: Essential for:
- Development and testing without physical sensors
- Simulation and validation of the perception pipeline
- Debugging planning and control algorithms
- CI/CD testing environments

Both nodes are important for the Autoware system:
- **autoware_accel_brake_map_calibrator**: Ensures safe and accurate vehicle control
- **autoware_dummy_perception_publisher**: Enables development and testing without physical hardware

