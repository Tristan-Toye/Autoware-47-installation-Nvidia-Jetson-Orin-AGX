#!/bin/bash
set -e

# CUMM Installation Script
# This script installs CUMM (CUDA Matrix Multiplication) library

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}"

add_line_if_missing() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"
}

TAG_CUMM="${TAG_CUMM:-v0.8.2}"
PREFIX="${PREFIX:-$HOME/.local}"
PY="${PYTHON:-python3}"
USE_CUDA_SUFFIX="${USE_CUDA_SUFFIX:-1}"   # 1 => build cumm-cuXXX wheel; 0 => editable "cumm"


CFG_A="${PREFIX}/share/cmake/cumm/cummConfig.cmake"
CFG_B="${PREFIX}/cmake/cumm/cummConfig.cmake"
if [[ -f "${CFG_A}" ]] || [[ -f "${CFG_B}" ]]; then
	echo "#########################################"
	echo "#########################################"
  	echo "==> CUMM already installed. Skipping."
	echo "#########################################"
	echo "#########################################"
else
	echo "Installing CUMM..."
	echo "==> Using cumm tag: ${TAG_CUMM}"
	echo "==> Install prefix: ${PREFIX}"
	echo "==> Python: ${PY}"
	echo "==> Build CUDA-suffixed wheel (cumm-cuXXX)? ${USE_CUDA_SUFFIX}"

	# Basic sanity checks
	command -v nvcc >/dev/null || { echo "nvcc not found. Install CUDA first."; exit 1; }
	if [[ "$(uname -m)" != "aarch64" ]]; then
	  echo "Warning: this script is tuned for Jetson (aarch64)."
	fi

	# 1) Tooling (pin setuptools<80 to avoid colcon-core 0.20.0 conflict; upgrade packaging to fix canonicalize_version error)
	${PY} -m pip install -U pip wheel pccm ccimport 
	${PY} -m pip install --upgrade --force-reinstall "setuptools<80"
	${PY} -m pip install --upgrade --force-reinstall "packaging>=24.1"



	#2) Clean any existing installs (no wildcards—query then uninstall)
	mapfile -t _OLD_PKGS < <(${PY} -m pip list --format=freeze \
	  | sed 's/==.*//' \
	  | grep -E '^(cumm|cumm-cu[0-9]+|spconv|spconv-cu[0-9]+)$' || true)
	if (( ${#_OLD_PKGS[@]} )); then
	  ${PY} -m pip uninstall -y "${_OLD_PKGS[@]}"
	fi


	# 3) Orin arch for JIT builds
	export CUMM_CUDA_ARCH_LIST=8.7   # required for NVIDIA embedded boards (Orin = SM 87)
	# (spconv docs: set 8.7 for Orin)  # ref: traveller59/spconv README
	# https://github.com/traveller59/spconv  (For NVIDIA Embedded: CUMM_CUDA_ARCH_LIST=8.7)
	# (citation provided separately)

	# --- CUDA version detection (for cumm-cuXXX naming) ---
	CUDA_VER=$(
	  nvcc --version | sed -n 's/.*release \([0-9]\+\)\.\([0-9]\+\).*/\1.\2/p' | head -n1
	)
	CUDA_VER="${CUDA_VER:-12.6}"
	CUDA_DIGITS="${CUDA_VER//./}"   # e.g., 12.6 -> 126
	echo "==> Detected CUDA: ${CUDA_VER}  (digits: ${CUDA_DIGITS})"

	# 4) Clone/update cumm and checkout a tag (use tags, not main)
	cd "${SCRIPT_DIR}"
	if [[ ! -d cumm ]]; then
	  git clone https://github.com/FindDefinition/cumm
	fi
	cd "${SCRIPT_DIR}/cumm"
	git fetch --tags
	git checkout "tags/${TAG_CUMM}" -f

	if [[ "${USE_CUDA_SUFFIX}" == "1" ]]; then
	  echo "==> Building CUDA-suffixed wheel: cumm-cu${CUDA_DIGITS}"
	  # Official wheel build path:
	  #   export CUMM_CUDA_VERSION=<ver>; export CUMM_DISABLE_JIT=1; python setup.py bdist_wheel; pip install dists/*.whl
	  # (The README uses 'dists'; some envs emit 'dist', so we check both.)  :contentReference[oaicite:1]{index=1}
	  export CUMM_CUDA_VERSION="${CUDA_VER}"
	  export CUMM_DISABLE_JIT=1
	  ${PY} setup.py bdist_wheel
	  # pick the wheel (prefer 'dists', fallback to 'dist')
	  WHEEL_PATH="$(ls -1 dists/*cu${CUDA_DIGITS}*.whl 2>/dev/null || true)"
	  if [[ -z "${WHEEL_PATH}" ]]; then
	    WHEEL_PATH="$(ls -1 dist/*cu${CUDA_DIGITS}*.whl 2>/dev/null || true)"
	  fi
	  if [[ -z "${WHEEL_PATH}" ]]; then
	    echo "ERROR: built wheel not found for cu${CUDA_DIGITS}. Check build logs."; exit 1
	  fi
	  echo "==> Installing ${WHEEL_PATH}"
	  ${PY} -m pip install "${WHEEL_PATH}"
	  # Keep env for spconv so it resolves to spconv-cu${CUDA_DIGITS} and depends on cumm-cu${CUDA_DIGITS}
	  # (If you plan to install plain 'spconv' later, unset CUMM_CUDA_VERSION before pip install -e .)
	else
	  echo "==> Installing editable 'cumm' (no CUDA-suffixed wheel)"
	  # Python editable install (JIT/dev)
	  ${PY} -m pip install -e .
	fi

	# 5) ALSO install a CMake package so CMake find_package(cumm) works:
	#    This installs headers + cummConfig.cmake to $PREFIX/share/cmake/cumm
	cmake -S . -B build-cmake \
	  -DCMAKE_BUILD_TYPE=Release \
	  -DCMAKE_INSTALL_PREFIX="${PREFIX}"
	cmake --build build-cmake -j"$(nproc)"
	cmake --install build-cmake

	# 6) Verification
	echo "==> Python site-package:"
	${PY} - <<- 'PY'
	import importlib, pathlib, sys
	import cumm
	print("cumm module:", pathlib.Path(cumm.__file__).resolve())
	PY

	CFG_A="${PREFIX}/share/cmake/cumm/cummConfig.cmake"
	CFG_B="${PREFIX}/cmake/cumm/cummConfig.cmake"
	if [[ -f "${CFG_A}" ]]; then
	  echo "==> Found CMake package: ${CFG_A}"
	elif [[ -f "${CFG_B}" ]]; then
	  echo "==> Found CMake package: ${CFG_B}"
	else
	  echo "!! Could not find cummConfig.cmake under ${PREFIX}. Check the build logs."
	fi

	echo
	echo "==> To let Autoware/CMake find cumm, export:"
	echo "export CMAKE_PREFIX_PATH=\"${PREFIX}:\$CMAKE_PREFIX_PATH\""
	export CMAKE_PREFIX_PATH="${PREFIX}:${CMAKE_PREFIX_PATH:-}"
	#echo "export CMAKE_PREFIX_PATH=\"${PREFIX}:\$CMAKE_PREFIX_PATH\"" >> ~/.bashrc
	add_line_if_missing "export CMAKE_PREFIX_PATH=\"${PREFIX}:\$CMAKE_PREFIX_PATH\"" "$HOME/.bashrc"
	
	echo "✅ CUMM installation complete!"
fi

