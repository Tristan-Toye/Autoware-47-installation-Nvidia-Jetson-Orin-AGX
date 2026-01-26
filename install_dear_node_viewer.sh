
set -x
set -e 

add_line_if_missing() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"
}
export SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# is being called from installation.sh
if [ -d DearPyGui ]; then
	echo "DearPyGui directory already exists. Skipping clone."
else
	# Use HTTPS instead of SSH to avoid LTTng interference with SSH
	git clone --recursive https://github.com/hoffstadt/DearPyGui.git
fi
cd DearPyGui
git checkout v2.1.0
chmod +x scripts/BuildPythonForLinux.sh
./scripts/BuildPythonForLinux.sh


mkdir -p cmake-build-debug
cd cmake-build-debug
cmake ..
cd ..
cmake --build cmake-build-debug --config Debug

pip install .

cd "${SCRIPT_DIR}"

sudo apt install graphviz graphviz-dev
if [ -d dear_ros_node_viewer ]; then
	echo "dear_ros_node_viewer directory already exists. Skipping clone."
else
	git clone https://github.com/takeshi-iwanari/dear_ros_node_viewer.git
fi
cd dear_ros_node_viewer
pip3 install -r requirements.txt

#python3 main.py path-to-graph-file
add_line_if_missing "alias node-graph=${SCRIPT_DIR}/dear_ros_node_viewer/main.py" "$HOME/.bashrc"
