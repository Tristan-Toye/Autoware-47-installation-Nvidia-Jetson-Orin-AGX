set -x
set -e 

# Cache sudo password at the start to avoid repeated prompts
echo "Please enter your sudo password (will be cached for this session)..."
sudo -v
# Keep sudo alive by refreshing every 5 minutes in background
# This is a standard pattern: background process that refreshes sudo and exits when parent dies
(
  set +x  # Disable verbose mode in subshell
  while kill -0 "$$" 2>/dev/null; do
    sudo -n true 2>/dev/null
    sleep 300
  done
) >/dev/null 2>&1 &

add_line_if_missing() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"
}

remove_bashrc_sources() {
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
  mv "$tmp" "$bashrc"
}

remove_bashrc_sources

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
source ${SCRIPT_DIR}/ros2_tracing/install/setup.bash
source ${SCRIPT_DIR}/ros2_caret_ws/install/local_setup.bash
source ${SCRIPT_DIR}/autoware/install/setup.bash
export LD_PRELOAD=${SCRIPT_DIR}/ros2_caret_ws/install/lib/libcaret.so
$end
EOF
  mv "$tmp" "$bashrc"
}
rebuild_autoware=0
rerun_autoware_setup=0
rebuild_failed_packages=0
verbose_link=0
show_help() {
  cat <<'EOF'
Positional arguments:
  None
  
Optional arguments:
  -s | setup    enable the force setup autoware run option: setup-dev-env.sh is guaranteed to run
  -b | build   enable the rebuild option: colcon build is guaranteed to run
  -r | rebuild-failed   rebuild only packages listed in unable_to_build.txt
  -d | debug-link   enable verbose link logging (CARET_VERBOSE_LINK=1)
  -h | help   show this help
  --    end of options; everything after is a positional argument
  
Usage: ./installation.sh [-s] [-b] [-r] [--] [args...]
  
Examples:
  ./installation.sh -s
  ./installation.sh -sb            # same as -s -b
  ./installation.sh -bs -- file1   # flags + positional
  ./installation.sh -r             # rebuild only failed packages from unable_to_build.txt
EOF
}
while getopts ":sbrdh" opt; do
   case "$opt" in
      s) rerun_autoware_setup=1 ;;
      b) rebuild_autoware=1;;
      r) rebuild_failed_packages=1;;
	  d) verbose_link=1;;
      h) show_help; exit 0;;
      \?) echo "Unknown option: -$OPTARG" >&2; show_help; exit 2 ;; 
   esac
done

export CARET_VERBOSE_LINK="${verbose_link}"
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
chmod +x install_opencv.sh
chmod +x install_cumm.sh
chmod +x install_spconv.sh
chmod +x install_ros2.sh
chmod +x install_CARET.sh
chmod +x install_dear_node_viewer.sh
chmod +x install_single_node_replayer.sh


sudo apt -y update
sudo apt -y upgrade

sudo apt -y install apt-utils cmake ninja-build git python3-pytest

export CUDAToolkit_ROOT=/usr/local/cuda
#echo "export CUDAToolkit_ROOT=/usr/local/cuda" >> ~/.bashrc
add_line_if_missing 'export CUDAToolkit_ROOT=/usr/local/cuda' "$HOME/.bashrc"

# --------------------- OpenCV ---------------------------------
export SCRIPT_DIR
"${SCRIPT_DIR}/install_opencv.sh"

# ---------------- CUMM --------------------------
INFERENCE_ONLY="${INFERENCE_ONLY:-0}" # set to 1 to generate inference-only ops (smaller/faster build)
TAG_SPCONV="${1:-v2.3.6}"                 # (unused here, kept for compatibility)
TAG_CUMM="${TAG_CUMM:-v0.8.2}"            # choose a stable tag; change if needed
PREFIX="${PREFIX:-$HOME/.local}"          # where the CMake package will be installed
PY="${PYTHON:-python3}"
USE_CUDA_SUFFIX="${USE_CUDA_SUFFIX:-1}"   # 1 => build cumm-cuXXX wheel; 0 => editable "cumm"
export INFERENCE_ONLY TAG_SPCONV TAG_CUMM PREFIX PY USE_CUDA_SUFFIX
"${SCRIPT_DIR}/install_cumm.sh"

