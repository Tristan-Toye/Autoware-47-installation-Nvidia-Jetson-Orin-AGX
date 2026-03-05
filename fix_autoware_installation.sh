#!/bin/bash
set -e

# Script to fix Autoware installation issues:
# 1. Add diagnostic_updater dependency to autoware_lidar_centerpoint package.xml if missing
# 2. Add rclcpp include to monitor headers if missing
# 3. Add angles dependency to autoware_control_validator package.xml if missing

export SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# ==================== Fix 1: autoware_lidar_centerpoint package.xml ====================
PACKAGE_XML="${SCRIPT_DIR}/autoware/src/universe/autoware_universe/perception/autoware_lidar_centerpoint/package.xml"

if [ ! -f "${PACKAGE_XML}" ]; then
    echo "Warning: package.xml not found at ${PACKAGE_XML}"
    echo "Skipping diagnostic_updater dependency fix."
else
    # Check if diagnostic_updater dependency is already present
    if grep -q "<depend>diagnostic_updater</depend>" "${PACKAGE_XML}"; then
        echo "✓ diagnostic_updater dependency already present in package.xml"
    else
        # Find the line number after cuda_blackboard dependency
        CUDA_BLACKBOARD_LINE=$(grep -n "<depend>cuda_blackboard</depend>" "${PACKAGE_XML}" | cut -d: -f1)
        
        if [ -z "${CUDA_BLACKBOARD_LINE}" ]; then
            echo "Warning: Could not find cuda_blackboard dependency in package.xml"
            echo "Skipping diagnostic_updater dependency fix."
        else
            # Insert the diagnostic_updater dependency after cuda_blackboard
            sed -i "${CUDA_BLACKBOARD_LINE}a\  <depend>diagnostic_updater</depend>" "${PACKAGE_XML}"
            echo "✓ Added diagnostic_updater dependency to package.xml"
        fi
    fi
fi

# ==================== Fix 2: Add rclcpp includes to monitor headers ====================
# List of monitor headers that need the rclcpp include
MONITOR_HEADERS=(
    "hdd_monitor/hdd_monitor.hpp"
    "mem_monitor/mem_monitor.hpp"
    "net_monitor/net_monitor.hpp"
    "voltage_monitor/voltage_monitor.hpp"
    "gpu_monitor/gpu_monitor_base.hpp"
    "ntp_monitor/ntp_monitor.hpp"
)

BASE_PATH="${SCRIPT_DIR}/autoware/src/universe/autoware_universe/system/autoware_system_monitor/include/system_monitor"

for header_rel_path in "${MONITOR_HEADERS[@]}"; do
    HEADER_FILE="${BASE_PATH}/${header_rel_path}"
    
    if [ ! -f "${HEADER_FILE}" ]; then
        echo "Warning: ${header_rel_path} not found at ${HEADER_FILE}"
        echo "Skipping rclcpp include fix for this file."
        continue
    fi
    
    # Check if rclcpp include is already present
    if grep -q "#include <rclcpp/rclcpp.hpp>" "${HEADER_FILE}"; then
        echo "✓ rclcpp include already present in ${header_rel_path}"
    else
        # Find the line number after diagnostic_updater include
        DIAGNOSTIC_UPDATER_LINE=$(grep -n "#include <diagnostic_updater/diagnostic_updater.hpp>" "${HEADER_FILE}" | cut -d: -f1 | head -n1)
        
        if [ -z "${DIAGNOSTIC_UPDATER_LINE}" ]; then
            echo "Warning: Could not find diagnostic_updater include in ${header_rel_path}"
            echo "Skipping rclcpp include fix for this file."
        else
            # Insert the rclcpp include after diagnostic_updater
            sed -i "${DIAGNOSTIC_UPDATER_LINE}a#include <rclcpp/rclcpp.hpp>" "${HEADER_FILE}"
            echo "✓ Added rclcpp include to ${header_rel_path}"
        fi
    fi
done

# ==================== Fix 3: autoware_control_validator package.xml ====================
CONTROL_VALIDATOR_XML="${SCRIPT_DIR}/autoware/src/universe/autoware_universe/control/autoware_control_validator/package.xml"

