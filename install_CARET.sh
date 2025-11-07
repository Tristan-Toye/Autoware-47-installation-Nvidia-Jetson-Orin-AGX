set -x
set -e 

add_line_if_missing() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"
}
export SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"




if [ -d ros2_caret_ws ]; then
	echo "CARET directory already exists. Skipping clone."
else
	git clone https://github.com/tier4/caret.git ros2_caret_ws
fi

cd ros2_caret_ws
mkdir -p src
vcs import src < caret.repos
./setup_caret.sh 
source /opt/ros/humble/setup.bash
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
source "${SCRIPT_DIR}/ros2_caret_ws/install/local_setup.bash"
add_line_if_missing "source ${SCRIPT_DIR}/ros2_caret_ws/install/local_setup.bash" "$HOME/.bashrc"
add_line_if_missing "export LD_PRELOAD=$(readlink -f ${SCRIPT_DIR}/ros2_caret_ws/install/caret_trace/lib/libcaret.so)" "$HOME/.bashrc"
ros2 run tracetools status # return Tracing enabled


