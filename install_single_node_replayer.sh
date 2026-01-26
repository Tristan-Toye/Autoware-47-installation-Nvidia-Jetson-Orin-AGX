set -x
set -e 

add_line_if_missing() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"
}
export SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [ -d ros2_single_node_replayer ]; then
	echo "ros2_single_node_replayer directory already exists. Skipping clone."
else
git clone https://github.com/sykwer/ros2_single_node_replayer.git
fi

 #After launching a whole ROS 2 App, start the tool before playing the rosbag 
 # (i.e., launch a ROS 2 App → start the tool → play the rosbag to start the ROS 2 App). 
 #In the terminal where you run the tool, do not forget to run the script that sets the environment 
 # variables required for the ROS 2 App to work (i.e., setup.bash).

cd ros2_single_node_replayer
#pip install -r requirements.txt

cd "${SCRIPT_DIR}"
# https://github.com/sykwer/ros2_single_node_replayer

add_line_if_missing "alias single-node-replayer='python3 ${SCRIPT_DIR}/ros2_single_node_replayer/recorder.py'" "$HOME/.bashrc"