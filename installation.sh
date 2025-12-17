set -x
set -e 



add_line_if_missing() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"
}

clean_env_for_autoware_build() {
  # Remove any existing Autoware overlay from the current shell environment.
  # This script is often run from a shell that has already sourced
  # ${SCRIPT_DIR}/autoware/install/setup.bash via ~/.bashrc, which pollutes
  # CMAKE_PREFIX_PATH / AMENT_PREFIX_PATH and can cause CMake to resolve
  # the wrong rclcpp (non‑CARET) for some packages.
  local var val
  for var in CMAKE_PREFIX_PATH AMENT_PREFIX_PATH ROS_PACKAGE_PATH LD_LIBRARY_PATH PATH; do
    # shellcheck disable=SC2086
    val=${!var-}
    [ -z "$val" ] && continue
    # Strip any entries under this repo's autoware/install
    val=$(printf '%s\n' "$val" | tr ':' '\n' | grep -v "${SCRIPT_DIR}/autoware/install" | paste -sd: -)
    # shellcheck disable=SC2163
    export "$var=$val"
  done
  # CARET preload should not be active during build
  unset LD_PRELOAD || true
}

update_bashrc_sources() {
  local bashrc="$HOME/.bashrc"
  local start="# >>> Autoware env >>>"
  local end="# <<< Autoware env <<<"
  local tmp
  tmp="$(mktemp)"
  touch "$bashrc"
  awk -v start="$start" -v end="$end" '
    $0 == start {inblock=1; next}
    $0 == end {inblock=0; next}
    !inblock {print}
  ' "$bashrc" > "$tmp"
  cat <<EOF >> "$tmp"
$start
source /opt/ros/humble/setup.bash
[ -f ${SCRIPT_DIR}/ros2_caret_ws/install/local_setup.bash ] && source ${SCRIPT_DIR}/ros2_caret_ws/install/local_setup.bash
[ -f ${SCRIPT_DIR}/ros2_humble/install/local_setup.bash ] && source ${SCRIPT_DIR}/ros2_humble/install/local_setup.bash
[ -f ${SCRIPT_DIR}/autoware/install/setup.bash ] && source ${SCRIPT_DIR}/autoware/install/setup.bash
export LD_PRELOAD=${SCRIPT_DIR}/ros2_caret_ws/install/lib/libcaret.so"
$end
EOF
  mv "$tmp" "$bashrc"
}
# export LD_LIBRARY_PATH="${SCRIPT_DIR}/ros2_caret_ws/install/lib:${LD_LIBRARY_PATH}

source_autoware_build_env() {
  # shellcheck disable=SC1091
  source /opt/ros/humble/setup.bash
  source "${SCRIPT_DIR}/ros2_humble/install/local_setup.bash"
  
  source "${SCRIPT_DIR}/ros2_caret_ws/install/local_setup.bash"
  
}
rebuild_autoware=0
rerun_autoware_setup=0

show_help() {
  cat <<'EOF'
Positional arguments:
  None
  
Optional arguments:
  -s | setup    enable the force setup autoware run option: setup-dev-env.sh is guaranteed to run
  -b | build   enable the rebuild option: colcon build is guaranteed to run
  -h | help   show this help
  --    end of options; everything after is a positional argument
  
Usage: ./script.sh [-s] [-b] [--] [args...]
  
Examples:
  ./script.sh -s
  ./script.sh -sb            # same as -s -b
  ./script.sh -bs -- file1   # flags + positional
EOF
}
while getopts ":sbh" opt; do
   case "$opt" in
      s) rerun_autoware_setup=1 ;;
      b) rebuild_autoware=1;;
      h) show_help; exit 0;;
      \?) echo "Unknown option: -$OPTARG" >&2; show_help; exit 2 ;; 
   esac
done


sudo rm -f /etc/apt/sources.list.d/ros-latest.list
sudo rm -f /etc/apt/sources.list.d/ros2.list

sudo apt clean

#echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
#export PATH="$HOME/.local/bin:$PATH"

export SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

chmod +x setup-dev-env.sh
chmod +x remove_agnocast.sh
chmod +x setup_network.sh
chmod +x setup_rqt.sh
chmod +x install_CARET.sh
chmod +x install_dear_node_viewer.sh
chmod +x install_single_node_replayer.sh


