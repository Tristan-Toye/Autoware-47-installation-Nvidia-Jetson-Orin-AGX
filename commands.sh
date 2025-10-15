
# autoware with graphical interface
rocds2 launch autoware_launch logging_simulator.launch.xml map_path:=$HOME/autoware_map/sample-map-rosbag vehicle_model:=sample_vehicle sensor_model:=sample_sensor_kit 

#autoware without graphical interface
ros2 launch autoware_launch logging_simulator.launch.xml map_path:=$HOME/autoware_map/sample-map-rosbag vehicle_model:=sample_vehicle sensor_model:=sample_sensor_kit rviz:=false


#runnig rosbag replay
ros2 bag play ~/autoware_map/sample-rosbag/ -r 0.2 -s sqlite3

# rqt graph
ros2 run rqt_graph rqt_graph

#opeen rqt
rqt

#running nsys
nsys profile \
  --trace=cuda,osrt,nvtx \
  --sample=cpu --cpuctxsw=process-tree \
  -o test1_0910_1506 \
  ros2 bag play ~/autoware_map/sample-rosbag/ -r 0.2 -s sqlite3
  
# running perf stats

perf stat -o perf.out -- ros2 bag play ~/autoware_map/sample-rosbag/ -r 0.2 -s sqlite3
