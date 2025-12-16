#!/bin/bash
set +e

# Script to fix CARET build environment issues
export SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

echo "=========================================="
echo "CARET Build Environment Fix"
echo "=========================================="
echo ""

# 1. Check current environment
echo "1. Checking current environment:"
echo "   CMAKE_PREFIX_PATH (first 3):"
echo "$CMAKE_PREFIX_PATH" | tr ':' '\n' | head -3
echo ""
echo "   LD_LIBRARY_PATH (first 3):"
echo "$LD_LIBRARY_PATH" | tr ':' '\n' | head -3
echo ""

# 2. Source ROS and CARET in correct order
echo "2. Sourcing ROS and CARET workspaces..."
source /opt/ros/humble/setup.bash 2>/dev/null
source "${SCRIPT_DIR}/ros2_caret_ws/install/local_setup.bash" 2>/dev/null
source "${SCRIPT_DIR}/ros2_humble/install/local_setup.bash" 2>/dev/null

# 3. Verify tracetools is findable
echo "3. Verifying tracetools is findable:"
if [ -f "${SCRIPT_DIR}/ros2_caret_ws/install/share/tracetools/cmake/tracetoolsConfig.cmake" ]; then
    echo "   ✓ tracetoolsConfig.cmake found"
else
    echo "   ❌ tracetoolsConfig.cmake NOT found!"
    exit 1
fi

# 4. Check if tracetools library exists
if [ -f "${SCRIPT_DIR}/ros2_caret_ws/install/lib/libtracetools.so" ]; then
    echo "   ✓ libtracetools.so found"
else
    echo "   ❌ libtracetools.so NOT found!"
    exit 1
fi
echo ""

# 5. Ensure CARET's lib directory is in LD_LIBRARY_PATH for build
echo "4. Setting up library paths for build:"
CARET_LIB="${SCRIPT_DIR}/ros2_caret_ws/install/lib"
if echo "$LD_LIBRARY_PATH" | grep -q "$CARET_LIB"; then
    echo "   ✓ CARET lib directory already in LD_LIBRARY_PATH"
else
    export LD_LIBRARY_PATH="${CARET_LIB}:${LD_LIBRARY_PATH}"
    echo "   ✓ Added CARET lib directory to LD_LIBRARY_PATH"
fi
echo ""

# 6. Verify CMAKE_PREFIX_PATH includes CARET first
echo "5. Verifying CMAKE_PREFIX_PATH order:"
FIRST_PATH=$(echo "$CMAKE_PREFIX_PATH" | cut -d: -f1)
if echo "$FIRST_PATH" | grep -q "ros2_caret_ws/install"; then
    echo "   ✓ CARET workspace is first in CMAKE_PREFIX_PATH"
    echo "   First path: $FIRST_PATH"
else
    echo "   ⚠ CARET workspace is NOT first in CMAKE_PREFIX_PATH"
    echo "   First path: $FIRST_PATH"
    echo "   Fixing..."
    CARET_PATH=$(echo "$CMAKE_PREFIX_PATH" | tr ':' '\n' | grep "ros2_caret_ws/install" | head -n1)
    if [ -n "$CARET_PATH" ]; then
        CMAKE_PREFIX_PATH=$(echo "$CMAKE_PREFIX_PATH" | tr ':' '\n' | grep -v "ros2_caret_ws/install" | tr '\n' ':' | sed 's/:$//')
        export CMAKE_PREFIX_PATH="${CARET_PATH}:${CMAKE_PREFIX_PATH}"
        echo "   ✓ Fixed CMAKE_PREFIX_PATH"
    fi
fi
echo ""

# 7. Test if CMake can find tracetools
echo "6. Testing CMake can find tracetools:"
cat > /tmp/test_tracetools.cmake << 'EOF'
find_package(tracetools REQUIRED)
message(STATUS "tracetools_FOUND: ${tracetools_FOUND}")
if(TARGET tracetools::tracetools)
    message(STATUS "tracetools::tracetools target found")
    get_target_property(TRACETOOLS_LIB tracetools::tracetools LOCATION)
    message(STATUS "tracetools library: ${TRACETOOLS_LIB}")
else
    message(FATAL_ERROR "tracetools::tracetools target NOT found")
endif
EOF

if cmake -P /tmp/test_tracetools.cmake 2>&1 | grep -q "tracetools::tracetools target found"; then
    echo "   ✓ CMake can find tracetools"
else
    echo "   ❌ CMake CANNOT find tracetools"
    echo "   This is the root cause of the linking errors!"
    echo ""
    echo "   Run this to see the error:"
    echo "   cmake -P /tmp/test_tracetools.cmake"
fi
rm -f /tmp/test_tracetools.cmake
echo ""

# 8. Summary and recommendations
echo "=========================================="
echo "Summary and Next Steps"
echo "=========================================="
echo ""
echo "Current environment variables:"
echo "  CMAKE_PREFIX_PATH (first): $(echo "$CMAKE_PREFIX_PATH" | cut -d: -f1)"
echo "  LD_LIBRARY_PATH includes CARET: $(echo "$LD_LIBRARY_PATH" | grep -q "ros2_caret_ws" && echo "yes" || echo "no")"
echo ""
echo "To rebuild Autoware with CARET:"
echo "  1. Source this script: source ${SCRIPT_DIR}/fix_caret_build_environment.sh"
echo "  2. Then run: cd ${SCRIPT_DIR}/autoware"
echo "  3. Then run: colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF"
echo ""
