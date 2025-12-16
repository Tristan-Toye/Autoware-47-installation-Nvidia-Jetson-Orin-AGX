#!/bin/bash
set +e  # Don't exit on error, we want to process all packages

# Script to check which Autoware packages have <depend>rclcpp</depend> in their package.xml
# Usage: ./check_package_dependencies.sh

export SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
AUTOWARE_DIR="${SCRIPT_DIR}/autoware"

# List of packages from CARET warning
PACKAGES=(
	autoware_stop_mode_operator
	autoware_trajectory_modifier
	autoware_object_velocity_splitter
	autoware_iv_internal_api_adaptor
	autoware_cluster_merger
	autoware_raindrop_cluster_filter
	autoware_calibration_status_classifier
	reaction_analyzer
	pointcloud_to_laserscan
	autoware_tensorrt_bevformer
	autoware_hazard_lights_selector
	autoware_detected_object_validation
	autoware_command_mode_switcher_plugins
	autoware_shape_estimation
	autoware_image_transport_decompressor
	autoware_radar_fusion_to_detected_object
	eagleye_gnss_converter
	autoware_map_height_fitter
	autoware_trajectory_traffic_rule_filter
	autoware_radar_object_tracker
	autoware_mission_planner_universe
	autoware_motion_velocity_boundary_departure_prevention_module
	autoware_trajectory_adapter
	autoware_steer_offset_estimator
	autoware_perception_online_evaluator
	autoware_lanelet2_map_visualizer
	autoware_planning_topic_converter
	autoware_pose2twist
	autoware_costmap_generator
	autoware_elevation_map_loader
	autoware_gnss_poser
	tier4_perception_rviz_plugin
	autoware_behavior_velocity_virtual_traffic_light_module
	autoware_tensorrt_bevdet
	autoware_default_adapi_universe
	pacmod_interface
	autoware_diagnostic_graph_utils
	boost_udp_driver
	autoware_localization_evaluator
	yabloc_image_processing
	autoware_object_merger
	autoware_raw_vehicle_cmd_converter
	autoware_euclidean_cluster
	autoware_traffic_light_selector
	autoware_simple_object_merger
	yabloc_monitor
	autoware_motion_velocity_planner
	autoware_pose_estimator_arbiter
	autoware_pose_initializer
	autoware_occupancy_grid_map_outlier_filter
	autoware_command_mode_decider
	autoware_planning_evaluator
	autoware_planning_validator
	tier4_planning_factor_rviz_plugin
	agnocast_e2e_test
	autoware_behavior_path_planner
	autoware_joy_controller
	autoware_collision_detector
	autoware_localization_rviz_plugin
	tier4_control_mode_rviz_plugin
	autoware_radar_objects_adapter
	autoware_radar_threshold_filter
	autoware_traffic_light_arbiter
	autoware_path_sampler
	autoware_control_performance_analysis
	autoware_trajectory_concatenator
	autoware_twist2accel
	autoware_bevfusion
	autoware_vehicle_cmd_gate
	tier4_adapi_rviz_plugin
	yabloc_pose_initializer
	awapi_awiv_adapter
	autoware_perception_rviz_plugin
	autoware_default_adapi
	autoware_control_command_gate
	autoware_radar_static_pointcloud_filter
	autoware_path_generator
	autoware_path_smoother
	autoware_external_velocity_limit_selector
	autoware_remaining_distance_time_calculator
	autoware_traffic_light_occlusion_predictor
	autoware_radar_scan_to_pointcloud2
	tier4_deprecated_api_adapter
	autoware_mission_planner
	negotiated_examples
	agnocast_sample_application
	autoware_scenario_simulator_v2_adapter
	autoware_traffic_light_map_based_detector
	autoware_control_evaluator
	autoware_traffic_light_category_merger
	autoware_fault_injection
	tamagawa_imu_driver
	yabloc_common
	autoware_mrm_handler
	autoware_mrm_emergency_stop_operator
	autoware_overlay_rviz_plugin
	autoware_ground_segmentation
	nebula_ros
	autoware_fake_test_node
	autoware_control_validator
	autoware_crosswalk_traffic_light_estimator
	autoware_velocity_smoother
	autoware_obstacle_collision_checker
	autoware_dummy_perception_publisher
	autoware_bytetrack
	autoware_imu_corrector
	autoware_trajectory_ranker
	autoware_planning_rviz_plugin
	autoware_ndt_scan_matcher
	autoware_image_object_locator
	autoware_path_distance_calculator
	autoware_surround_obstacle_checker
	managed_transform_buffer
	autoware_external_cmd_converter
	autoware_processing_time_checker
	autoware_lidar_marker_localizer
	autoware_component_state_monitor
	autoware_predicted_path_checker
	autoware_image_diagnostics
	autoware_tracking_object_merger
	autoware_test_utils
	autoware_multi_object_tracker
	autoware_string_stamped_rviz_plugin
	autoware_radar_tracks_msgs_converter
	autoware_adapi_adaptors
	autoware_crop_box_filter
	autoware_map_loader
	autoware_component_interface_tools
	boost_serial_driver
	autoware_traffic_light_rviz_plugin
	autoware_trajectory_follower_node
	autoware_traffic_light_recognition_marker_publisher
	autoware_detection_by_tracker
	autoware_radar_tracks_noise_filter
	autoware_dummy_infrastructure
	autoware_lidar_frnet
	autoware_camera_streampetr
	autoware_perception_objects_converter
	autoware_autonomous_emergency_braking
	autoware_traffic_light_visualization
	autoware_map_tf_generator
	eagleye_geo_pose_fusion
	autoware_lane_departure_checker
	eagleye_rt
	negotiated
	autoware_gyro_odometer
	cuda_blackboard
	autoware_object_sorter
	autoware_object_range_splitter
	autoware_command_mode_switcher
	autoware_motion_utils
	autoware_operation_mode_transition_manager
	autoware_vehicle_velocity_converter
	autoware_stop_filter
	autoware_iv_external_api_adaptor
	autoware_mission_details_overlay_rviz_plugin
	autoware_traffic_light_classifier
	tier4_state_rviz_plugin
	autoware_traffic_light_multi_camera_fusion
	autoware_topic_state_monitor
	autoware_scenario_selector
	autoware_ar_tag_based_localizer
	autoware_diffusion_planner
	autoware_lidar_apollo_instance_segmentation
	ros2_socketcan
	autoware_automatic_pose_initializer
	autoware_cuda_pointcloud_preprocessor
	autoware_hazard_status_converter
	autoware_geo_pose_projector
	tier4_autoware_api_extension
	yabloc_particle_filter
	autoware_probabilistic_occupancy_grid_map
	autoware_localization_error_monitor
	autoware_ground_filter
	autoware_goal_distance_calculator
	autoware_trajectory_optimizer
	tier4_traffic_light_rviz_plugin
	autoware_path_optimizer
	autoware_compare_map_segmentation
	tier4_vehicle_rviz_plugin
	autoware_simple_pure_pursuit
	autoware_image_projection_based_fusion
	eagleye_fix2kml
	autoware_kinematic_evaluator
	autoware_external_cmd_selector
	autoware_accel_brake_map_calibrator
	autoware_pose_instability_detector
	autoware_livox_tag_filter
	autoware_trajectory_safety_filter
	autoware_traffic_light_fine_detector
	autoware_downsample_filters
	autoware_pose_covariance_modifier
	autoware_simpl_prediction
	autoware_behavior_velocity_planner
	autoware_simple_planning_simulator
	autoware_manual_lane_change_handler
	autoware_predicted_path_postprocessor
	autoware_pointcloud_preprocessor
	autoware_topic_relay_controller
	autoware_ekf_localizer
	autoware_euclidean_cluster_object_detector
	eagleye_can_velocity_converter
	autoware_shift_decider
	autoware_map_based_prediction
	autoware_freespace_planner
	autoware_detected_object_feature_remover
	autoware_motion_velocity_obstacle_cruise_module
	autoware_diagnostic_graph_aggregator
	eagleye_geo_pose_converter
)

