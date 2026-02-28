#!/bin/bash
set -e
set +x  # Disable verbose mode (set -x) to avoid excessive output

# Build script for Autoware with CARET support
# Usage: build_autoware.sh <SCRIPT_DIR> [rebuild_flag] [packages_to_build]
#   SCRIPT_DIR: Base directory of the installation
#   rebuild_flag: Optional, set to 1 to force rebuild
#   packages_to_build: Optional, space-separated list of packages to build (uses --packages-select)

SCRIPT_DIR="$1"
REBUILD_FLAG="${2:-0}"
PACKAGES_TO_BUILD="${3:-}"
export SCRIPT_DIR="${SCRIPT_DIR}"

if [ -z "$SCRIPT_DIR" ]; then
  echo "Error: SCRIPT_DIR argument is required"
  exit 1
fi


# Fix for CARET linking issue: https://github.com/tier4/caret/issues/69
# This ensures ament_cmake_auto uses SYSTEM dependencies, which makes CMake prefer
# CARET's instrumented libraries (from CMAKE_PREFIX_PATH) over system ROS 2 libraries.
# The fix changes:
#   ament_target_dependencies(${target}  ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})
# to:
#   ament_target_dependencies(${target} SYSTEM ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})
apply_caret_ament_cmake_auto_fix() {
  local ament_exec_file="/opt/ros/humble/share/ament_cmake_auto/cmake/ament_auto_add_executable.cmake"
  local ament_lib_file="/opt/ros/humble/share/ament_cmake_auto/cmake/ament_auto_add_library.cmake"
  local fix_applied=0
  
  # Check and fix ament_auto_add_executable.cmake
  if [ -f "${ament_exec_file}" ]; then
    # Check if fix is already applied (line contains SYSTEM keyword)
    if grep -q "ament_target_dependencies(\${target} SYSTEM" "${ament_exec_file}"; then
      echo "✓ CARET fix already applied to ${ament_exec_file}"
    else
      echo "Applying CARET fix to ${ament_exec_file}..."
      # Backup original file
      sudo cp "${ament_exec_file}" "${ament_exec_file}.backup"
      # Apply fix: add SYSTEM keyword before ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS}
      # Match pattern with two spaces (original) or one space (some variants)
      sudo sed -i 's/ament_target_dependencies(${target}  ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})/ament_target_dependencies(${target} SYSTEM ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})/g' "${ament_exec_file}"
      sudo sed -i 's/ament_target_dependencies(${target} ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})/ament_target_dependencies(${target} SYSTEM ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})/g' "${ament_exec_file}"
      # Verify the fix was applied
      if grep -q "ament_target_dependencies(\${target} SYSTEM" "${ament_exec_file}"; then
        echo "✓ Fix successfully applied to ${ament_exec_file}"
        fix_applied=1
      else
        echo "⚠ Warning: Fix may not have been applied correctly to ${ament_exec_file}"
      fi
    fi
  else
    echo "⚠ Warning: ${ament_exec_file} not found. Skipping fix."
  fi
  
  # Check and fix ament_auto_add_library.cmake
  if [ -f "${ament_lib_file}" ]; then
    # Check if fix is already applied (line contains SYSTEM keyword)
    if grep -q "ament_target_dependencies(\${target} SYSTEM" "${ament_lib_file}"; then
      echo "✓ CARET fix already applied to ${ament_lib_file}"
    else
      echo "Applying CARET fix to ${ament_lib_file}..."
      # Backup original file
      sudo cp "${ament_lib_file}" "${ament_lib_file}.backup"
      # Apply fix: add SYSTEM keyword before ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS}
      # Match pattern with two spaces (original) or one space (some variants)
      sudo sed -i 's/ament_target_dependencies(${target}  ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})/ament_target_dependencies(${target} SYSTEM ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})/g' "${ament_lib_file}"
      sudo sed -i 's/ament_target_dependencies(${target} ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})/ament_target_dependencies(${target} SYSTEM ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})/g' "${ament_lib_file}"
      # Verify the fix was applied
      if grep -q "ament_target_dependencies(\${target} SYSTEM" "${ament_lib_file}"; then
        echo "✓ Fix successfully applied to ${ament_lib_file}"
        fix_applied=1
      else
        echo "⚠ Warning: Fix may not have been applied correctly to ${ament_lib_file}"
      fi
    fi
  else
    echo "⚠ Warning: ${ament_lib_file} not found. Skipping fix."
  fi
  
  if [ $fix_applied -eq 1 ]; then
    echo "✓ CARET ament_cmake_auto fix applied successfully"
  fi
}

