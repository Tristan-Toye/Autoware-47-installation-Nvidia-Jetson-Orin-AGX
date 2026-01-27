# Single Node Isolation

This folder contains scripts for isolating individual ROS 2 nodes from Autoware for detailed performance profiling using [ros2_single_node_replayer](https://github.com/sykwer/ros2_single_node_replayer).

## Workflow

### Step 1: Collect Node Information
While Autoware is running, collect metadata about all nodes:
```bash
./collect_node_info.sh
```
This creates `ros2_node_inventory.csv` with package/executable info.

### Step 2: Merge with Latency Data
Combine node info with CARET latency rankings:
```bash
python3 merge_latency_with_info.py
```
This creates `merged_node_data.csv` with complete node information.

### Step 3: Prepare Isolation Scripts
Generate recording scripts for top N nodes:
```bash
./isolate_top_nodes.sh 10  # Top 10 nodes
```
This creates `single_node_run/<node_name>/record.sh` for each node.

### Step 4: Record Individual Nodes
Automated recording (recommended):
```bash
./record_single_node.sh <node_name>
```
This handles Autoware launch, replayer, rosbag, and auto-termination.

### Step 5: Run Isolated Node
After recording, run the isolated node for profiling:
```bash
./run_isolated_node.sh <node_name>
```

## Files

| File | Description |
|------|-------------|
| `config.yaml` | Configuration for paths and parameters |
| `collect_node_info.sh` | Collects node metadata from running system |
| `merge_latency_with_info.py` | Merges CARET latency with node inventory |
| `isolate_top_nodes.sh` | Generates recording scripts for top N nodes |
| `record_single_node.sh` | Automated node recording |
| `run_isolated_node.sh` | Runs previously recorded isolated node |

## Output Structure

```
single_node_run/
├── <node_name>/
│   ├── ros2_run_<package>_<executable>  # Command to run node
│   ├── <namespace>_<node>.yaml          # Node parameters
│   └── rosbag2_*/                       # Recorded input data
```

## Tips

- Run `collect_node_info.sh` with a fully-loaded Autoware scenario
- Recording may take as long as the rosbag duration × playback rate
- For perf profiling, use scripts in `../3_perf_profiling/`