if [ ! -f "${CONTROL_VALIDATOR_XML}" ]; then
    echo "Warning: package.xml not found at ${CONTROL_VALIDATOR_XML}"
    echo "Skipping angles dependency fix."
else
    # Check if angles dependency is already present
    if grep -q "<depend>angles</depend>" "${CONTROL_VALIDATOR_XML}"; then
        echo "✓ angles dependency already present in autoware_control_validator package.xml"
    else
        # Find the line number after autoware_vehicle_info_utils dependency
        VEHICLE_INFO_LINE=$(grep -n "<depend>autoware_vehicle_info_utils</depend>" "${CONTROL_VALIDATOR_XML}" | cut -d: -f1)
        
        if [ -z "${VEHICLE_INFO_LINE}" ]; then
            echo "Warning: Could not find autoware_vehicle_info_utils dependency in package.xml"
            echo "Skipping angles dependency fix."
        else
            # Insert the angles dependency after autoware_vehicle_info_utils
            sed -i "${VEHICLE_INFO_LINE}a\  <depend>angles</depend>" "${CONTROL_VALIDATOR_XML}"
            echo "✓ Added angles dependency to autoware_control_validator package.xml"
        fi
    fi
fi

# ==================== Fix 4: CHECK_CUDA_ERROR macro redefinition ====================
# autoware_lidar_centerpoint defines CHECK_CUDA_ERROR in its own cuda_utils.hpp, and
# autoware_cuda_utils defines it differently in cuda_check_error.hpp, causing -Werror failure.
# Adding #undef before each #define prevents the redefinition error.

CENTERPOINT_CUDA_UTILS="${SCRIPT_DIR}/autoware/src/universe/autoware_universe/perception/autoware_lidar_centerpoint/include/autoware/lidar_centerpoint/cuda_utils.hpp"
if [ -f "${CENTERPOINT_CUDA_UTILS}" ]; then
    if grep -q '^#undef CHECK_CUDA_ERROR' "${CENTERPOINT_CUDA_UTILS}"; then
        echo "✓ CHECK_CUDA_ERROR #undef already present in lidar_centerpoint cuda_utils.hpp"
    else
        sed -i 's/^#define CHECK_CUDA_ERROR(e)/#undef CHECK_CUDA_ERROR\n#define CHECK_CUDA_ERROR(e)/' "${CENTERPOINT_CUDA_UTILS}"
        echo "✓ Added #undef CHECK_CUDA_ERROR to lidar_centerpoint cuda_utils.hpp"
    fi
else
    echo "Warning: ${CENTERPOINT_CUDA_UTILS} not found"
fi

CUDA_UTILS_SRC="${SCRIPT_DIR}/autoware/src/universe/autoware_universe/sensing/autoware_cuda_utils/include/autoware/cuda_utils/cuda_check_error.hpp"
if [ -f "${CUDA_UTILS_SRC}" ]; then
    if grep -q '^#undef CHECK_CUDA_ERROR' "${CUDA_UTILS_SRC}"; then
        echo "✓ CHECK_CUDA_ERROR #undef already present in autoware_cuda_utils cuda_check_error.hpp (source)"
    else
        sed -i 's/^#define CHECK_CUDA_ERROR(e)/#undef CHECK_CUDA_ERROR\n#define CHECK_CUDA_ERROR(e)/' "${CUDA_UTILS_SRC}"
        echo "✓ Added #undef CHECK_CUDA_ERROR to autoware_cuda_utils cuda_check_error.hpp (source)"
    fi
else
    echo "Warning: ${CUDA_UTILS_SRC} not found"
fi

