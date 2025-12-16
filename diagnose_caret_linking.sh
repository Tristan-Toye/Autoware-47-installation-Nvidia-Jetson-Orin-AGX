#!/bin/bash
# Diagnostic script to check CARET linking issues

export SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

echo "=========================================="
echo "CARET Linking Diagnostics"
echo "=========================================="
echo ""

# 1. Check if CARET's rclcpp has undefined trace symbols
echo "1. Checking CARET's librclcpp.so for undefined trace symbols:"
nm -D "${SCRIPT_DIR}/ros2_caret_ws/install/lib/librclcpp.so" 2>/dev/null | grep -E "U ros_trace" | head -5
echo ""

# 2. Check if tracetools defines these symbols
echo "2. Checking if libtracetools.so defines these symbols:"
nm -D "${SCRIPT_DIR}/ros2_caret_ws/install/lib/libtracetools.so" 2>/dev/null | grep -E "T ros_trace_message_construct|T ros_trace_rclcpp_intra_publish" | head -5
echo ""

# 3. Check a failing package's link command
FAILING_PKG="autoware_dummy_perception_publisher"
LINK_FILE="${SCRIPT_DIR}/autoware/build/${FAILING_PKG}/CMakeFiles/autoware_dummy_perception_publisher_node.dir/link.txt"

if [ -f "$LINK_FILE" ]; then
    echo "3. Checking link command for ${FAILING_PKG}:"
    echo "   Looking for tracetools library:"
    grep -oE "-ltracetools|-L[^ ]*tracetools" "$LINK_FILE" || echo "   ❌ tracetools NOT found in link command"
    echo ""
    echo "   Library search paths:"
    grep -oE "-L[^ ]*" "$LINK_FILE" | head -10
    echo ""
    echo "   Linked libraries:"
    grep -oE "-l[^ ]*" "$LINK_FILE" | grep -E "rclcpp|tracetools" | head -5
else
    echo "3. Link file not found: $LINK_FILE"
    echo "   Package may not have been built yet"
fi
echo ""

# 4. Check package.xml for tracetools dependency
PKG_XML="${SCRIPT_DIR}/autoware/src/universe/autoware_universe/simulator/autoware_dummy_perception_publisher/package.xml"
if [ -f "$PKG_XML" ]; then
    echo "4. Checking package.xml for tracetools dependency:"
    if grep -q "tracetools" "$PKG_XML"; then
        echo "   ✓ tracetools dependency found"
        grep "tracetools" "$PKG_XML"
    else
        echo "   ❌ tracetools dependency NOT found"
    fi
else
    echo "4. package.xml not found: $PKG_XML"
fi
echo ""

# 5. Check CMAKE_PREFIX_PATH order
echo "5. CMAKE_PREFIX_PATH order (first 5 entries):"
echo "$CMAKE_PREFIX_PATH" | tr ':' '\n' | head -5
echo ""

# 6. Check if tracetools is findable by CMake
echo "6. Checking if CMake can find tracetools:"
if [ -f "${SCRIPT_DIR}/ros2_caret_ws/install/share/tracetools/cmake/tracetoolsConfig.cmake" ]; then
    echo "   ✓ tracetoolsConfig.cmake found"
else
    echo "   ❌ tracetoolsConfig.cmake NOT found"
    echo "   Looking for tracetools cmake files:"
    find "${SCRIPT_DIR}/ros2_caret_ws/install" -name "*tracetools*Config.cmake" 2>/dev/null | head -3
fi