# Reverse fix for CARET linking issue: Remove SYSTEM keyword from ament_cmake_auto
# This restores the original behavior where dependencies are not marked as SYSTEM.
# The fix changes:
#   ament_target_dependencies(${target} SYSTEM ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})
# back to:
#   ament_target_dependencies(${target} ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})
remove_caret_ament_cmake_auto_fix() {
  local ament_exec_file="/opt/ros/humble/share/ament_cmake_auto/cmake/ament_auto_add_executable.cmake"
  local ament_lib_file="/opt/ros/humble/share/ament_cmake_auto/cmake/ament_auto_add_library.cmake"
  local fix_applied=0
  
  # Check and fix ament_auto_add_executable.cmake
  if [ -f "${ament_exec_file}" ]; then
    # Check if SYSTEM keyword is present (fix is applied)
    if grep -q "ament_target_dependencies(\${target} SYSTEM" "${ament_exec_file}"; then
      echo "Removing SYSTEM keyword from ${ament_exec_file}..."
      # Backup original file
      sudo cp "${ament_exec_file}" "${ament_exec_file}.backup"
      # Apply fix: remove SYSTEM keyword before ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS}
      # Match pattern with SYSTEM keyword (with one or two spaces after target)
      sudo sed -i 's/ament_target_dependencies(${target} SYSTEM ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})/ament_target_dependencies(${target} ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})/g' "${ament_exec_file}"
      # Verify the fix was applied
      if ! grep -q "ament_target_dependencies(\${target} SYSTEM" "${ament_exec_file}"; then
        echo "✓ SYSTEM keyword successfully removed from ${ament_exec_file}"
        fix_applied=1
      else
        echo "⚠ Warning: SYSTEM keyword may not have been removed correctly from ${ament_exec_file}"
      fi
    else
      echo "✓ No SYSTEM keyword found in ${ament_exec_file} (already removed or never applied)"
    fi
  else
    echo "⚠ Warning: ${ament_exec_file} not found. Skipping fix."
  fi
  
  # Check and fix ament_auto_add_library.cmake
  if [ -f "${ament_lib_file}" ]; then
    # Check if SYSTEM keyword is present (fix is applied)
    if grep -q "ament_target_dependencies(\${target} SYSTEM" "${ament_lib_file}"; then
      echo "Removing SYSTEM keyword from ${ament_lib_file}..."
      # Backup original file
      sudo cp "${ament_lib_file}" "${ament_lib_file}.backup"
      # Apply fix: remove SYSTEM keyword before ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS}
      # Match pattern with SYSTEM keyword (with one or two spaces after target)
      sudo sed -i 's/ament_target_dependencies(${target} SYSTEM ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})/ament_target_dependencies(${target} ${${PROJECT_NAME}_FOUND_BUILD_DEPENDS})/g' "${ament_lib_file}"
      # Verify the fix was applied
      if ! grep -q "ament_target_dependencies(\${target} SYSTEM" "${ament_lib_file}"; then
        echo "✓ SYSTEM keyword successfully removed from ${ament_lib_file}"
        fix_applied=1
      else
        echo "⚠ Warning: SYSTEM keyword may not have been removed correctly from ${ament_lib_file}"
      fi
    else
      echo "✓ No SYSTEM keyword found in ${ament_lib_file} (already removed or never applied)"
    fi
  else
    echo "⚠ Warning: ${ament_lib_file} not found. Skipping fix."
  fi
  
  if [ $fix_applied -eq 1 ]; then
    echo "✓ SYSTEM keyword removed from ament_cmake_auto files successfully"
  fi
}

