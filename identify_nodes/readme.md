# ROS 2 Node Metadata Guide

This document outlines how to retrieve the **Package Name**, **Executable Name**, **Namespace**, and **Node Name** for active nodes in a ROS 2 environment.

---

## 1. Quick Introspection Commands

| Goal | Command |
| :--- | :--- |
| **List Node & Namespace** | `ros2 node list` |
| **Get Detailed Node Info** | `ros2 node info <node_name>` |
| **Find Package & Executable** | `ros2 doctor --report` |
| **Search for Executables** | `ros2 pkg executables <package_name>` |

---

## 2. Component Definitions

### A. Namespace and Node Name
When you run `ros2 node list`, the output follows the pattern:  
`/<namespace>/<node_name>`

* **Namespace:** The directory-like prefix (e.g., `/robots/drone1`). If a node is in the "global" namespace, it will just show as `/node_name`.
* **Node Name:** The specific identity of that node instance. Note that the node name can be different from the executable name if it was remapped at runtime.

### B. Package and Executable
These represent the "Source" of the node on your disk.
* **Package Name:** The software container (e.g., `turtlesim`).
* **Executable Name:** The specific binary or script within that package (e.g., `turtlesim_node`).

To find these for a running system, use:
```bash
ros2 doctor --report