sudo apt -y update
sudo apt -y upgrade

sudo apt -y install apt-utils cmake ninja-build git python3-pytest

export CUDAToolkit_ROOT=/usr/local/cuda
#echo "export CUDAToolkit_ROOT=/usr/local/cuda" >> ~/.bashrc
add_line_if_missing 'export CUDAToolkit_ROOT=/usr/local/cuda' "$HOME/.bashrc"

# --------------------- Openv CV ---------------------------------

if [ -f "${SCRIPT_DIR}/.opencv_built_flag" ] && [ -f /usr/local/lib/cmake/opencv4/OpenCVConfig.cmake ]; then
	echo "#########################################"
	echo "#########################################"
    	echo "✅ OpenCV build flag found. Skipping build."
    	echo "#########################################"
	echo "#########################################"
else
	sudo apt remove python3-opencv -y
	sudo apt update
	sudo apt install -y build-essential pkg-config libgtk-3-dev \
	libavcodec-dev libavformat-dev libswscale-dev libv4l-dev \
	libxvidcore-dev libx264-dev libjpeg-dev libpng-dev libtiff-dev \
	gfortran openexr libatlas-base-dev python3-dev python3-numpy \
	libtbb2 libtbb-dev libdc1394-dev

	cd "${SCRIPT_DIR}"
	if [ -d opencv ]; then
		echo "opencv directory already exists. Skipping clone."
	else
		git clone https://github.com/opencv/opencv.git
	fi
	if [ -d opencv_contrib ]; then
		echo "contrib directory already exists. Skipping clone."
	else
		git clone https://github.com/opencv/opencv_contrib.git
	fi
	cd "${SCRIPT_DIR}/opencv"
	git checkout 4.x
	cd "${SCRIPT_DIR}/opencv_contrib"
	git checkout 4.x

	sudo apt-get install -y libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev 


	# https://devtalk.nvidia.com/default/topic/1007290/jetson-tx2/building-opencv-with-opengl-support-/post/5141945/#5141945
	cd /usr/local/cuda/include
	sudo mkdir -p patches
	cd patches
	sudo touch OpenGLHeader.patch
	sudo cp "${SCRIPT_DIR}/OpenGLHeader.patch" OpenGLHeader.patch
	cd ../
	sudo patch -N cuda_gl_interop.h $PWD'/patches/OpenGLHeader.patch' 
	# Clean up the OpenGL tegra libs that usually get crushed
	cd /usr/lib/aarch64-linux-gnu/
	# sudo ln -s libGL.so.1 libGL.so


	cd "${SCRIPT_DIR}/opencv"
	mkdir build && cd build

	cmake -D CMAKE_BUILD_TYPE=Release \
	-D CMAKE_INSTALL_PREFIX=/usr/local \
	-D OPENCV_EXTRA_MODULES_PATH="${SCRIPT_DIR}/opencv_contrib/modules" \
	-D OPENCV_GENERATE_PKGCONFIG=ON \
	-D WITH_CUDA=ON \
	-D CUDA_ARCH_BIN=8.7 \
	-D CUDA_ARCH_PTX="" \
	-D ENABLE_FAST_MATH=ON \
	-D CUDA_FAST_MATH=ON \
	-D WITH_CUBLAS=ON \
	-D WITH_CUDNN=ON \
	-D OPENCV_DNN_CUDA=ON \
	-D WITH_OPENGL=ON \
	-D WITH_QT=ON \
	-D WITH_GTK=ON \
	-D BUILD_TESTS=OFF \
	-D BUILD_PERF_TESTS=OFF \
	-D BUILD_EXAMPLES=OFF \
	-D BUILD_opencv_python3=ON \
	-D BUILD_opencv_barcode=ON \
	..

	make -j$(nproc)
	sudo make install
	touch "${SCRIPT_DIR}/.opencv_built_flag"
fi


# ---------------- CUMM --------------------------