source_autoware_build_env() {
  # shellcheck disable=SC1091
  source /opt/ros/humble/setup.bash
  #source "${SCRIPT_DIR}/ros2_tracing/install/setup.bash"
  echo $CMAKE_PREFIX_PATH
  source "${SCRIPT_DIR}/ros2_caret_ws/install/local_setup.bash"
  echo $SCRIPT_DIR
  echo $CMAKE_PREFIX_PATH
  
}

# Function to detect failed packages from colcon build output
detect_failed_packages() {
	local log_file="$1"
	local failed_file="$2"
	
	# Extract the summary section from the log starting from "Summary:" line
	# This ensures we get the complete summary even if the log is very long
	local summary_section=""
	if grep -q "^Summary:" "$log_file" 2>/dev/null; then
		# Extract everything from the first "Summary:" line to the end of the file
		summary_section=$(sed -n '/^Summary:/,$p' "$log_file" 2>/dev/null || echo "")
		echo "Found Summary: in log file"
	elif grep -q "Summary:" "$log_file" 2>/dev/null; then
		# Fallback: extract from any line containing "Summary:" to the end
		summary_section=$(sed -n '/Summary:/,$p' "$log_file" 2>/dev/null || echo "")
		echo "Found summary with fallback method"
	else
		# Last resort: use last 100 lines if no "Summary:" found
		summary_section=$(tail -100 "$log_file" 2>/dev/null || echo "")
		echo "Summary not found, taking last 100 lines"
	fi
	
	# Extract failed packages from colcon summary
	# Colcon summary format: "  X packages failed: package1 package2 package3"
	# First try the summary format
	if echo "$summary_section" | grep -q "packages failed:"; then
		# Extract the line with "packages failed:" and get all package names after the colon
		echo "$summary_section" | grep "packages failed:" | \
			sed 's/.*packages failed: *//' | \
			tr ' ' '\n' | \
			grep -v '^$' | \
			sort -u > "$failed_file" || true
	fi
	
	# Also check for "Failed   <<<" format (individual package failures during build)
	if [ -s "$failed_file" ]; then
		# Merge with any "Failed <<<" entries
		grep -E "Failed[[:space:]]+<<<" "$log_file" 2>/dev/null | \
			sed 's/.*Failed[[:space:]]\+<<< \([^ ]*\).*/\1/' | \
			sort -u >> "$failed_file" || true
	else
		# If summary didn't work, try "Failed <<<" format
		grep -E "Failed[[:space:]]+<<<" "$log_file" 2>/dev/null | \
			sed 's/.*Failed[[:space:]]\+<<< \([^ ]*\).*/\1/' | \
			sort -u > "$failed_file" || true
	fi
	
	# Also check colcon's result files if available (as backup)
	if [ -d "log/latest_build" ]; then
		find log/latest_build -name "stderr" -exec grep -l "error\|Error\|ERROR\|failed\|Failed" {} \; 2>/dev/null | \
		while read -r stderr_file; do
			# Extract package name from path: log/latest_build/package_name/stderr
			package_name=$(basename "$(dirname "$stderr_file")")
			echo "$package_name" >> "$failed_file"
		done
	fi
	
	# Remove duplicates and empty lines
	sort -u "$failed_file" -o "$failed_file" 2>/dev/null || true
	sed -i '/^$/d' "$failed_file" 2>/dev/null || true
	
	# Count failed packages
	local failed_count=0
	if [ -f "$failed_file" ]; then
		failed_count=$(wc -l < "$failed_file" 2>/dev/null | tr -d ' ' || echo "0")
	fi
	
	if [ "$failed_count" -gt 0 ]; then
		echo "Detected $failed_count failed package(s)"
		return 0
	else
		echo "No failed packages detected"
		return 1
	fi
}

