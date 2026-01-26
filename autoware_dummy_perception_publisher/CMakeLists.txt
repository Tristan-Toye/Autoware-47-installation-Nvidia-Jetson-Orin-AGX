cmake_minimum_required(VERSION 3.14)
project(autoware_dummy_perception_publisher)

find_package(autoware_cmake REQUIRED)
autoware_package()

find_package(autoware_point_types REQUIRED)

# Force CARET's rclcpp and tracetools first so tracing symbols resolve
set(rclcpp_DIR "/home/tristan-toye/Autoware-47-installation-Nvidia-Jetson-Orin-AGX/ros2_caret_ws/install/share/rclcpp/cmake")
set(tracetools_DIR "/home/tristan-toye/Autoware-47-installation-Nvidia-Jetson-Orin-AGX/ros2_caret_ws/install/share/tracetools/cmake")

find_package(rclcpp REQUIRED)
find_package(rclcpp_components REQUIRED)
find_package(tracetools REQUIRED)

# See ndt_omp package for documentation on why PCL is special
find_package(PCL REQUIRED COMPONENTS common filters)

set(${PROJECT_NAME}_DEPENDENCIES
  autoware_perception_msgs
  autoware_point_types
  tier4_perception_msgs
  pcl_conversions
  rclcpp
  sensor_msgs
  std_msgs
  tf2
  tf2_geometry_msgs
  tf2_ros
)

ament_auto_add_library(signed_distance_function SHARED
  src/signed_distance_function.cpp
)

ament_auto_add_library(${PROJECT_NAME}_component SHARED
  src/node.cpp
  src/object_info.cpp
  src/movement_utils.cpp
  src/pointcloud_creator.cpp
  src/straight_line_object_movement_plugin.cpp
  src/predicted_object_movement_plugin.cpp
)

target_link_libraries(${PROJECT_NAME}_component
  signed_distance_function
)

ament_target_dependencies(${PROJECT_NAME}_component ${${PROJECT_NAME}_DEPENDENCIES})

target_link_libraries(${PROJECT_NAME}_component
  rclcpp::rclcpp
  tracetools::tracetools
)

# PCL uses anonymous structs/unions; silence pedantic Werror for this target
target_compile_options(${PROJECT_NAME}_component PRIVATE
  -Wno-pedantic
  -Wno-error=pedantic
)

target_include_directories(${PROJECT_NAME}_component
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>)

# PCL dependencies - `ament_target_dependencies` doesn't respect the
# components/modules selected above and only links in `common` ,so we need
# to do this manually.
target_compile_definitions(${PROJECT_NAME}_component PRIVATE ${PCL_DEFINITIONS})
target_include_directories(${PROJECT_NAME}_component PRIVATE ${PCL_INCLUDE_DIRS})
# Unfortunately, this one can't be PRIVATE because only the plain or only the
# keyword (PRIVATE) signature of target_link_libraries can be used for one
# target, not both. The plain signature is already used inside
# `ament_target_dependencies` and possibly rosidl_target_interfaces.
target_link_libraries(${PROJECT_NAME}_component ${PCL_LIBRARIES})
target_link_directories(${PROJECT_NAME}_component PRIVATE ${PCL_LIBRARY_DIRS})

rclcpp_components_register_node(${PROJECT_NAME}_component
  PLUGIN "autoware::dummy_perception_publisher::DummyPerceptionPublisherNode"
  EXECUTABLE ${PROJECT_NAME}_node
)

ament_auto_add_library(empty_objects_publisher_component SHARED
  src/empty_objects_publisher.cpp
)

target_link_libraries(empty_objects_publisher_component
  rclcpp::rclcpp
  tracetools::tracetools
)

# PCL uses anonymous structs/unions; silence pedantic Werror for this target
target_compile_options(empty_objects_publisher_component PRIVATE
  -Wno-pedantic
  -Wno-error=pedantic
)

rclcpp_components_register_node(empty_objects_publisher_component
  PLUGIN "autoware::dummy_perception_publisher::EmptyObjectsPublisher"
  EXECUTABLE empty_objects_publisher
)

if(BUILD_TESTING)
  ament_add_ros_isolated_gtest(signed_distance_function-test
    test/src/test_signed_distance_function.cpp
  )
  target_link_libraries(signed_distance_function-test
    signed_distance_function
  )
endif()

ament_auto_package(
  INSTALL_TO_SHARE
  config
  launch
  schema
)