#!/bin/bash
# =============================================================================
# Install Experiment Dependencies
# =============================================================================
# Installs all tools needed for the performance modelling experiments:
#   1. Rust toolchain via rustup
#   2. Clang-19 + LLVM dev libraries (requires sudo)
#   3. miniperf (patched for aarch64 / Jetson Orin AGX)
#   4. mpld3 Python package
#
# Usage: ./install_experiment_deps.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MINIPERF_ROOT="${HOME}/miniperf"

echo "============================================================"
echo "  Experiment Dependencies Installation"
echo "============================================================"
echo ""

# ─── Step 1: Rust via rustup ────────────────────────────────────────────────
echo "[1/4] Installing Rust toolchain..."
if [ -f "${HOME}/.cargo/env" ]; then
    source "${HOME}/.cargo/env"
fi
if command -v rustup &> /dev/null; then
    echo "  Rust already installed ($(rustc --version)), updating..."
    rustup update stable
else
    echo "  Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    source "${HOME}/.cargo/env"
fi
export PATH="${HOME}/.cargo/bin:${PATH}"
echo "  Rust: $(rustc --version)"
echo ""

# ─── Step 2: Clang-19 + LLVM (requires sudo) ────────────────────────────────
echo "[2/4] Installing Clang 19 and LLVM libraries..."
if command -v clang-19 &> /dev/null; then
    echo "  Clang 19 already installed: $(clang-19 --version | head -1)"
else
    echo "  Installing system prerequisites..."
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends \
        curl wget git build-essential \
        cmake ninja-build pkg-config \
        lsb-release software-properties-common gnupg \
        libcapnp-dev capnproto python3-pip

    echo "  Adding LLVM apt repository and installing Clang 19..."
    wget -qO /tmp/llvm.sh https://apt.llvm.org/llvm.sh
    chmod +x /tmp/llvm.sh
    sudo /tmp/llvm.sh 19 all
    rm -f /tmp/llvm.sh

    sudo apt-get install -y --no-install-recommends \
        llvm-19-dev clang-19 libclang-19-dev libmlir-19-dev 2>/dev/null || true
fi
echo ""

# ─── Step 3: miniperf (with aarch64 patch) ──────────────────────────────────
echo "[3/4] Building miniperf..."
if [ -f "${MINIPERF_ROOT}/target/release/mperf" ]; then
    echo "  miniperf already built at ${MINIPERF_ROOT}/target/release/mperf"
else
    if [ -d "${MINIPERF_ROOT}/.git" ]; then
        echo "  Found existing repository..."
    else
        echo "  Cloning miniperf repository..."
        git clone https://github.com/alexbatashev/miniperf.git "${MINIPERF_ROOT}"
    fi

    # Patch for aarch64 (Jetson Orin AGX): add get_host_cpu_family stub
    CPUFAMILY="${MINIPERF_ROOT}/pmu/src/cpu_family.rs"
    if ! grep -q 'target_arch = "aarch64"' "${CPUFAMILY}" 2>/dev/null; then
        echo "  Patching cpu_family.rs for aarch64 support..."
        sed -i '/#\[cfg(target_arch = "riscv64")\]/i \
#[cfg(target_arch = "aarch64")]\
pub fn get_host_cpu_family() -> \&'\''static str {\
    "unknown"\
}\
' "${CPUFAMILY}"
    fi

    cd "${MINIPERF_ROOT}"
    echo "  Building mperf binary (release mode)..."
    cargo build --release 2>&1 | tail -5

    if [ ! -f "${MINIPERF_ROOT}/target/release/mperf" ]; then
        echo "  ERROR: mperf binary not found after build"
        exit 1
    fi
fi
echo "  mperf: ${MINIPERF_ROOT}/target/release/mperf"
echo ""

# ─── Step 3b: Build Clang plugin (only if clang-19 available) ────────────────
if command -v clang-19 &> /dev/null; then
    PLUGIN_SRC="${MINIPERF_ROOT}/utils/clang_plugin"
    PLUGIN_BUILD="${MINIPERF_ROOT}/target/clang_plugin"
    if [ -d "${PLUGIN_SRC}" ]; then
        LLVM_CMAKE_DIR=$(find /usr/lib/llvm-19/lib/cmake -name "LLVMConfig.cmake" \
                         -exec dirname {} \; 2>/dev/null | head -1)
        if [ -z "${LLVM_CMAKE_DIR}" ]; then
            LLVM_CMAKE_DIR=$(find /usr -name "LLVMConfig.cmake" -exec dirname {} \; 2>/dev/null | head -1)
        fi

        if [ -n "${LLVM_CMAKE_DIR}" ]; then
            echo "  Building miniperf Clang plugin..."
            mkdir -p "${PLUGIN_BUILD}"
            cd "${PLUGIN_BUILD}"
            cmake -DCMAKE_BUILD_TYPE=Release -GNinja \
                  -DLLVM_DIR="${LLVM_CMAKE_DIR}" \
                  -DCMAKE_C_COMPILER=clang-19 \
                  -DCMAKE_CXX_COMPILER=clang++-19 \
                  "${PLUGIN_SRC}"
            ninja -j$(nproc)
            PLUGIN_SO=$(find "${PLUGIN_BUILD}" -name "*.so" | head -1)
            echo "  Clang plugin: ${PLUGIN_SO:-NOT FOUND}"
        else
            echo "  WARNING: LLVM cmake dir not found, skipping Clang plugin build"
        fi
    else
        echo "  WARNING: Clang plugin source not found at ${PLUGIN_SRC}"
    fi
else
    echo "  Skipping Clang plugin build (clang-19 not found)"
fi
echo ""

# ─── Step 4: mpld3 Python package ───────────────────────────────────────────
echo "[4/4] Installing mpld3 Python package..."
pip3 install --user mpld3 2>/dev/null || pip install --user mpld3 2>/dev/null || {
    echo "  WARNING: Could not install mpld3 (interactive roofline HTML will be skipped)"
}
echo ""

# ─── Validation ──────────────────────────────────────────────────────────────
echo "============================================================"
echo "  Validation"
echo "============================================================"
check_tool() {
    if command -v "$1" &> /dev/null; then echo "  [OK] $1"; else echo "  [MISSING] $1"; fi
}
check_tool rustc
check_tool cargo
check_tool clang-19
check_tool perf
check_tool lttng
[ -f "${MINIPERF_ROOT}/target/release/mperf" ] && echo "  [OK] mperf" || echo "  [MISSING] mperf"
python3 -c "import mpld3; print('  [OK] mpld3')" 2>/dev/null || echo "  [MISSING] mpld3"
python3 -c "import pandas; print('  [OK] pandas')" 2>/dev/null || echo "  [MISSING] pandas"
python3 -c "import matplotlib; print('  [OK] matplotlib')" 2>/dev/null || echo "  [MISSING] matplotlib"
python3 -c "import numpy; print('  [OK] numpy')" 2>/dev/null || echo "  [MISSING] numpy"
python3 -c "import bokeh; print('  [OK] bokeh')" 2>/dev/null || echo "  [MISSING] bokeh"
python3 -c "import yaml; print('  [OK] pyyaml')" 2>/dev/null || echo "  [MISSING] pyyaml"

echo ""
echo "============================================================"
echo "  Installation complete!"
echo "============================================================"