INFERENCE_ONLY="${INFERENCE_ONLY:-0}" # set to 1 to generate inference-only ops (smaller/faster build)
TAG_SPCONV="${1:-v2.3.6}"                 # (unused here, kept for compatibility)
TAG_CUMM="${TAG_CUMM:-v0.8.2}"            # choose a stable tag; change if needed
PREFIX="${PREFIX:-$HOME/.local}"          # where the CMake package will be installed
PY="${PYTHON:-python3}"
USE_CUDA_SUFFIX="${USE_CUDA_SUFFIX:-1}"   # 1 => build cumm-cuXXX wheel; 0 => editable "cumm"


CFG_A="${PREFIX}/share/cmake/cumm/cummConfig.cmake"
CFG_B="${PREFIX}/cmake/cumm/cummConfig.cmake"
if [[ -f "${CFG_A}" ]]; then
	echo "#########################################"
	echo "#########################################"
  	echo "==> Found CMake package: ${CFG_A}"
	echo "#########################################"
	echo "#########################################"
elif [[ -f "${CFG_B}" ]]; then
	echo "#########################################"
	echo "#########################################"
  	echo "==> Found CMake package: ${CFG_B}"
	echo "#########################################"
	echo "#########################################"
else
	echo "==> Using cumm tag: ${TAG_CUMM}"
	echo "==> Install prefix: ${PREFIX}"
	echo "==> Python: ${PY}"
	echo "==> Build CUDA-suffixed wheel (cumm-cuXXX)? ${USE_CUDA_SUFFIX}"

	# 0) Basic sanity
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
	# cumm-cuXXX installs the 'cumm' module; both cases import as 'cumm'
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
fi

#------------------ SPCONV ---------------------------------------

# ---------- spconv (idempotent) ----------
CFG_DIR="${PREFIX}/lib/cmake/spconv"
CFG_FILE="${CFG_DIR}/spconvConfig.cmake"

# Skip rebuild if we've already installed spconv unless user forces it
if [ -f "${CFG_FILE}" ]; then
	echo "#########################################"
	echo "#########################################"
	echo "spconv already installed (found ${CFG_FILE})."
	echo "Set FORCE_SPCONV_REBUILD=1 to force a rebuild."
	echo "#########################################"
	echo "#########################################"
else


	# --- CUDA / arch detection for Orin ---
	CUDA_VER=$(
	nvcc --version | sed -n 's/.*release \([0-9]\+\)\.\([0-9]\+\).*/\1.\2/p' | head -n1
	)
	CUDA_VER="${CUDA_VER:-12.2}"
	echo "==> Detected CUDA: ${CUDA_VER}"
	export CUMM_CUDA_VERSION="${CUDA_VER}"
	export CUMM_CUDA_ARCH_LIST=8.7     # Jetson Orin (SM 87)
	export CMAKE_CUDA_ARCHITECTURES=87 # For CMake >= 3.18

	# --- Clone spconv (use a tag!) ---
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

	# --- Generate pure-C++ sources (disable JIT) ---
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

	# --- CMake build (more tolerant source globs) ---
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


	# --- Minimal CMake package that also wires cumm (needed for tensorview/* headers) ---
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


	echo "==> Install complete."
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
# ------------------- ROS installation ---------------------------
if [ -f "${SCRIPT_DIR}/.ros_humble_flag" ]; then
	echo "#########################################"
	echo "#########################################"
    	echo "ROS 2 Humble is already installed. Skipping ROS installation."
	echo "#########################################"
	echo "#########################################"