# Function to build with error handling and retry
build_with_retry() {
	local initial_packages="${1:-}"  # Optional: space-separated list of packages to build
	local build_log="${SCRIPT_DIR}/autoware_build.log"
	local failed_packages_file="${SCRIPT_DIR}/failed_packages.txt"
	local max_retries=1  # Only one retry with same environment, then special retry without system libtracetools.so
	local retry_count=0
	
	# Build colcon arguments based on whether packages are specified
	local colcon_packages_args=""
	if [ -n "$initial_packages" ]; then
		colcon_packages_args="--packages-select $initial_packages"
		echo "=========================================="
		echo "Building selected packages with CARET: $initial_packages"
		echo "=========================================="
	else
		echo "=========================================="
		echo "Building Autoware with CARET (continuing on errors)..."
		echo "=========================================="
	fi
	
	# build_autoware_addition.sh
	# Jetson Orin AGX = sm_87; overrides packages that default to unsupported compute_101
	CMAKE_ARGS="-DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DCMAKE_CUDA_ARCHITECTURES=87"
	if [ "${CARET_VERBOSE_LINK:-0}" = "1" ]; then
		CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_VERBOSE_MAKEFILE=ON"
		echo "Verbose link logging enabled (CARET_VERBOSE_LINK=1)"
	fi

	# Log the exact CMake arguments used for the build into the same env log file
	{
		echo "=== CMake Arguments (initial build) ==="
		echo "CMAKE_ARGS=${CMAKE_ARGS}"
		if [ -n "$initial_packages" ]; then
			echo "Packages: $initial_packages"
		fi
		echo "======================================="
	} | tee -a "${SCRIPT_DIR}/installation_env"
	
	colcon build --symlink-install --cmake-clean-cache \
	  ${colcon_packages_args} \
	  --cmake-args ${CMAKE_ARGS} \
	  --continue-on-error 2>&1 | tee "$build_log"
	
	local build_exit_code=${PIPESTATUS[0]}
	
	# Detect failed packages
	rm -f "$failed_packages_file"
	detect_failed_packages "$build_log" "$failed_packages_file"
	
	if [ ! -s "$failed_packages_file" ]; then
		echo "✓ All packages built successfully!"
		return 0
	fi
	
	echo ""
	echo "=========================================="
	echo "Failed packages detected. Writing to: $failed_packages_file"
	echo "=========================================="
	cat "$failed_packages_file"
	echo ""
	exit 0


}

# -------------------- Colcon Build ------------------------
cd "${SCRIPT_DIR}/autoware"
echo "########################################################"
echo "CMAKE_PREFIX_PATH: $CMAKE_PREFIX_PATH"
export CMAKE_PREFIX_PATH="/home/tristan-toye/.local:$CMAKE_PREFIX_PATH"
echo "########################################################"
echo "CMAKE_PREFIX_PATH: $CMAKE_PREFIX_PATH"
echo "########################################################"

# CRITICAL: Apply CARET ament_cmake_auto fix before building
# This ensures CMake prefers CARET's instrumented libraries over system ROS 2 libraries
# See: https://github.com/tier4/caret/issues/69
# apply_caret_ament_cmake_auto_fix
remove_caret_ament_cmake_auto_fix

# Copy autoware_dummy_perception_publisher folder to replace existing one
# This ensures the modified component-based version is used during build
# Source directory can be set via AUTOWARE_DUMMY_PUBLISHER_SOURCE env variable
# If not set, uses the current location (assumes modifications are already in place)
copy_autoware_dummy_perception_publisher() {
	local source_dir="${SCRIPT_DIR}/autoware_dummy_perception_publisher"
	local target_dir="${SCRIPT_DIR}/autoware/src/universe/autoware_universe/simulator/autoware_dummy_perception_publisher"
	
	
	# Copy from source to target
	if [ -d "$source_dir" ]; then
		echo "Copying autoware_dummy_perception_publisher to target location..."
		# Remove existing target if it exists
		if [ -d "$target_dir" ]; then
			echo "  Removing existing folder: $target_dir"
			rm -rf "$target_dir"
		fi
		# Copy the folder
		echo "  Copying from: $source_dir"
		echo "  To: $target_dir"
		cp -r "$source_dir" "$target_dir"
		echo "✓ autoware_dummy_perception_publisher folder copied successfully"
	else
		echo "⚠ Warning: Source directory not found: $source_dir"
		echo "  Skipping copy operation"
	fi
}

