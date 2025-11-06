add_line_if_missing() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"
}
export SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# is being called from installation.sh
git clone --recursive git@github.com:hoffstadt/DearPyGui.git
cd DearPyGui
git checkout v2.1
chmod +x BuildPythonForLinux.sh
./BuildPythonForLinux.sh

cd ../
mkdir cmake-build-debug
cd cmake-build-debug
cmake ..
cd ..
cmake --build cmake-build-debug --config Debug

pip install .

cd "${SCRIPT_DIR}"

sudo apt install graphviz graphviz-dev
git clone https://github.com/takeshi-iwanari/dear_ros_node_viewer.git
cd dear_ros_node_viewer
pip3 install -r requirements.txt

#python3 main.py path-to-graph-file
add_line_if_missing() "alias node-graph=${SCRIPT_DIR}/dear_ros_node_viewer/main.py" "$HOME/.bashrc"