else
	echo "Installing ROS 2 Humble..."
	locale  # check for UTF-8

	sudo apt update && sudo apt install locales
	sudo locale-gen en_US en_US.UTF-8
	sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
	export LANG=en_US.UTF-8

	locale  # verify settings

	sudo apt install software-properties-common
	sudo add-apt-repository universe -y

	sudo apt update && sudo apt install curl -y
	# Robust one-liner: fetches the right asset URL for your codename
	ASSET_URL="$(curl -fsSL https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
	  | grep -oE 'https://[^"]*ros2-apt-source_[^"]*'"$(
	      . /etc/os-release; echo "${UBUNTU_CODENAME:-${VERSION_CODENAME}}"
	    )"'_all\.deb')"

	curl -fsSL -o /tmp/ros2-apt-source.deb "$ASSET_URL"
	sudo dpkg -i /tmp/ros2-apt-source.deb

	
	
	sudo apt update && sudo apt install -y \
	  python3-flake8-docstrings \
	  python3-pip \
	  python3-pytest-cov \
	  ros-dev-tools
	
	sudo apt install -y \
	   python3-flake8-blind-except \
	   python3-flake8-builtins \
	   python3-flake8-class-newline \
	   python3-flake8-comprehensions \
	   python3-flake8-deprecated \
	   python3-flake8-import-order \
	   python3-flake8-quotes \
	   python3-pytest-repeat \
	   python3-pytest-rerunfailures
	
	mkdir -p "${SCRIPT_DIR}/ros2_humble/src"
	cd "${SCRIPT_DIR}/ros2_humble"
	vcs import --input https://raw.githubusercontent.com/ros2/ros2/humble/ros2.repos src
	cd src/
	
	if [ -d diagnostics ]; then
		echo "diagnostics directory already exists. Skipping clone."
	else
		git clone -b ros2-humble https://github.com/ros/diagnostics.git
	fi

	
	if [ -d angles ]; then
		echo "angles directory already exists. Skipping clone."
	else
		git clone -b ros2-humble https://github.com/ros/angles.git
	fi

	# Fix angles CMakeLists.txt for building from source
	# See: https://github.com/ros/angles/issues/42
	ANGLES_CMAKE="${SCRIPT_DIR}/ros2_humble/src/angles/angles/CMakeLists.txt"
	if [ -f "${ANGLES_CMAKE}" ]; then
		if grep -q 'INSTALL_INTERFACE:include/angles>' "${ANGLES_CMAKE}"; then
			sed -i 's|"$<INSTALL_INTERFACE:include/angles>"|"$<INSTALL_INTERFACE:include>"|g' "${ANGLES_CMAKE}"
			echo "✓ Fixed angles CMakeLists.txt for building from source"
		fi
	fi

	if [ -d tracetools_analysis ]; then
	    	echo "tracetools directory already exists. Skipping clone."
	else
	  	git clone https://github.com/ros-tracing/tracetools_analysis.git -b humble
	fi
	
	cd ..
	
	sudo apt upgrade -y
	sudo rosdep init || true
	rosdep update
	rosdep install --from-paths src --ignore-src -y --skip-keys "fastcdr rti-connext-dds-6.0.1 urdfdom_headers"

	sudo apt-get update
	sudo apt-get install -y lttng-tools liblttng-ust-dev python3-lttng babeltrace2
	
	
	colcon build --merge-install --cmake-args -DCMAKE_BUILD_TYPE=Release 
	
	cd "${SCRIPT_DIR}/ros2_humble"
	rm -rf build
	rm -rf log

	#echo 'source /opt/ros/humble/setup.bash' >> ~/.bashrc 
	#source "${SCRIPT_DIR}/ros2_humble/install/local_setup.bash"
	#if ! ros2 run tracetools status | grep -q "Tracing enabled"; then
	#  echo "[ERROR] ROS 2 tracing is not enabled. Re-check LTTng install and the overlay build." >&2
	#  exit 1
	#fi
	
	touch "${SCRIPT_DIR}/.ros_humble_flag"
fi
sudo rm -f /etc/apt/sources.list.d/ros-latest.list 





# --------------- Autoware repo ----------------------
cd "${SCRIPT_DIR}"
sudo apt install python3.10-venv -y

if [ -f "${SCRIPT_DIR}/.autoware_setup_flag" ] && (( ! rerun_autoware_setup )); then
	echo "#########################################"
	echo "#########################################"
    	echo "Autoware setup already ran. Skipping setup-dev-env.sh script."
	echo "#########################################"
	echo "#########################################"