# Fix PCL pedantic warnings in autoware_dummy_perception_publisher CMakeLists.txt
# This adds the necessary compile options to suppress PCL's anonymous struct warnings
apply_pcl_pedantic_fix() {
	local cmake_file="${SCRIPT_DIR}/autoware/src/universe/autoware_universe/simulator/autoware_dummy_perception_publisher/CMakeLists.txt"
	
	if [ ! -f "$cmake_file" ]; then
		echo "⚠ Warning: CMakeLists.txt not found: $cmake_file"
		return
	fi
	
	# Check if fix is already applied
	if grep -q "PCL uses anonymous structs/unions; silence pedantic Werror" "$cmake_file"; then
		echo "✓ PCL pedantic fix already applied to autoware_dummy_perception_publisher CMakeLists.txt"
		return
	fi
	
	echo "Applying PCL pedantic fix to autoware_dummy_perception_publisher CMakeLists.txt..."
	
	# Create a backup
	cp "$cmake_file" "${cmake_file}.bak"
	
	# Find the line with the closing parenthesis of target_include_directories
	# Pattern: $<INSTALL_INTERFACE:include>)
	local insert_after_line=$(grep -n '\$<INSTALL_INTERFACE:include>)' "$cmake_file" | head -1 | cut -d: -f1)
	
	if [ -z "$insert_after_line" ]; then
		echo "⚠ Warning: Could not find insertion point in CMakeLists.txt"
		mv "${cmake_file}.bak" "$cmake_file"
		return
	fi
	
	# Use awk to insert the fix after the target_include_directories block
	awk -v line="$insert_after_line" '
		NR == line {
			print
			print ""
			print "# PCL uses anonymous structs/unions; silence pedantic Werror for this target"
			print "target_compile_options(${PROJECT_NAME}_node PRIVATE"
			print "  -Wno-pedantic"
			print "  -Wno-error=pedantic"
			print ")"
			next
		}
		{print}
	' "$cmake_file" > "${cmake_file}.tmp" && mv "${cmake_file}.tmp" "$cmake_file"
	
	# Verify the fix was applied
	if grep -q "PCL uses anonymous structs/unions; silence pedantic Werror" "$cmake_file"; then
		echo "✓ PCL pedantic fix successfully applied to autoware_dummy_perception_publisher CMakeLists.txt"
		rm -f "${cmake_file}.bak"
	else
		echo "⚠ Warning: Fix may not have been applied correctly. Restoring backup..."
		mv "${cmake_file}.bak" "$cmake_file"
	fi
}

# Jetson Orin (sm_87) does not support compute_101/110/120; packages that hardcode these
# in CUDA_NVCC_FLAGS override CMAKE_CUDA_ARCHITECTURES. Comment out those lines so only
# sm_86/87/89 are used.
apply_jetson_cuda_arch_fix() {
	local src_dir="${SCRIPT_DIR}/autoware/src"
	local count=0
	while IFS= read -r -d '' f; do
		if grep -q 'compute_101\|compute_110\|compute_120' "$f" 2>/dev/null; then
			sed -i '/list(APPEND CUDA_NVCC_FLAGS.*compute_101/s/^/# Jetson: /' "$f"
			sed -i '/list(APPEND CUDA_NVCC_FLAGS.*compute_110/s/^/# Jetson: /' "$f"
			sed -i '/list(APPEND CUDA_NVCC_FLAGS.*compute_120/s/^/# Jetson: /' "$f"
			count=$((count + 1))
		fi
	done < <(find "$src_dir" -name "CMakeLists.txt" -print0 2>/dev/null)
	if [ "$count" -gt 0 ]; then
		echo "✓ Jetson CUDA arch fix applied to $count CMakeLists.txt (commented compute_101/110/120)"
	fi
}