#------------------ SPCONV ---------------------------------------
"${SCRIPT_DIR}/install_spconv.sh"

# ------------------- ROS installation ---------------------------
"${SCRIPT_DIR}/install_ros2.sh" 





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
			exit 1
		}
		echo "Autoware 1.5.0 checked out successfully"
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
	
	#source /opt/ros/humble/setup.bash
	cd "${SCRIPT_DIR}/autoware"
	[ -d src ] && sudo rm -rf src
	mkdir src
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
# Temporarily disable set -x for build script to reduce verbose output
{ set +x; } 2>/dev/null

run_build_autoware_clean() {
	local rebuild_flag="$1"
	local packages="$2"
	# Use a clean shell so previous sourcing does not affect the build.
	# Keep only minimal environment and source in the correct order.
	env -i \
		HOME="$HOME" \
		USER="$USER" \
		LOGNAME="$LOGNAME" \
		PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
		SCRIPT_DIR="$SCRIPT_DIR" \
		CARET_VERBOSE_LINK="$CARET_VERBOSE_LINK" \
		bash -lc '
			set -e
			if [ -n "$1" ]; then
				"${SCRIPT_DIR}/build_autoware.sh" "${SCRIPT_DIR}" "$0" "$1"
			else
				"${SCRIPT_DIR}/build_autoware.sh" "${SCRIPT_DIR}" "$0"
			fi
		' "${rebuild_flag}" "${packages}"
}

if [ "$rebuild_failed_packages" = "1" ]; then
	# Read packages from unable_to_build.txt
	unable_to_build_file="${SCRIPT_DIR}/unable_to_build.txt"
	if [ ! -f "$unable_to_build_file" ]; then
		echo "Error: unable_to_build.txt not found. Cannot rebuild failed packages." >&2
		exit 1
	fi
	if [ ! -s "$unable_to_build_file" ]; then
		echo "unable_to_build.txt is empty. No packages to rebuild." >&2
		exit 0
	fi
	# Convert newline-separated list to space-separated
	packages_to_rebuild=$(tr '\n' ' ' < "$unable_to_build_file" | sed 's/ $//')
	echo "Rebuilding failed packages from unable_to_build.txt: $packages_to_rebuild"
	run_build_autoware_clean "${rebuild_autoware}" "autoware_dummy_perception_publisher"
else
	run_build_autoware_clean "${rebuild_autoware}"
fi
exit 0
set -x

update_bashrc_sources
# Source the Autoware environment directly (safer than sourcing .bashrc in a script)
source /opt/ros/humble/setup.bash
source "${SCRIPT_DIR}/ros2_tracing/install/setup.bash"
source "${SCRIPT_DIR}/ros2_caret_ws/install/local_setup.bash"
source "${SCRIPT_DIR}/autoware/install/setup.bash"
export LD_PRELOAD="${SCRIPT_DIR}/ros2_caret_ws/install/lib/libcaret.so"


echo ""
echo "=========================================="
echo "✓ Build complete!"
echo "=========================================="
echo ""
echo "Verifying ROS 2 tracing is enabled..."
if ! ros2 run tracetools status | grep -q "Tracing enabled"; then
	echo "[ERROR] ROS 2 tracing is not enabled. Re-check LTTng install and the overlay build." >&2
	exit 1
fi
echo "✓ ROS 2 tracing is enabled"

echo ""
echo "Verifying CARET instrumentation..."
cd "${SCRIPT_DIR}/autoware"
ros2 caret check_caret_rclcpp . > "${SCRIPT_DIR}/autoware_nodes__build_with_caret.txt" 2>&1
echo "CARET verification output saved to: ${SCRIPT_DIR}/autoware_nodes__build_with_caret.txt"





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

# Add commands.sh log directory setup to .bashrc (write absolute path)
LOG_DIR="${SCRIPT_DIR}/logs"
add_line_if_missing "LOG_DIR=\"${LOG_DIR}\"" "$HOME/.bashrc"
mkdir -p ${LOG_DIR} 
 