else
	if [ -d autoware ]; then
	    	echo "Autoware directory already exists. Checking out tag 1.5.0..."
		cd autoware
		git fetch --tags
		git checkout 1.5.0 || {
			echo "Warning: Could not checkout tag 1.5.0. Current branch/commit:"
			git describe --tags --always
		}
		cd "${SCRIPT_DIR}"
	else
	  	git clone --branch 1.5.0 --tags https://github.com/autowarefoundation/autoware.git
		echo "#############################################"
		echo "Autoware 1.5.0 cloned and checked out"
		echo "#############################################"
	fi
	cp "${SCRIPT_DIR}/setup-dev-env.sh" "${SCRIPT_DIR}/autoware/setup-dev-env.sh"
	cd "${SCRIPT_DIR}/autoware"

	./setup-dev-env.sh -y --no-nvidia --no-cuda-drivers --download-artifacts
	touch "${SCRIPT_DIR}/.autoware_setup_flag"
fi


#----------------- ROS dependencies ---------------------------------
#TODO: check if can be omitted
# source /opt/ros/humble/setup.bash
# Make sure all previously installed ros-$ROS_DISTRO-* packages are upgraded to their latest version
sudo apt -y update 
sudo apt -y upgrade

rosdep update
sudo apt -y update

if [ -f  "${SCRIPT_DIR}/.ros_dependencies" ] && (( ! rebuild_autoware )) ; then
	echo "#########################################"
	echo "#########################################"
    	echo "Rosdep dependencies already installed. rosdep install -y --from-paths src --ignore-src --rosdistro ${ROS_DISTRO}"
	echo "#########################################"
	echo "#########################################"
	
else
	[ -d src ] && sudo rm -rf src
	mkdir src
	#source /opt/ros/humble/setup.bash
	cd "${SCRIPT_DIR}/autoware"
	vcs import src < autoware.repos
	vcs import src < extra-packages.repos

	rosdep install -y --from-paths src --ignore-src --rosdistro humble

	cd "${SCRIPT_DIR}"
	sudo apt install ros-humble-cv-bridge -y
	sudo apt install ros-humble-rosbag2-storage-default-plugins ros-humble-sqlite3-vendor 
	sudo apt install -y ros-humble-grid-map-cv \
		            ros-humble-grid-map-core \
		            ros-humble-grid-map-ros \
		            ros-humble-grid-map-msgs
	
	#source /opt/ros/humble/setup.bash
	touch "${SCRIPT_DIR}/.ros_dependencies"
fi 

# --------------- tracing & CARET ---------------


sudo apt update

echo "installing caret"
cd "${SCRIPT_DIR}"
./install_CARET.sh


# --------------------- Fix Autoware installation issues ----------------------
cd "${SCRIPT_DIR}"
chmod +x fix_autoware_installation.sh
./fix_autoware_installation.sh


# --------------------- CCache ----------------------
sudo apt -y update && sudo apt -y install ccache
mkdir -p ~/.cache/ccache
touch ~/.cache/ccache/ccache.conf
echo "max_size = 60G" >> ~/.cache/ccache/ccache.conf
export CC="/usr/lib/ccache/gcc"
export CXX="/usr/lib/ccache/g++"
export CCACHE_DIR="$HOME/.cache/ccache/"


# -------------------- Colcon Build ------------------------
cd "${SCRIPT_DIR}/autoware"

# Clean any Autoware overlay from the current shell environment so that CMake
# sees a clean base (opt/ros + ros2_humble + CARET) instead of resolving
# rclcpp / friends from a previously sourced autoware/install.
# This is CRITICAL when building with --packages-up-to, because dependencies
# are built first and must use CARET's rclcpp, not a previously built autoware rclcpp.
clean_env_for_autoware_build

# Reset CMAKE_PREFIX_PATH to just .local (from bashrc), then source in same order as working script
# This ensures a clean environment that matches test_autoware_dummy_perception_publisher.sh
export CMAKE_PREFIX_PATH="$HOME/.local"

source_autoware_build_env

# after: source /opt/ros/humble/setup.bash
export CUDAToolkit_ROOT=/usr/local/cuda
export spconv_DIR="$HOME/.local/lib/cmake/spconv"
export cumm_DIR="$HOME/.local/share/cmake/cumm"   # or .../lib/cmake/cumm if that’s where yours installed

if ! ros2 run tracetools status | grep -q "Tracing enabled"; then
	  echo "[ERROR] ROS 2 tracing is not enabled. Re-check LTTng install and the overlay build." >&2
	  exit 1
fi

