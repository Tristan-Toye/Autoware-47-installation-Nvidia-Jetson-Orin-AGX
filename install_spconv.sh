#!/bin/bash
set -e

# SPCONV Installation Script
# This script installs SPCONV (Sparse Convolution) library

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}"

TAG_SPCONV="${TAG_SPCONV:-v2.3.6}"
PREFIX="${PREFIX:-$HOME/.local}"
PY="${PYTHON:-python3}"

CFG_DIR="${PREFIX}/lib/cmake/spconv"
CFG_FILE="${CFG_DIR}/spconvConfig.cmake"

# Skip rebuild if we've already installed spconv unless user forces it
if [ -f "${CFG_FILE}" ] && [ "${FORCE_SPCONV_REBUILD:-0}" != "1" ]; then
	echo "#########################################"
	echo "#########################################"
	echo "spconv already installed (found ${CFG_FILE})."
	echo "Set FORCE_SPCONV_REBUILD=1 to force a rebuild."
	echo "#########################################"
	echo "#########################################"
else
	echo "Installing SPCONV..."


	# CUDA / arch detection for Orin
	CUDA_VER=$(
	nvcc --version | sed -n 's/.*release \([0-9]\+\)\.\([0-9]\+\).*/\1.\2/p' | head -n1
	)
	CUDA_VER="${CUDA_VER:-12.2}"
	echo "==> Detected CUDA: ${CUDA_VER}"
	export CUMM_CUDA_VERSION="${CUDA_VER}"
	export CUMM_CUDA_ARCH_LIST=8.7     # Jetson Orin (SM 87)
	export CMAKE_CUDA_ARCHITECTURES=87 # For CMake >= 3.18

	# Clone spconv (use a tag!)
	cd "${SCRIPT_DIR}"
	if [[ ! -d spconv ]]; then
		git clone https://github.com/traveller59/spconv
	fi
	cd "${SCRIPT_DIR}/spconv"
	git fetch --tags
	git checkout "tags/${TAG_SPCONV}" -f

	cp "${SCRIPT_DIR}/spconv_project.toml" pyproject.toml
	cp "${SCRIPT_DIR}/spconv_setup.py" setup.py

	$PY -m pip install -e .

	# Generate pure-C++ sources (disable JIT)
	export SPCONV_DISABLE_JIT=1
	export CUMM_DISABLE_JIT=1

	BUILD_ROOT="${PWD}/build-libspconv"
	INC_OUT="${BUILD_ROOT}/spconv/include"
	SRC_OUT="${BUILD_ROOT}/spconv/src"
	mkdir -p "${INC_OUT}" "${SRC_OUT}"

	echo "==> Generating C++ sources via spconv.gencode ..."
	set +e
	${PY} -m spconv.gencode --include="${INC_OUT}" --src="${SRC_OUT}"
	GEN_RET1=$?
	NUM_GEN_FILES=$(find "${SRC_OUT}" -type f \( -name '*.cu' -o -name '*.cc' -o -name '*.cpp' \) | wc -l)
	if [ "${GEN_RET1}" -ne 0 ] || [ "${NUM_GEN_FILES}" -eq 0 ]; then
		echo "==> No sources with --include/--src; retrying with --include_dir/--src_dir ..."
		${PY} -m spconv.gencode --include_dir="${INC_OUT}" --src_dir="${SRC_OUT}"
	fi
	set -e

	NUM_GEN_FILES=$(find "${SRC_OUT}" -type f \( -name '*.cu' -o -name '*.cc' -o -name '*.cpp' \) | wc -l)
	if [ "${NUM_GEN_FILES}" -eq 0 ]; then
		echo "ERROR: spconv.gencode produced no sources in ${SRC_OUT}."
		${PY} -m spconv.gencode --help || true
		find "${SRC_OUT}" -maxdepth 3 -type d -print
		exit 1
	fi
	echo "==> Generated ${NUM_GEN_FILES} source files."

	# CMake build (more tolerant source globs)
	CMAKE_DIR="${BUILD_ROOT}/cmake"
	mkdir -p "${CMAKE_DIR}"
	cat > "${CMAKE_DIR}/CMakeLists.txt" <<- 'CMAKE'
	cmake_minimum_required(VERSION 3.18)
	project(libspconv LANGUAGES CXX CUDA)
	set(CMAKE_CXX_STANDARD 17)
	set(CMAKE_POSITION_INDEPENDENT_CODE ON)
	find_package(cumm REQUIRED)

	if(NOT DEFINED INC_OUT OR NOT DEFINED SRC_OUT)
	message(FATAL_ERROR "INC_OUT and SRC_OUT must be provided via -DINC_OUT= -DSRC_OUT=")
	endif()

	file(GLOB_RECURSE GEN_SRC
	"${SRC_OUT}/*.cu" "${SRC_OUT}/*.cc" "${SRC_OUT}/*.cpp"
	"${SRC_OUT}/**/*.cu" "${SRC_OUT}/**/*.cc" "${SRC_OUT}/**/*.cpp")

	if(NOT GEN_SRC)
	message(FATAL_ERROR "No generated sources found under ${SRC_OUT}")
	endif()

	add_library(spconv STATIC ${GEN_SRC})
	set_target_properties(spconv PROPERTIES CUDA_SEPARABLE_COMPILATION ON)
	target_link_libraries(spconv PUBLIC cumm::cumm)
	target_include_directories(spconv PUBLIC "${INC_OUT}")

	install(DIRECTORY "${INC_OUT}/" DESTINATION include/spconv)
	install(TARGETS spconv
	LIBRARY DESTINATION lib
	ARCHIVE DESTINATION lib
	RUNTIME DESTINATION bin)
	CMAKE

	BUILD_DIR="${BUILD_ROOT}/build"
	cmake -S "${CMAKE_DIR}" -B "${BUILD_DIR}" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX="${PREFIX}" \
	-DCMAKE_CUDA_ARCHITECTURES="${CMAKE_CUDA_ARCHITECTURES}" \
	-DINC_OUT="${INC_OUT}" -DSRC_OUT="${SRC_OUT}" \
	-DCMAKE_PREFIX_PATH="${PREFIX}" \
	-DCMAKE_CUDA_FLAGS="--expt-relaxed-constexpr"

	cmake --build "${BUILD_DIR}" -j"$(nproc)"
	cmake --install "${BUILD_DIR}"

	# Minimal CMake package that also wires cumm (needed for tensorview/* headers)
	CFG_DIR="${PREFIX}/lib/cmake/spconv"
	install -d "${CFG_DIR}"

	# Render the template with the actual install prefix
	TMP_CFG="$(mktemp)"
	sed -e "s|@PREFIX@|${PREFIX}|g" "${SCRIPT_DIR}/spconvConfig.cmake.in" > "${TMP_CFG}"

	# Only update if changed (idempotent)
	if ! cmp -s "${TMP_CFG}" "${CFG_DIR}/spconvConfig.cmake" 2>/dev/null; then
		mv "${TMP_CFG}" "${CFG_DIR}/spconvConfig.cmake"
	else
		rm -f "${TMP_CFG}"
	fi

	echo "==> Installed spconv CMake config to: ${CFG_DIR}/spconvConfig.cmake"


	
	echo "✅ SPCONV installation complete!"
# Quick verification
	echo "export CMAKE_PREFIX_PATH=\"${PREFIX}:\$CMAKE_PREFIX_PATH\""
fi

# Quick verification (either path):
echo "==> CMake package (if present):"
ls -1 "${CFG_DIR}/spconvConfig.cmake" 2>/dev/null || true

echo
echo
echo "SPCONV installation succesfull!!"
echo 
echo
