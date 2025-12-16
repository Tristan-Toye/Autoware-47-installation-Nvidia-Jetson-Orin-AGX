#!/bin/bash
set -e

KERNEL_VERSION=$(uname -r)
echo "Detected kernel version: ${KERNEL_VERSION}"

# Try installing the metapackage first
echo "Attempting to install linux-tools-nvidia-tegra..."
if sudo apt install -y linux-tools-nvidia-tegra; then
    echo "✓ Installed linux-tools-nvidia-tegra"
else
    echo "Package not available, trying alternative approach..."
fi

# Check if perf is now available and create symlink for custom kernel versions
KERNEL_VERSION=$(uname -r)
# Look for perf in both linux-tools and linux-nvidia-tegra-tools directories
COMPATIBLE_PERF=$(find /usr/lib -name "perf" -type f 2>/dev/null | grep -E "linux.*tegra.*tools|linux-tools.*tegra" | grep "5.15" | head -n1)
if [ -z "${COMPATIBLE_PERF}" ]; then
    # Try alternative search pattern
    COMPATIBLE_PERF=$(find /usr/lib -path "*tegra*" -name "perf" -type f 2>/dev/null | grep "5.15" | head -n1)
fi

if [ -z "${COMPATIBLE_PERF}" ]; then
    # Last resort: try the specific known location
    if [ -f "/usr/lib/linux-nvidia-tegra-tools-5.15.0-1048/perf" ]; then
        COMPATIBLE_PERF="/usr/lib/linux-nvidia-tegra-tools-5.15.0-1048/perf"
    fi
fi

if [ -n "${COMPATIBLE_PERF}" ] && [ ! -f "/usr/lib/linux-tools/${KERNEL_VERSION}/perf" ]; then
    echo "Creating symlink for custom kernel ${KERNEL_VERSION} to compatible perf..."
    echo "  Source: ${COMPATIBLE_PERF}"
    sudo mkdir -p "/usr/lib/linux-tools/${KERNEL_VERSION}"
    sudo ln -sf "${COMPATIBLE_PERF}" "/usr/lib/linux-tools/${KERNEL_VERSION}/perf"
    echo "✓ Created symlink: /usr/lib/linux-tools/${KERNEL_VERSION}/perf -> ${COMPATIBLE_PERF}"
elif [ -z "${COMPATIBLE_PERF}" ]; then
    echo "⚠ Warning: Could not find compatible perf binary"
fi

# Check if perf is now available
if command -v perf >/dev/null 2>&1; then
    echo "Testing perf..."
    if perf --version >/dev/null 2>&1; then
        echo "✓ perf is now available and working"
        perf --version
        exit 0
    else
        echo "⚠ perf found but still showing errors. Checking symlink..."
    fi
fi

# With the symlink created above, /usr/bin/perf wrapper should now work correctly
# No need for alias - the wrapper will find perf at the symlinked location

# If still not found, provide instructions
echo ""
echo "⚠ perf tools not found for kernel ${KERNEL_VERSION}"
echo ""
echo "Available options:"
echo "1. Try installing generic package:"
echo "   sudo apt install linux-tools-tegra"
echo ""
echo "2. Check available packages matching your kernel:"
echo "   apt-cache search linux-tools.*tegra | grep 5.15"
echo ""
echo "3. You may need to build perf from source or install a matching kernel tools package"
echo ""
echo "4. As a workaround, you can use perf from a similar kernel version:"
echo "   sudo apt install linux-tools-5.15.0-1048-nvidia-tegra  # or similar version"

