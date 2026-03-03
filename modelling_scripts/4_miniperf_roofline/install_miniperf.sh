#!/bin/bash
# =============================================================================
# Install miniperf on Nvidia Jetson Orin AGX (AArch64 / Ubuntu 22.04)
# =============================================================================
# This script:
#   1. Installs Rust via rustup (if not present)
#   2. Installs Clang 19 and the matching LLVM development libraries
#   3. Clones and builds the miniperf Rust binary
#   4. Builds the miniperf Clang pass plugin (required for roofline analysis)
#   5. Validates the installation
#
# The miniperf tool implements the agnostic roofline methodology described in:
#   "Architecture-Agnostic Roofline Modelling Using LLVM IR" (Batashev et al.)
#
# Usage: ./install_miniperf.sh [--prefix DIR]
#   --prefix DIR  : Install directory (default: $HOME/miniperf)
#   --skip-rust   : Skip Rust installation (if already installed)
#   --skip-llvm   : Skip LLVM/Clang installation (if Clang 19 is available)
# =============================================================================

set -e

# ─── Defaults ────────────────────────────────────────────────────────────────
MINIPERF_ROOT="${HOME}/miniperf"
INSTALL_RUST=true
INSTALL_LLVM=true
LLVM_VERSION=19

# ─── Argument Parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --prefix)    MINIPERF_ROOT="$2"; shift 2 ;;
        --skip-rust) INSTALL_RUST=false; shift ;;
        --skip-llvm) INSTALL_LLVM=false; shift ;;
        *)           echo "Unknown option: $1"; exit 1 ;;
    esac
done

LLVM_PROJECT_DIR="${HOME}/llvm-project"

echo "============================================================"
echo "  miniperf Installation — Jetson Orin AGX (AArch64)"
echo "============================================================"
echo "  miniperf root  : ${MINIPERF_ROOT}"
echo "  LLVM version   : ${LLVM_VERSION}"
echo "  Install Rust   : ${INSTALL_RUST}"
echo "  Install LLVM   : ${INSTALL_LLVM}"
echo "============================================================"
echo ""

# ─── Step 1: System Prerequisites ────────────────────────────────────────────
echo "[1/6] Installing system prerequisites..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    curl wget git build-essential \
    cmake ninja-build pkg-config \
    lsb-release software-properties-common \
    libcapnp-dev capnproto \
    python3-pip

echo "  System prerequisites installed."

# ─── Step 2: Install Rust ────────────────────────────────────────────────────
if [ "${INSTALL_RUST}" = true ]; then
    echo ""
    echo "[2/6] Installing Rust toolchain via rustup..."
    if command -v rustup &> /dev/null; then
        echo "  Rust already installed, updating..."
        rustup update stable
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
        # shellcheck source=/dev/null
        source "${HOME}/.cargo/env"
    fi
    # Ensure cargo is on PATH for the rest of this script
    export PATH="${HOME}/.cargo/bin:${PATH}"
    echo "  Rust version: $(rustc --version)"
else
    echo "[2/6] Skipping Rust installation."
    export PATH="${HOME}/.cargo/bin:${PATH}"
fi

# ─── Step 3: Install Clang 19 and LLVM ────────────────────────────────────────
if [ "${INSTALL_LLVM}" = true ]; then
    echo ""
    echo "[3/6] Installing Clang ${LLVM_VERSION} and LLVM libraries..."

    # Install using the official LLVM apt repository
    if ! command -v clang-${LLVM_VERSION} &> /dev/null; then
        wget -qO /tmp/llvm.sh https://apt.llvm.org/llvm.sh
        chmod +x /tmp/llvm.sh
        sudo /tmp/llvm.sh ${LLVM_VERSION} all
        rm /tmp/llvm.sh
    else
        echo "  Clang ${LLVM_VERSION} already installed."
    fi

    # Install LLVM dev libraries needed for building Clang plugins
    sudo apt-get install -y --no-install-recommends \
        "llvm-${LLVM_VERSION}-dev" \
        "clang-${LLVM_VERSION}" \
        "libclang-${LLVM_VERSION}-dev" \
        "libmlir-${LLVM_VERSION}-dev" || true

    echo "  Clang version: $(clang-${LLVM_VERSION} --version | head -1)"
else
    echo "[3/6] Skipping LLVM/Clang installation."
fi

# Determine LLVM cmake directory
LLVM_CMAKE_DIR=$(find /usr/lib/llvm-${LLVM_VERSION}/lib/cmake -name "LLVMConfig.cmake" \
                 -exec dirname {} \; 2>/dev/null | head -1)
if [ -z "${LLVM_CMAKE_DIR}" ]; then
    LLVM_CMAKE_DIR=$(find /usr -name "LLVMConfig.cmake" -exec dirname {} \; 2>/dev/null | head -1)
fi
echo "  LLVM cmake dir: ${LLVM_CMAKE_DIR}"

# ─── Step 4: Clone and Build miniperf ─────────────────────────────────────────
echo ""
echo "[4/6] Building miniperf from source..."

if [ -d "${MINIPERF_ROOT}/.git" ]; then
    echo "  Found existing repository, pulling latest..."
    git -C "${MINIPERF_ROOT}" pull --ff-only
