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

echo "✓ All fixes applied successfully"

