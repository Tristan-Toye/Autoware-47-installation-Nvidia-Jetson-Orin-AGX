set -x
set -e 



add_line_if_missing() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"
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
	
	git clone -b ros2-humble https://github.com/ros/diagnostics.git

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
	source "${SCRIPT_DIR}/ros2_humble/install/local_setup.bash"
	if ! ros2 run tracetools status | grep -q "Tracing enabled"; then
	  echo "[ERROR] ROS 2 tracing is not enabled. Re-check LTTng install and the overlay build." >&2
	  exit 1
	fi
	
	add_line_if_missing "source ${SCRIPT_DIR}/ros2_humble/install/local_setup.bash" "$HOME/.bashrc"
	touch "${SCRIPT_DIR}/.ros_humble_flag"
fi
sudo rm -f /etc/apt/sources.list.d/ros-latest.list 


# --------------- tracing & CARET ---------------


sudo apt update

echo "installing caret"
cd "${SCRIPT_DIR}"
./install_CARET.sh



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
	    	echo "Autoware directory already exists. Skipping clone."
	else
	  	git clone https://github.com/autowarefoundation/autoware.git
	  	# git checkout 1.5.0
	fi
	cp "${SCRIPT_DIR}/setup-dev-env.sh" "${SCRIPT_DIR}/autoware/setup-dev-env.sh"
	cd "${SCRIPT_DIR}/autoware"

	./setup-dev-env.sh -y --no-nvidia --no-cuda-drivers --download-artifacts
	touch "${SCRIPT_DIR}/.autoware_setup_flag"
fi

source ~/.bashrc


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

	cd "${SCRIPT_DIR}/autoware"
	vcs import src < autoware.repos
	vcs import src < extra-packages.repos

	rosdep install -y --from-paths src --ignore-src --rosdistro $ROS_DISTRO

	cd "${SCRIPT_DIR}"
	sudo apt install ros-$ROS_DISTRO-cv-bridge -y
	sudo apt install ros-"${ROS_DISTRO}"-rosbag2-storage-default-plugins ros-"${ROS_DISTRO}"-sqlite3-vendor 
	sudo apt install -y ros-$ROS_DISTRO-grid-map-cv \
		            ros-$ROS_DISTRO-grid-map-core \
		            ros-$ROS_DISTRO-grid-map-ros \
		            ros-$ROS_DISTRO-grid-map-msgs
	source /opt/ros/humble/setup.bash
	add_line_if_missing "source /opt/ros/humble/setup.bash" "$HOME/.bashrc"
	touch "${SCRIPT_DIR}/.ros_dependencies"
fi 

# --------------------- Fix autoware_lidar_centerpoint package.xml ----------------------
cd "${SCRIPT_DIR}"
chmod +x fix_lidar_centerpoint.sh
./fix_lidar_centerpoint.sh

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

# after: source /opt/ros/humble/setup.bash
export CUDAToolkit_ROOT=/usr/local/cuda

export CMAKE_PREFIX_PATH="$HOME/.local${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export spconv_DIR="$HOME/.local/lib/cmake/spconv"
export cumm_DIR="$HOME/.local/share/cmake/cumm"   # or .../lib/cmake/cumm if that’s where yours installed

# optional: prove it
echo "CMAKE_PREFIX_PATH=$CMAKE_PREFIX_PATH"
echo "spconv_DIR=$spconv_DIR"
echo "cumm_DIR=$cumm_DIR"


if [ -f "${SCRIPT_DIR}/.autoware_build_flag" ] && (( ! rebuild_autoware )) ; then
	echo "#########################################"
	echo "#########################################"
    	echo "Autoware colcon build already ran. Skipping colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release."
	echo "#########################################"
	echo "#########################################"
else
	colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
	touch "${SCRIPT_DIR}/.autoware_build_flag"
fi



cd "${SCRIPT_DIR}"
echo "#########################################"
echo "#########################################"
echo "build done!!"
echo "#########################################"
echo "#########################################"

./remove_agnocast.sh
./setup_network.sh
sudo ./setup_rqt.sh


add_line_if_missing "source ${SCRIPT_DIR}/autoware/install/setup.bash" "$HOME/.bashrc"
sudo apt install linux-tools-nvidia-tegra

cd /usr/lib
PERF_LOCATION="$(ls | grep 'linux-nvidia-tegra-tools')"

add_line_if_missing "alias perf=/usr/lib/${PERF_LOCATION}/perf"
 "$HOME/.bashrc"
 

 
