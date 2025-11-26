#!/bin/bash
set -e

# Script to fix autoware_lidar_centerpoint package.xml by adding diagnostic_updater dependency if missing

export SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PACKAGE_XML="${SCRIPT_DIR}/autoware/src/universe/autoware_universe/perception/autoware_lidar_centerpoint/package.xml"

# Check if package.xml exists
if [ ! -f "${PACKAGE_XML}" ]; then
    echo "Warning: package.xml not found at ${PACKAGE_XML}"
    echo "Skipping diagnostic_updater dependency fix."
    exit 0
fi

# Check if diagnostic_updater dependency is already present
if grep -q "<depend>diagnostic_updater</depend>" "${PACKAGE_XML}"; then
    echo "✓ diagnostic_updater dependency already present in package.xml"
    exit 0
fi

# Find the line number after cuda_blackboard dependency
CUDA_BLACKBOARD_LINE=$(grep -n "<depend>cuda_blackboard</depend>" "${PACKAGE_XML}" | cut -d: -f1)

if [ -z "${CUDA_BLACKBOARD_LINE}" ]; then
    echo "Warning: Could not find cuda_blackboard dependency in package.xml"
    echo "Skipping diagnostic_updater dependency fix."
    exit 1
fi

# Insert the diagnostic_updater dependency after cuda_blackboard
# Using sed to insert after the line
sed -i "${CUDA_BLACKBOARD_LINE}a\  <depend>diagnostic_updater</depend>" "${PACKAGE_XML}"

echo "✓ Added diagnostic_updater dependency to package.xml"