# Arrays to store results
COMPLIANT_PACKAGES=()
NON_COMPLIANT_PACKAGES=()
NOT_FOUND_PACKAGES=()

# Function to find package.xml for a given package name
find_package_xml() {
	local pkg_name="$1"
	local pkg_xml=""
	
	# Search in src directory (most common location)
	if [ -d "${AUTOWARE_DIR}/src" ]; then
		# Try exact match first (most common case)
		pkg_xml=$(find "${AUTOWARE_DIR}/src" -type f -name "package.xml" -path "*/${pkg_name}/package.xml" 2>/dev/null | head -n1)
		
		if [ -n "$pkg_xml" ]; then
			echo "$pkg_xml"
			return 0
		fi
		
		# Try searching in subdirectories (for packages like autoware_command_mode_switcher_plugins)
		pkg_xml=$(find "${AUTOWARE_DIR}/src" -type f -name "package.xml" -path "*/*${pkg_name}*/package.xml" 2>/dev/null | head -n1)
		
		if [ -n "$pkg_xml" ]; then
			echo "$pkg_xml"
			return 0
		fi
	fi
	
	return 1
}

# Function to check if package.xml contains rclcpp dependency
check_rclcpp_dependency() {
	local pkg_xml="$1"
	
	if [ ! -f "$pkg_xml" ]; then
		return 2  # File not found
	fi
	
	# Check for <depend>rclcpp</depend> with various whitespace patterns
	if grep -qE '<depend[^>]*>rclcpp</depend>' "$pkg_xml" 2>/dev/null; then
		return 0  # Found
	fi
	
	# Also check for whitespace variations
	if grep -qE '<depend[^>]*>\s*rclcpp\s*</depend>' "$pkg_xml" 2>/dev/null; then
		return 0  # Found
	fi
	
	return 1  # Not found
}

echo "=========================================="
echo "Checking packages for rclcpp dependency"
echo "=========================================="
echo "Total packages to check: ${#PACKAGES[@]}"
echo ""

