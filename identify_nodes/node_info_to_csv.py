#!/usr/bin/env python3

import rclpy
import csv
import subprocess
import os
from rclpy.node import Node

def get_node_metadata():
    rclpy.init()
    # Create a temporary node to peek at the graph
    helper_node = rclpy.create_node('metadata_scraper')
    
    node_names_with_namespaces = helper_node.get_node_names_and_namespaces()
    
    data_rows = []
    
    print(f"Found {len(node_names_with_namespaces)} nodes. Collecting metadata...")

    for name, namespace in node_names_with_namespaces:
        # Ignore the scraper node itself
        if name == 'metadata_scraper':
            continue
            
        # Default values if package/executable can't be found
        package_name = "Unknown"
        executable_name = "Unknown"

        # Try to find the process info via system ps
        # This searches for the node name in the system process list
        try:
            cmd = f"ps -ef | grep {name} | grep -v grep"
            ps_output = subprocess.check_output(cmd, shell=True).decode('utf-8')
            
            # Heuristic: ROS 2 paths usually look like .../package_name/executable_name
            parts = ps_output.split()
            full_path = parts[-1] 
            path_segments = full_path.split('/')
            
            if len(path_segments) >= 2:
                executable_name = path_segments[-1]
                package_name = path_segments[-2]
        except Exception:
            # Fallback if ps fails or node name isn't in the command string
            pass

        data_rows.append({
            "Node Name": name,
            "Namespace": namespace,
            "Package": package_name,
            "Executable": executable_name
        })

    # Write to CSV
    filename = "ros2_node_inventory.csv"
    with open(filename, mode='w', newline='') as f:
        fieldnames = ["Node Name", "Namespace", "Package", "Executable"]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(data_rows)

    print(f"Successfully saved node metadata to {filename}")
    helper_node.destroy_node()
    rclpy.shutdown()

if __name__ == '__main__':
    get_node_metadata()