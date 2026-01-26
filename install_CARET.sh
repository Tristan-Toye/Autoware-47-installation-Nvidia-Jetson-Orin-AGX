set -x
set -e 

add_line_if_missing() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"
}


export SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [ -f "${SCRIPT_DIR}/.caret_built_flag" ] && [ -f /usr/local/lib/cmake/opencv4/OpenCVConfig.cmake ]; then
	echo "#########################################"
	echo "#########################################"
    	echo "✅ CARET build flag found. Skipping build."
    	echo "#########################################"
	echo "#########################################"
else

if [ -d "${SCRIPT_DIR}/ros2_caret_ws" ]; then
	echo "CARET directory already exists. Skipping clone."
else
	cd "${SCRIPT_DIR}"
	git clone https://github.com/tier4/caret.git ros2_caret_ws
fi

cd "${SCRIPT_DIR}/ros2_caret_ws"
mkdir -p src
vcs import src < caret.repos
./setup_caret.sh 
source /opt/ros/humble/setup.bash
if [ -f "${SCRIPT_DIR}/ros2_humble/install/local_setup.bash" ]; then
	# shellcheck disable=SC1090
	source "${SCRIPT_DIR}/ros2_humble/install/local_setup.bash"
fi
colcon build --merge-install --cmake-args -DCMAKE_BUILD_TYPE=Release



source "${SCRIPT_DIR}/ros2_caret_ws/install/local_setup.bash"
# add_line_if_missing "export LD_PRELOAD=${SCRIPT_DIR}/ros2_caret_ws/install/lib/libcaret.so" "$HOME/.bashrc"
ros2 run tracetools status # return Tracing enabled
touch "${SCRIPT_DIR}/.caret_built_flag"

fi