# CRITICAL: Ensure CARET's tracetools library is found at LINK TIME, not the system version
# The system /opt/ros/humble/lib/libtracetools.so exists but doesn't have CARET's symbols.
# We MUST ensure CARET's version is found FIRST by the linker.
# 
# LIBRARY_PATH: Used by GCC/ld at LINK TIME to find libraries (MOST IMPORTANT for this fix)
# LD_LIBRARY_PATH: Used by dynamic linker at RUNTIME to find libraries
# CMAKE_LIBRARY_PATH: Used by CMake's find_library() to search for libraries
#
# Order matters: CARET's paths MUST come BEFORE any system paths to avoid linking
# against the system's libtracetools.so which lacks CARET-specific symbols.
export LIBRARY_PATH="${SCRIPT_DIR}/ros2_caret_ws/install/lib:${SCRIPT_DIR}/ros2_humble/install/tracetools/lib${LIBRARY_PATH:+:${LIBRARY_PATH}}"
export LD_LIBRARY_PATH="${SCRIPT_DIR}/ros2_caret_ws/install/lib:${SCRIPT_DIR}/ros2_humble/install/tracetools/lib:${LD_LIBRARY_PATH}"
export CMAKE_LIBRARY_PATH="${SCRIPT_DIR}/ros2_caret_ws/install/lib:${SCRIPT_DIR}/ros2_humble/install/tracetools/lib${CMAKE_LIBRARY_PATH:+:${CMAKE_LIBRARY_PATH}}"
export LD_PRELOAD="${SCRIPT_DIR}/ros2_caret_ws/install/lib/libcaret.so"

# Debug: show environment before build and write to file
{
	echo "=== Build Environment ==="
	echo "CMAKE_PREFIX_PATH=$CMAKE_PREFIX_PATH"
	echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
	echo "LIBRARY_PATH=$LIBRARY_PATH"
	echo "CMAKE_LIBRARY_PATH=$CMAKE_LIBRARY_PATH"
	echo "spconv_DIR=$spconv_DIR"
	echo "cumm_DIR=$cumm_DIR"
	echo "========================="
} | tee "${SCRIPT_DIR}/installation_env"

# Function to detect failed packages from colcon build output
detect_failed_packages() {
	local log_file="$1"
	local failed_file="$2"
	
	# Extract the summary section from the log starting from "Summary:" line
	# This ensures we get the complete summary even if the log is very long
	local summary_section=""
	if grep -q "^Summary:" "$log_file" 2>/dev/null; then
		# Extract everything from the first "Summary:" line to the end of the file
		summary_section=$(sed -n '/^Summary:/,$p' "$log_file" 2>/dev/null || echo "")
		echo "Found Summary: in log file"
	elif grep -q "Summary:" "$log_file" 2>/dev/null; then
		# Fallback: extract from any line containing "Summary:" to the end
		summary_section=$(sed -n '/Summary:/,$p' "$log_file" 2>/dev/null || echo "")
		echo "Found summary with fallback method"
	else
		# Last resort: use last 100 lines if no "Summary:" found
		summary_section=$(tail -100 "$log_file" 2>/dev/null || echo "")
		echo "Summary not found, taking last 100 lines"
	fi
	
	# Extract failed packages from colcon summary
	# Colcon summary format: "  X packages failed: package1 package2 package3"
	# First try the summary format
	if echo "$summary_section" | grep -q "packages failed:"; then
		# Extract the line with "packages failed:" and get all package names after the colon
		echo "$summary_section" | grep "packages failed:" | \
			sed 's/.*packages failed: *//' | \
			tr ' ' '\n' | \
			grep -v '^$' | \
			sort -u > "$failed_file" || true
	fi
	
	# Also check for "Failed <<<" format (individual package failures during build)
	if [ -s "$failed_file" ]; then
		# Merge with any "Failed <<<" entries
		grep -E "Failed <<<" "$log_file" 2>/dev/null | \
			sed 's/.*Failed <<< \([^ ]*\).*/\1/' | \
			sort -u >> "$failed_file" || true
	else
		# If summary didn't work, try "Failed <<<" format
		grep -E "Failed <<<" "$log_file" 2>/dev/null | \
			sed 's/.*Failed <<< \([^ ]*\).*/\1/' | \
			sort -u > "$failed_file" || true
	fi
	
	# Also check colcon's result files if available (as backup)
	if [ -d "log/latest_build" ]; then
		find log/latest_build -name "stderr" -exec grep -l "error\|Error\|ERROR\|failed\|Failed" {} \; 2>/dev/null | \
		while read -r stderr_file; do
			# Extract package name from path: log/latest_build/package_name/stderr
			package_name=$(basename "$(dirname "$stderr_file")")
			echo "$package_name" >> "$failed_file"
		done
	fi
	
	# Remove duplicates and empty lines
	sort -u "$failed_file" -o "$failed_file" 2>/dev/null || true
	sed -i '/^$/d' "$failed_file" 2>/dev/null || true
	
	# Count failed packages
	local failed_count=0
	if [ -f "$failed_file" ]; then
		failed_count=$(wc -l < "$failed_file" 2>/dev/null | tr -d ' ' || echo "0")
	fi
	
	if [ "$failed_count" -gt 0 ]; then
		echo "Detected $failed_count failed package(s)"
		return 0
	else
		echo "No failed packages detected"
		return 1
	fi
}