CUDA_UTILS_INSTALLED="${SCRIPT_DIR}/autoware/install/autoware_cuda_utils/include/autoware/cuda_utils/cuda_check_error.hpp"
if [ -f "${CUDA_UTILS_INSTALLED}" ]; then
    if grep -q '^#undef CHECK_CUDA_ERROR' "${CUDA_UTILS_INSTALLED}"; then
        echo "✓ CHECK_CUDA_ERROR #undef already present in autoware_cuda_utils cuda_check_error.hpp (installed)"
    else
        sed -i 's/^#define CHECK_CUDA_ERROR(e)/#undef CHECK_CUDA_ERROR\n#define CHECK_CUDA_ERROR(e)/' "${CUDA_UTILS_INSTALLED}"
        echo "✓ Added #undef CHECK_CUDA_ERROR to autoware_cuda_utils cuda_check_error.hpp (installed)"
    fi
else
    echo "Warning: ${CUDA_UTILS_INSTALLED} not found (autoware_cuda_utils may not be built yet)"
fi

# ==================== Fix 5: OpenCV missing modules referenced by cv_bridge ====================
# ros-humble-cv-bridge's cmake config references OpenCV contrib modules (alphamat, barcode, hdf, viz)
# that may not exist in the custom OpenCV build, causing linker failures.
# Two-pronged fix: (a) try to patch cv_bridge cmake (needs sudo), (b) create stub .so files as fallback.
OPENCV_STUBS_DIR="${HOME}/.local/lib/opencv_stubs"
MISSING_MODULES="opencv_alphamat opencv_barcode opencv_hdf opencv_viz"
STUBS_NEEDED=0
for mod in $MISSING_MODULES; do
    if [ ! -f "/usr/local/lib/lib${mod}.so" ]; then
        STUBS_NEEDED=1
        break
    fi
done

if [ "$STUBS_NEEDED" = "1" ]; then
    mkdir -p "${OPENCV_STUBS_DIR}"
    for mod in $MISSING_MODULES; do
        if [ ! -f "/usr/local/lib/lib${mod}.so" ] && [ ! -f "${OPENCV_STUBS_DIR}/lib${mod}.so" ]; then
            echo "void __stub_${mod}(void) {}" | gcc -shared -x c - -o "${OPENCV_STUBS_DIR}/lib${mod}.so" -Wl,--soname,lib${mod}.so 2>/dev/null \
                && echo "  Created stub: ${OPENCV_STUBS_DIR}/lib${mod}.so" \
                || echo "  Warning: failed to create stub for ${mod}"
        fi
    done
    echo "✓ OpenCV stub libraries created in ${OPENCV_STUBS_DIR}"

    CV_BRIDGE_EXTRAS="/opt/ros/humble/share/cv_bridge/cmake/cv_bridge-extras.cmake"
    if [ -f "${CV_BRIDGE_EXTRAS}" ]; then
        NEEDS_PATCH=0
        for mod in $MISSING_MODULES; do
            if grep -q "${mod}" "${CV_BRIDGE_EXTRAS}" && [ ! -f "/usr/local/lib/lib${mod}.so" ]; then
                NEEDS_PATCH=1
                break
            fi
        done
        if [ "$NEEDS_PATCH" = "1" ]; then
            if sudo -n true 2>/dev/null; then
                sudo cp "${CV_BRIDGE_EXTRAS}" "${CV_BRIDGE_EXTRAS}.backup"
                for mod in $MISSING_MODULES; do
                    if [ ! -f "/usr/local/lib/lib${mod}.so" ]; then
                        sudo sed -i "s/;${mod}//g" "${CV_BRIDGE_EXTRAS}"
                        sudo sed -i "s/${mod};//g" "${CV_BRIDGE_EXTRAS}"
                        sudo sed -i "s/${mod}//g" "${CV_BRIDGE_EXTRAS}"
                        echo "  Removed non-existent module: ${mod}"
                    fi
                done
                echo "✓ Patched cv_bridge-extras.cmake to remove non-existent OpenCV modules"
            else
                echo "⚠ cv_bridge-extras.cmake patch requires sudo (stub libraries used as fallback)"
            fi
        else
            echo "✓ cv_bridge-extras.cmake already patched or all modules exist"
        fi
    fi
else
    echo "✓ All OpenCV modules referenced by cv_bridge exist"
fi

echo "✓ All fixes applied successfully"

