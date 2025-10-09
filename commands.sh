
# autoware with graphical interface
ros2 launch autoware_launch logging_simulator.launch.xml map_path:=$HOME/autoware_map/sample-map-rosbag vehicle_model:=sample_vehicle sensor_model:=sample_sensor_kit rviz:=false

#autoware without graphical interface
ros2 launch autoware_launch logging_simulator.launch.xml map_path:=$HOME/autoware_map/sample-map-rosbag vehicle_model:=sample_vehicle sensor_model:=sample_sensor_kit


#runnig rosbag replay
ros2 bag play ~/autoware_map/sample-rosbag/ -r 0.2 -s sqlite3

# rqt graph
ros2 run rqt_graph rqt_graph

#opeen rqt
rqt