# Function to build with error handling and retry
build_with_retry() {
	local build_log="${SCRIPT_DIR}/autoware_build.log"
	local failed_packages_file="${SCRIPT_DIR}/failed_packages.txt"
	local max_retries=3
	local retry_count=0
	
	# Initial build with continue-on-error
	echo "=========================================="
	echo "Building Autoware with CARET (continuing on errors)..."
	echo "=========================================="
	
	colcon build --symlink-install --cmake-clean-cache \
	  --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
	  --continue-on-error 2>&1 | tee "$build_log"
	
	local build_exit_code=${PIPESTATUS[0]}
	
	# Detect failed packages
	rm -f "$failed_packages_file"
	detect_failed_packages "$build_log" "$failed_packages_file"
	
	if [ ! -s "$failed_packages_file" ]; then
		echo "✓ All packages built successfully!"
		return 0
	fi
	
	echo ""
	echo "=========================================="
	echo "Failed packages detected. Writing to: $failed_packages_file"
	echo "=========================================="
	cat "$failed_packages_file"
	echo ""
	
	# Retry failed packages
	while [ $retry_count -lt $max_retries ] && [ -s "$failed_packages_file" ]; do
		retry_count=$((retry_count + 1))
		echo ""
		echo "=========================================="
		echo "Retry attempt $retry_count of $max_retries for failed packages..."
		echo "=========================================="
		
		# Build failed packages
		local packages_to_build=$(tr '\n' ' ' < "$failed_packages_file" | sed 's/ $//')
		echo "Retrying packages: $packages_to_build"
		
		colcon build --packages-select $packages_to_build \
		  --symlink-install \
		  --cmake-clean-cache \
		  --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
		  2>&1 | tee -a "$build_log"
		
		local retry_exit_code=${PIPESTATUS[0]}
		
		# Update failed packages list
		rm -f "$failed_packages_file"
		detect_failed_packages "$build_log" "$failed_packages_file"
		
		if [ ! -s "$failed_packages_file" ]; then
			echo "✓ All packages built successfully after retry!"
			return 0
		fi
		
		echo "Still have $(wc -l < "$failed_packages_file" | tr -d ' ') failed package(s)"
	done
	
	# Final status
	if [ -s "$failed_packages_file" ]; then
		echo ""
		echo "=========================================="
		echo "⚠ WARNING: Some packages failed after $max_retries retries"
		echo "Failed packages written to: $failed_packages_file"
		echo "=========================================="
		cat "$failed_packages_file"
		return 1
	else
		echo "✓ All packages built successfully!"
		return 0
	fi
}

if (( rebuild_autoware )); then
	echo "Cleaning build and install directories..."
	rm -rf build install log
	rm -f "${SCRIPT_DIR}/.autoware_build_flag"
	rm -f "${SCRIPT_DIR}/failed_packages.txt"
	rm -f "${SCRIPT_DIR}/autoware_build.log"
	echo "✓ Cleaned build directories"
	build_with_retry
	touch "${SCRIPT_DIR}/.autoware_build_flag"