else
    echo "  Cloning miniperf repository..."
    git clone https://github.com/alexbatashev/miniperf.git "${MINIPERF_ROOT}"
fi

cd "${MINIPERF_ROOT}"

# Build the main Rust binary in release mode
echo "  Running: cargo build --release"
cargo build --release 2>&1 | tail -5

MPERF_BIN="${MINIPERF_ROOT}/target/release/mperf"
if [ ! -f "${MPERF_BIN}" ]; then
    echo "ERROR: mperf binary not found at ${MPERF_BIN}"
    exit 1
fi
echo "  mperf binary: ${MPERF_BIN}"

# ─── Step 5: Build the Clang Plugin ───────────────────────────────────────────
echo ""
echo "[5/6] Building miniperf Clang plugin (required for roofline)..."

PLUGIN_BUILD_DIR="${MINIPERF_ROOT}/target/clang_plugin"
PLUGIN_SRC_DIR="${MINIPERF_ROOT}/utils/clang_plugin"

if [ ! -d "${PLUGIN_SRC_DIR}" ]; then
    echo "ERROR: Clang plugin source not found at ${PLUGIN_SRC_DIR}"
    echo "       Check that the miniperf repository contains utils/clang_plugin/"
    exit 1
fi

mkdir -p "${PLUGIN_BUILD_DIR}"
cd "${PLUGIN_BUILD_DIR}"

cmake -DCMAKE_BUILD_TYPE=Release \
      -GNinja \
      -DLLVM_DIR="${LLVM_CMAKE_DIR}" \
      -DCMAKE_C_COMPILER="clang-${LLVM_VERSION}" \
      -DCMAKE_CXX_COMPILER="clang++-${LLVM_VERSION}" \
      "${PLUGIN_SRC_DIR}"

ninja -j$(nproc)

PLUGIN_SO=$(find "${PLUGIN_BUILD_DIR}" -name "*.so" | head -1)
if [ -z "${PLUGIN_SO}" ]; then
    # Try .dylib on unusual setups
    PLUGIN_SO=$(find "${PLUGIN_BUILD_DIR}" -name "*.dylib" | head -1)
fi

if [ -z "${PLUGIN_SO}" ]; then
    echo "ERROR: Clang plugin .so not found after build."
    exit 1
fi

echo "  Clang plugin: ${PLUGIN_SO}"

# Create a symlink at the expected path if different
EXPECTED_PLUGIN="${PLUGIN_BUILD_DIR}/lib/miniperf_plugin.so"
if [ ! -f "${EXPECTED_PLUGIN}" ] && [ -f "${PLUGIN_SO}" ]; then
    mkdir -p "$(dirname "${EXPECTED_PLUGIN}")"
    ln -sf "${PLUGIN_SO}" "${EXPECTED_PLUGIN}"
    echo "  Symlinked plugin to: ${EXPECTED_PLUGIN}"
fi

# ─── Step 6: Validate ──────────────────────────────────────────────────────────
echo ""
echo "[6/6] Validating installation..."

# Test mperf binary
if "${MPERF_BIN}" --version &>/dev/null || "${MPERF_BIN}" --help &>/dev/null; then
    echo "  ✓  mperf binary works"
else
    echo "  ⚠  mperf binary did not respond to --version (may still work)"
fi

# Test Clang plugin loads
echo "  Testing Clang plugin..."
cat > /tmp/test_miniperf.c << 'EOF'
#include <stdio.h>
int main() { printf("hello\n"); return 0; }
EOF

if clang-${LLVM_VERSION} -O3 /tmp/test_miniperf.c -o /tmp/test_miniperf_out \
     -Xclang "-fpass-plugin=${PLUGIN_SO}" \
     -L "${MINIPERF_ROOT}/target/release/" -lcollector \
     -Wl,-rpath,"${MINIPERF_ROOT}/target/release/" 2>/dev/null; then
    echo "  ✓  Clang plugin loaded and compiled test binary"
else
    echo "  ⚠  Clang plugin test compilation failed (may need libcollector fix)"
    echo "     Check: clang-${LLVM_VERSION} -O3 test.c -fpass-plugin=${PLUGIN_SO} -lcollector"
fi
rm -f /tmp/test_miniperf.c /tmp/test_miniperf_out

echo ""
echo "============================================================"
echo "  Installation complete!"
echo "============================================================"
echo ""
echo "  mperf binary  : ${MPERF_BIN}"
echo "  Clang plugin  : ${PLUGIN_SO}"
echo "  libcollector  : ${MINIPERF_ROOT}/target/release/libcollector.so"
echo ""
echo "  Add to your shell config:"
echo "    export PATH=\"${MINIPERF_ROOT}/target/release:\$PATH\""
echo "    export MINIPERF_ROOT=\"${MINIPERF_ROOT}\""
echo ""
echo "  Next steps:"
echo "    1. Edit miniperf_config.yaml to confirm paths"
echo "    2. Run: ./build_instrumented_nodes.sh"
echo "    3. Run: ./run_miniperf_roofline.sh"