# Apply PCL pedantic fix
apply_pcl_pedantic_fix
# Apply Jetson CUDA arch fix so nvcc does not see unsupported compute_101
apply_jetson_cuda_arch_fix

# https://tier4.github.io/caret_doc/main/faq/known_issues/#build
# sudo cp /opt/ros/humble/share/pcl_ros/cmake/export_pcl_rosExport.cmake /opt/ros/humble/share/pcl_ros/cmake/export_pcl_rosExport.cmake.bak
#sudo sed -i -e 's/\/opt\/ros\/humble\/lib\/libtracetools.so;//g' /opt/ros/humble/share/pcl_ros/cmake/export_pcl_rosExport.cmake
# Clean any Autoware overlay from the current shell environment so that CMake
# sees a clean base (opt/ros + ros2_humble + CARET) instead of resolving
# rclcpp / friends from a previously sourced autoware/install.
# This is CRITICAL when building with --packages-up-to, because dependencies
# are built first and must use CARET's rclcpp, not a previously built autoware rclcpp.
#clean_env_for_autoware_build

# Reset CMAKE_PREFIX_PATH to just .local (from bashrc), then source in same order as working script
# This ensures a clean environment that matches test_autoware_dummy_perception_publisher.sh
# export CMAKE_PREFIX_PATH="$HOME/.local"

# copy_autoware_dummy_perception_publisher

source_autoware_build_env

# CRITICAL: Reorder CMAKE_PREFIX_PATH and AMENT_PREFIX_PATH so CARET is FIRST.
# This prevents CMake from resolving rclcpp/tracetools from /opt/ros/humble.

# CARET_INSTALL="${SCRIPT_DIR}/ros2_caret_ws/install"
# prepend_prefix_path() {
# 	local var_name="$1"
# 	local prefix="$2"
# 	local current="${!var_name-}"
# 	if [ -z "$current" ]; then
# 		export "$var_name=$prefix"
# 		return
# 	fi
# 	current=$(echo "$current" | tr ':' '\n' | grep -vF "$prefix" | paste -sd: -)
# 	export "$var_name=$prefix:$current"
# }
# if [ -d "${CARET_INSTALL}" ]; then
# 	prepend_prefix_path "CMAKE_PREFIX_PATH" "${CARET_INSTALL}"
# 	prepend_prefix_path "AMENT_PREFIX_PATH" "${CARET_INSTALL}"
# fi

# after: source /opt/ros/humble/setup.bash
export CUDAToolkit_ROOT=/usr/local/cuda
export spconv_DIR="$HOME/.local/lib/cmake/spconv"
export cumm_DIR="$HOME/.local/share/cmake/cumm"   # or .../lib/cmake/cumm if that's where yours installed


if ! ros2 run tracetools status | grep -q "Tracing enabled"; then
	  echo "[ERROR] ROS 2 tracing is not enabled. Re-check LTTng install and the overlay build." >&2
	  exit 1
fi

# CRITICAL: Ensure CARET's tracetools library is found at LINK TIME, not the system version
# The system /opt/ros/humble/lib/libtracetools.so exists but doesn't have CARET's symbols.
# We MUST ensure CARET's version is found FIRST by the linker.
# 
# LIBRARY_PATH: Used by GCC/ld at LINK TIME to find libraries (MOST IMPORTANT for this fix)
# LD_LIBRARY_PATH: Used by dynamic linker at RUNTIME to find libraries
# CMAKE_LIBRARY_PATH: Used by CMake's find_library() to search for libraries
#
# Order matters: CARET's paths MUST come BEFORE any system paths to avoid linking
# against the system's libtracetools.so which lacks CARET-specific symbols.
# export LIBRARY_PATH="${SCRIPT_DIR}/ros2_caret_ws/install/lib${LIBRARY_PATH:+:${LIBRARY_PATH}}"
#export LD_LIBRARY_PATH="${SCRIPT_DIR}/ros2_caret_ws/install/lib:${LD_LIBRARY_PATH}"
#export CMAKE_LIBRARY_PATH="${SCRIPT_DIR}/ros2_caret_ws/install/lib${CMAKE_LIBRARY_PATH:+:${CMAKE_LIBRARY_PATH}}"
# export LDFLAGS="-L${SCRIPT_DIR}/ros2_caret_ws/install/lib"
#export LD_PRELOAD="${SCRIPT_DIR}/ros2_caret_ws/install/lib/libcaret.so"