# Pre-index all package.xml files for faster lookup
echo "Indexing package.xml files..."
INDEX_FILE=$(mktemp)
if [ -d "${AUTOWARE_DIR}/src" ]; then
	# Create index: package_name|full_path
	find "${AUTOWARE_DIR}/src" -type f -name "package.xml" 2>/dev/null | while read -r pkg_xml; do
		pkg_name=$(basename "$(dirname "$pkg_xml")")
		echo "${pkg_name}|${pkg_xml}"
	done > "$INDEX_FILE"
fi
INDEX_COUNT=$(wc -l < "$INDEX_FILE" 2>/dev/null || echo "0")
echo "Found $INDEX_COUNT package.xml files"
echo ""

# Process each package
total=${#PACKAGES[@]}
current=0
for pkg in "${PACKAGES[@]}"; do
	((current++))
	if [ $((current % 20)) -eq 0 ]; then
		echo "Progress: $current/$total packages checked..."
	fi
	
	# Try lookup from index file
	pkg_xml=$(grep "^${pkg}|" "$INDEX_FILE" 2>/dev/null | cut -d'|' -f2 | head -n1)
	
	# If not found, try using find (fallback for edge cases)
	if [ -z "$pkg_xml" ] || [ ! -f "$pkg_xml" ]; then
		pkg_xml=$(find_package_xml "$pkg")
	fi
	
	if [ -z "$pkg_xml" ] || [ ! -f "$pkg_xml" ]; then
		NOT_FOUND_PACKAGES+=("$pkg")
		continue
	fi
	
	if check_rclcpp_dependency "$pkg_xml"; then
		COMPLIANT_PACKAGES+=("$pkg|$pkg_xml")
	else
		NON_COMPLIANT_PACKAGES+=("$pkg|$pkg_xml")
	fi
done

# Print results
echo "=========================================="
echo "RESULTS"
echo "=========================================="
echo ""
echo "COMPLIANT PACKAGES (have <depend>rclcpp</depend>): ${#COMPLIANT_PACKAGES[@]}"
echo "---------------------------------------------------"
for entry in "${COMPLIANT_PACKAGES[@]}"; do
	pkg_name="${entry%%|*}"
	pkg_path="${entry#*|}"
	echo "  ✓ $pkg_name"
	echo "    Path: $pkg_path"
done

echo ""
echo "NON-COMPLIANT PACKAGES (missing <depend>rclcpp</depend>): ${#NON_COMPLIANT_PACKAGES[@]}"
echo "---------------------------------------------------"
for entry in "${NON_COMPLIANT_PACKAGES[@]}"; do
	pkg_name="${entry%%|*}"
	pkg_path="${entry#*|}"
	echo "  ✗ $pkg_name"
	echo "    Path: $pkg_path"
done

echo ""
echo "PACKAGES NOT FOUND: ${#NOT_FOUND_PACKAGES[@]}"
echo "---------------------------------------------------"
for pkg in "${NOT_FOUND_PACKAGES[@]}"; do
	echo "  ? $pkg"
done

echo ""
echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo "Total checked: ${#PACKAGES[@]}"
echo "Compliant: ${#COMPLIANT_PACKAGES[@]}"
echo "Non-compliant: ${#NON_COMPLIANT_PACKAGES[@]}"
echo "Not found: ${#NOT_FOUND_PACKAGES[@]}"
echo ""

# Save detailed results to files
RESULTS_DIR="${SCRIPT_DIR}/package_dependency_results"
mkdir -p "$RESULTS_DIR"

echo "Saving detailed results to ${RESULTS_DIR}/..."

# Save compliant packages
{
	echo "# Packages WITH <depend>rclcpp</depend> in package.xml"
	echo "# Total: ${#COMPLIANT_PACKAGES[@]}"
	echo ""
	for entry in "${COMPLIANT_PACKAGES[@]}"; do
		pkg_name="${entry%%|*}"
		pkg_path="${entry#*|}"
		echo "$pkg_name"
		echo "  Path: $pkg_path"
	done
} > "${RESULTS_DIR}/compliant_packages.txt"

# Save non-compliant packages
{
	echo "# Packages MISSING <depend>rclcpp</depend> in package.xml"
	echo "# Total: ${#NON_COMPLIANT_PACKAGES[@]}"
	echo ""
	for entry in "${NON_COMPLIANT_PACKAGES[@]}"; do
		pkg_name="${entry%%|*}"
		pkg_path="${entry#*|}"
		echo "$pkg_name"
		echo "  Path: $pkg_path"
	done
} > "${RESULTS_DIR}/non_compliant_packages.txt"

# Save not found packages
{
	echo "# Packages where package.xml could not be located"
	echo "# Total: ${#NOT_FOUND_PACKAGES[@]}"
	echo ""
	for pkg in "${NOT_FOUND_PACKAGES[@]}"; do
		echo "$pkg"
	done
} > "${RESULTS_DIR}/not_found_packages.txt"

echo "✓ Results saved to:"
echo "  - ${RESULTS_DIR}/compliant_packages.txt"
echo "  - ${RESULTS_DIR}/non_compliant_packages.txt"
echo "  - ${RESULTS_DIR}/not_found_packages.txt"

# Cleanup
rm -f "$INDEX_FILE"
