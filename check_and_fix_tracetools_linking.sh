#!/bin/bash
set +e

# Script to check and document the tracetools linking issue
export SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

echo "=========================================="
echo "CARET Tracetools Linking Analysis"
echo "=========================================="
echo ""

# Source environment properly
source /opt/ros/humble/setup.bash 2>/dev/null
source "${SCRIPT_DIR}/ros2_caret_ws/install/local_setup.bash" 2>/dev/null

# 1. Check if CARET's rclcpp has undefined trace symbols
echo "1. CARET's librclcpp.so undefined trace symbols:"
UNDEFINED=$(nm -D "${SCRIPT_DIR}/ros2_caret_ws/install/lib/librclcpp.so" 2>/dev/null | grep -c "U ros_trace")
echo "   Found $UNDEFINED undefined trace symbols"
if [ "$UNDEFINED" -gt 0 ]; then
    echo "   ✓ CARET's rclcpp calls trace functions (expected)"
    nm -D "${SCRIPT_DIR}/ros2_caret_ws/install/lib/librclcpp.so" 2>/dev/null | grep "U ros_trace" | head -3
fi
echo ""

# 2. Check if tracetools defines these symbols
echo "2. Checking libtracetools.so:"
if [ -f "${SCRIPT_DIR}/ros2_caret_ws/install/lib/libtracetools.so" ]; then
    DEFINED=$(nm -D "${SCRIPT_DIR}/ros2_caret_ws/install/lib/libtracetools.so" 2>/dev/null | grep -c "T ros_trace_message_construct")
    echo "   Found $DEFINED defined trace symbols"
    if [ "$DEFINED" -gt 0 ]; then
        echo "   ✓ libtracetools.so provides trace functions"
        nm -D "${SCRIPT_DIR}/ros2_caret_ws/install/lib/libtracetools.so" 2>/dev/null | grep "T ros_trace" | head -3
    fi
else
    echo "   ❌ libtracetools.so NOT found!"
fi
echo ""

# 3. Check if rclcpp CMake config requires tracetools
echo "3. Checking rclcpp CMake configuration:"
RCLCPP_CMAKE="${SCRIPT_DIR}/ros2_caret_ws/install/share/rclcpp/cmake/rclcppConfig.cmake"
if [ -f "$RCLCPP_CMAKE" ]; then
    if grep -q "tracetools" "$RCLCPP_CMAKE"; then
        echo "   ✓ rclcppConfig.cmake references tracetools"
        grep "tracetools" "$RCLCPP_CMAKE" | head -2
    else
        echo "   ⚠ rclcppConfig.cmake does NOT reference tracetools"
        echo "   This might be why packages aren't linking tracetools automatically"
    fi
else
    echo "   ❌ rclcppConfig.cmake NOT found"
fi
echo ""

# 4. Check a sample package's CMakeLists.txt
SAMPLE_PKG="${SCRIPT_DIR}/autoware/src/universe/autoware_universe/simulator/autoware_dummy_perception_publisher"
if [ -f "${SAMPLE_PKG}/CMakeLists.txt" ]; then
    echo "4. Checking sample package CMakeLists.txt:"
    if grep -q "tracetools" "${SAMPLE_PKG}/CMakeLists.txt"; then
        echo "   ✓ Package explicitly links tracetools"
    else
        echo "   ⚠ Package does NOT explicitly link tracetools"
        echo "   Checking how it links rclcpp:"
        grep -A5 "rclcpp" "${SAMPLE_PKG}/CMakeLists.txt" | head -10
    fi
else
    echo "4. CMakeLists.txt not found for sample package"
fi
echo ""

# 5. Solution: Check if we need to add tracetools to LD_LIBRARY_PATH or link it explicitly
echo "5. Recommended Solutions:"
echo ""
echo "   Option A: Ensure tracetools library path is in LD_LIBRARY_PATH during build"
echo "   Current LD_LIBRARY_PATH:"
echo "$LD_LIBRARY_PATH" | tr ':' '\n' | grep -E "caret|tracetools" || echo "   (no caret/tracetools paths found)"
echo ""
echo "   Option B: Packages using CARET's rclcpp should link tracetools explicitly"
echo "   This can be done by:"
echo "   1. Adding <depend>tracetools</depend> to package.xml"
echo "   2. OR ensuring rclcpp's CMake config automatically pulls in tracetools"
echo ""