# Explicitly set tracetools_DIR to force CMake to use CARET's tracetools
# This ensures find_package(tracetools) finds the CARET version even if CMAKE_PREFIX_PATH order fails
if [ -f "${SCRIPT_DIR}/ros2_caret_ws/install/share/tracetools/cmake/tracetoolsConfig.cmake" ]; then
	export tracetools_DIR="${SCRIPT_DIR}/ros2_caret_ws/install/share/tracetools/cmake"
	:
fi

# Explicitly set rclcpp_DIR and rclcpp_components_DIR to force CARET's rclcpp
# This prevents CMake from resolving system /opt/ros/humble rclcpp first.
if [ -f "${SCRIPT_DIR}/ros2_caret_ws/install/share/rclcpp/cmake/rclcppConfig.cmake" ]; then
	export rclcpp_DIR="${SCRIPT_DIR}/ros2_caret_ws/install/share/rclcpp/cmake"
	:
fi
if [ -f "${SCRIPT_DIR}/ros2_caret_ws/install/share/rclcpp_components/cmake/rclcpp_componentsConfig.cmake" ]; then
	export rclcpp_components_DIR="${SCRIPT_DIR}/ros2_caret_ws/install/share/rclcpp_components/cmake"
	:
fi

# Debug: show environment before build and write to file
{
	echo "=== Build Environment ==="
	echo "CMAKE_PREFIX_PATH=$CMAKE_PREFIX_PATH"
	echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
	echo "LIBRARY_PATH=$LIBRARY_PATH"
	echo "CMAKE_LIBRARY_PATH=$CMAKE_LIBRARY_PATH"
	echo "LDFLAGS=$LDFLAGS"
	echo "LD_PRELOAD=$LD_PRELOAD"
	echo "tracetools_DIR=$tracetools_DIR"
	echo "rclcpp_DIR=$rclcpp_DIR"
	echo "rclcpp_components_DIR=$rclcpp_components_DIR"
	echo "spconv_DIR=$spconv_DIR"
	echo "cumm_DIR=$cumm_DIR"
	echo "========================="
} | tee "${SCRIPT_DIR}/installation_env"

# Execute build based on rebuild flag
if [ "$REBUILD_FLAG" = "1" ]; then
	echo "Cleaning build and install directories..."
	rm -rf build install log
	rm -f "${SCRIPT_DIR}/.autoware_build_flag"
	rm -f "${SCRIPT_DIR}/failed_packages.txt"
	rm -f "${SCRIPT_DIR}/autoware_build.log"
	echo "✓ Cleaned build directories"
	build_with_retry 
	touch "${SCRIPT_DIR}/.autoware_build_flag"
elif [ ! -f "${SCRIPT_DIR}/.autoware_build_flag" ]; then
	# Build if flag doesn't exist (first time build)
	build_with_retry 
	touch "${SCRIPT_DIR}/.autoware_build_flag"
elif [ -n "$PACKAGES_TO_BUILD" ]; then
	# If packages are specified, build them even if build flag exists
	echo "Building specified packages: $PACKAGES_TO_BUILD"
	build_with_retry "$PACKAGES_TO_BUILD"
else
	echo "#########################################"
	echo "#########################################"
	echo "Autoware colcon build already ran. Skipping build."
	echo "Use -b flag to force rebuild."
	echo "Use -r flag to rebuild failed packages from unable_to_build.txt"
	echo "#########################################"
	echo "#########################################"
fi