elif [ ! -f "${SCRIPT_DIR}/.autoware_build_flag" ]; then
	# Build if flag doesn't exist (first time build)
	build_with_retry
	touch "${SCRIPT_DIR}/.autoware_build_flag"
else
	echo "#########################################"
	echo "#########################################"
	echo "Autoware colcon build already ran. Skipping build."
	echo "Use -b flag to force rebuild."
	echo "#########################################"
	echo "#########################################"
fi



echo ""
echo "=========================================="
echo "✓ Build complete!"
echo "=========================================="
echo ""
echo "Verifying CARET instrumentation..."
ros2 caret check_caret_rclcpp ./


update_bashrc_sources


cd "${SCRIPT_DIR}"
echo "#########################################"
echo "#########################################"
echo "build done!!"
echo "#########################################"
echo "#########################################"

./remove_agnocast.sh
./setup_network.sh
sudo ./setup_rqt.sh
./install_single_node_replayer.sh
./install_dear_node_viewer.sh


# Install perf tools for Jetson
# Try to find matching kernel tools package
KERNEL_VERSION=$(uname -r)
echo "Detected kernel version: ${KERNEL_VERSION}"

# First, try installing the metapackage that should auto-select the right version
if ! sudo apt install -y linux-tools-nvidia-tegra 2>/dev/null; then
    echo "Failed to install linux-tools-nvidia-tegra, trying generic package..."
    # Fallback: try to find the closest matching version
    # Extract base version (e.g., 5.15.148 from 5.15.148-tegra)
    BASE_VERSION=$(echo "${KERNEL_VERSION}" | cut -d'-' -f1)
    # Try to find a matching package
    MATCHING_PKG=$(apt-cache search linux-tools.*nvidia-tegra | grep -o "linux-tools-[0-9].*-nvidia-tegra" | head -n1)
    if [ -n "${MATCHING_PKG}" ]; then
        echo "Attempting to install ${MATCHING_PKG}..."
        sudo apt install -y "${MATCHING_PKG}" || echo "Warning: Could not install matching perf tools package"
    else
        echo "Warning: No matching perf tools package found for kernel ${KERNEL_VERSION}"
        echo "You may need to manually install perf tools for your specific kernel"
    fi
fi

# Check if perf is available and create symlink for custom kernel versions if needed
# Look for perf in both linux-tools and linux-nvidia-tegra-tools directories
COMPATIBLE_PERF=$(find /usr/lib -name "perf" -type f 2>/dev/null | grep -E "linux.*tegra.*tools|linux-tools.*tegra" | grep "5.15" | head -n1)
if [ -z "${COMPATIBLE_PERF}" ]; then
    # Try alternative search pattern
    COMPATIBLE_PERF=$(find /usr/lib -path "*tegra*" -name "perf" -type f 2>/dev/null | grep "5.15" | head -n1)
fi

if [ -n "${COMPATIBLE_PERF}" ] && [ ! -f "/usr/lib/linux-tools/${KERNEL_VERSION}/perf" ]; then
    echo "Creating symlink for custom kernel ${KERNEL_VERSION} to compatible perf..."
    echo "  Source: ${COMPATIBLE_PERF}"
    sudo mkdir -p "/usr/lib/linux-tools/${KERNEL_VERSION}"
    sudo ln -sf "${COMPATIBLE_PERF}" "/usr/lib/linux-tools/${KERNEL_VERSION}/perf"
    echo "✓ Created symlink for perf compatibility"
elif [ -z "${COMPATIBLE_PERF}" ]; then
    echo "⚠ Warning: Could not find compatible perf binary for symlink creation"
fi

# Check if perf is available
if command -v perf >/dev/null 2>&1; then
    # Test if perf actually works (not just the wrapper)
    if perf --version >/dev/null 2>&1; then
        echo "✓ perf is available and working"
    else
        echo "✓ perf is available in PATH (may show kernel version warnings for custom kernels)"
    fi
else
    echo "⚠ Warning: perf not found. You may need to install linux-tools-${KERNEL_VERSION} manually"
fi
cd "${SCRIPT_DIR}"
 

 
