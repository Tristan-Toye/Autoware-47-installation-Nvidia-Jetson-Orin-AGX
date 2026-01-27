#!/bin/bash

# 1. Generate the Documentation File (Markdown)
cat << EOF > ros2_nodes_documentation.md
# ROS 2 Introspection Guide

## Essential Commands
- **List Nodes:** \`ros2 node list\`
- **Node Details:** \`ros2 node info <node_name>\`
- **Package Executables:** \`ros2 pkg executables <package_name>\`

## Useful Documentation Links
- [ROS 2 Node Design](https://design.ros2.org/articles/node_namespaces.html)
- [Official CLI Tool Guide](https://docs.ros.org/en/humble/Concepts/Basic/About-Command-Line-Tools.html)
EOF

# 2. Generate the CSV using Shell Commands
CSV_FILE="ros2_node_inventory.csv"

# Write the CSV Header
echo "Namespace,Node_Name,Package,Executable" > $CSV_FILE

echo "Scanning ROS 2 Humble graph..."

# Loop through every node found by the ROS 2 CLI
for full_node_name in $(ros2 node list); do
    # Extract Namespace and Node Name using string manipulation
    # Namespace is everything before the last slash, Node Name is after
    namespace=$(echo "$full_node_name" | sed 's/\/[^\/]*$//')
    if [ -z "$namespace" ]; then namespace="/"; fi
    node_name=$(echo "$full_node_name" | sed 's/.*\///')

    # Use 'ps' to find the command line that started this node
    # We grep for the node name to find the process
    process_info=$(ps -ef | grep "$node_name" | grep -v "grep" | grep -v "ros2 node" | head -n 1)
    
    # Heuristic to find the path (usually contains /install/<package>/lib/<package>/<executable>)
    executable_path=$(echo "$process_info" | awk '{print $NF}')
    
    # Split the path to find Package and Executable
    # In ROS 2, the executable is usually in a folder named after the package
    package=$(echo "$executable_path" | rev | cut -d'/' -f2 | rev)
    executable=$(echo "$executable_path" | rev | cut -d'/' -f1 | rev)

    # Fallback if ps doesn't return a clear path
    if [[ "$executable_path" != *"/"* ]]; then
        package="Unknown"
        executable="Unknown"
    fi

    # Append to CSV
    echo "$namespace,$node_name,$package,$executable" >> $CSV_FILE
done

echo "Done! Report saved to $CSV_FILE and documentation to ros2_nodes_documentation.md"