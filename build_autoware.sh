#!/bin/bash
set -e
set +x  # Disable verbose mode (set -x) to avoid excessive output

# Build script for Autoware with CARET support
# Usage: build_autoware.sh <SCRIPT_DIR> [rebuild_flag]
#   SCRIPT_DIR: Base directory of the installation
#   rebuild_flag: Optional, set to 1 to force rebuild

SCRIPT_DIR="$1"
REBUILD_FLAG="${2:-0}"

if [ -z "$SCRIPT_DIR" ]; then
  echo "Error: SCRIPT_DIR argument is required"
  exit 1
fi

clean_env_for_autoware_build() {
  # Remove any existing Autoware overlay from the current shell environment.
  # This script is often run from a shell that has already sourced
  # ${SCRIPT_DIR}/autoware/install/setup.bash via ~/.bashrc, which pollutes
  # CMAKE_PREFIX_PATH / AMENT_PREFIX_PATH and can cause CMake to resolve
  # the wrong rclcpp (non‑CARET) for some packages.
  local var val
  for var in CMAKE_PREFIX_PATH AMENT_PREFIX_PATH ROS_PACKAGE_PATH LD_LIBRARY_PATH PATH; do
    # shellcheck disable=SC2086
    val=${!var-}
    [ -z "$val" ] && continue
    # Strip any entries under this repo's autoware/install
    val=$(printf '%s\n' "$val" | tr ':' '\n' | grep -v "${SCRIPT_DIR}/autoware/install" | paste -sd: -)
    # shellcheck disable=SC2163
    export "$var=$val"
  done
  # CARET preload should not be active during build
  unset LD_PRELOAD || true
}

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

source_autoware_build_env() {
  # shellcheck disable=SC1091
  source /opt/ros/humble/setup.bash
  source "${SCRIPT_DIR}/ros2_tracing/install/setup.bash"
  
  source "${SCRIPT_DIR}/ros2_caret_ws/install/local_setup.bash"
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
	
	# Also check for "Failed <<<" format (individual package failures during build)
	if [ -s "$failed_file" ]; then
		# Merge with any "Failed <<<" entries
		grep -E "Failed <<<" "$log_file" 2>/dev/null | \
			sed 's/.*Failed <<< \([^ ]*\).*/\1/' | \
			sort -u >> "$failed_file" || true
	else
		# If summary didn't work, try "Failed <<<" format
		grep -E "Failed <<<" "$log_file" 2>/dev/null | \
			sed 's/.*Failed <<< \([^ ]*\).*/\1/' | \
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
	local build_log="${SCRIPT_DIR}/autoware_build.log"
	local failed_packages_file="${SCRIPT_DIR}/failed_packages.txt"
	local max_retries=1  # Only one retry with same environment, then special retry without system libtracetools.so
	local retry_count=0
	
	# Initial build with continue-on-error
	echo "=========================================="
	echo "Building Autoware with CARET (continuing on errors)..."
	echo "=========================================="
	
	# Build with explicit tracetools_DIR to ensure CARET's tracetools is used
	CARET_TRACETOOLS_DIR="${SCRIPT_DIR}/ros2_caret_ws/install/share/tracetools/cmake"
	CARET_LIB_DIR="${SCRIPT_DIR}/ros2_caret_ws/install/lib"
	CARET_INSTALL_DIR="${SCRIPT_DIR}/ros2_caret_ws/install"
	CARET_TRACETOOLS_LIB="${CARET_LIB_DIR}/libtracetools.so"
	
	# Export CARET_TRACETOOLS_DIR for potential use by CMake modules
	export CARET_TRACETOOLS_DIR="${CARET_TRACETOOLS_DIR}"
	
	CMAKE_ARGS="-DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF"
	if [ -f "${CARET_TRACETOOLS_DIR}/tracetoolsConfig.cmake" ] && [ -f "${CARET_TRACETOOLS_LIB}" ]; then
		# CRITICAL: Set tracetools_DIR to force CMake to ONLY use CARET's tracetools
		# This should prevent CMake from finding /opt/ros/humble/lib/libtracetools.so
		CMAKE_ARGS="${CMAKE_ARGS} -Dtracetools_DIR=${CARET_TRACETOOLS_DIR}"
		
		# CRITICAL: Explicitly tell CMake to use CARET's tracetools library file directly
		# This bypasses find_library() and forces the linker to use CARET's version
		# Note: tracetools_LIBRARY may not be recognized by all CMake packages, but it's worth trying
		CMAKE_ARGS="${CMAKE_ARGS} -Dtracetools_LIBRARY=${CARET_TRACETOOLS_LIB}"
		
		# Add CARET's lib directory FIRST in CMAKE_LIBRARY_PATH to ensure linker finds CARET's tracetools FIRST
		if [ -n "${CMAKE_LIBRARY_PATH}" ]; then
			CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_LIBRARY_PATH=${CARET_LIB_DIR}:${CMAKE_LIBRARY_PATH}"
		else
			CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_LIBRARY_PATH=${CARET_LIB_DIR}"
		fi
		
		# CRITICAL: Use CMAKE_FIND_ROOT_PATH to prioritize CARET's install directory
		# This ensures find_package(tracetools) finds CARET's version first
		# BOTH mode allows fallback to system packages if not found in CARET
		CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_FIND_ROOT_PATH=${CARET_INSTALL_DIR}"
		CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH"
		CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH"
		
		# CRITICAL: Remove /opt/ros/humble from CMAKE_PREFIX_PATH temporarily to prevent
		# CMake from finding the system tracetools. We'll add it back after tracetools is found.
		# Actually, this is complex and might break other packages. Instead, we rely on
		# tracetools_DIR being set, which should make CMake use CARET's version.
		
		# Note: We rely on LIBRARY_PATH, LD_LIBRARY_PATH, and CMAKE_LIBRARY_PATH environment variables
		# (set above) to ensure the linker finds CARET's tracetools first.
		# Explicit linker flags cause quoting issues with colcon, so we avoid them here.
		
		echo "Using CARET's tracetools: ${CARET_TRACETOOLS_LIB}"
		echo "tracetools_DIR set to: ${CARET_TRACETOOLS_DIR}"
	else
		if [ ! -f "${CARET_TRACETOOLS_DIR}/tracetoolsConfig.cmake" ]; then
			echo "tracetoolsConfig.cmake not found in ${CARET_TRACETOOLS_DIR}"
		fi
		if [ ! -f "${CARET_TRACETOOLS_LIB}" ]; then
			echo "libtracetools.so not found in ${CARET_LIB_DIR}"
		fi
		return 1
	fi

	# Log the exact CMake arguments used for the build into the same env log file
	{
		echo "=== CMake Arguments (initial build) ==="
		echo "CMAKE_ARGS=${CMAKE_ARGS}"
		echo "======================================="
	} | tee -a "${SCRIPT_DIR}/installation_env"
	
	colcon build --symlink-install --cmake-clean-cache \
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
	
	# Retry failed packages
	while [ $retry_count -lt $max_retries ] && [ -s "$failed_packages_file" ]; do
		retry_count=$((retry_count + 1))
		echo ""
		echo "=========================================="
		echo "Retry attempt $retry_count of $max_retries for failed packages..."
		echo "=========================================="
		
		# Build failed packages
		local packages_to_build=$(tr '\n' ' ' < "$failed_packages_file" | sed 's/ $//')
		echo "Retrying packages: $packages_to_build"

		# Log the CMake arguments for this retry into the env log as well
		{
			echo "=== CMake Arguments (retry $retry_count) ==="
			echo "Packages: $packages_to_build"
			echo "CMAKE_ARGS=${CMAKE_ARGS}"
			echo "==========================================="
		} | tee -a "${SCRIPT_DIR}/installation_env"
		
		# Use same CMAKE_ARGS as initial build (includes tracetools_DIR if available)
		colcon build --packages-select $packages_to_build \
		  --symlink-install \
		  --cmake-clean-cache \
		  --cmake-args ${CMAKE_ARGS} \
		  2>&1 | tee -a "$build_log"
		
		local retry_exit_code=${PIPESTATUS[0]}
		
		# Update failed packages list
		rm -f "$failed_packages_file"
		detect_failed_packages "$build_log" "$failed_packages_file"
		
		if [ ! -s "$failed_packages_file" ]; then
			echo "✓ All packages built successfully after retry!"
			return 0
		fi
		
		echo "Still have $(wc -l < "$failed_packages_file" | tr -d ' ') failed package(s)"
	done
	
	# Special retry: Build with CARET but remove system libtracetools.so so only CARET's version is available
	if [ -s "$failed_packages_file" ]; then
		echo ""
		echo "=========================================="
		echo "Retry with CARET but removing system libtracetools.so..."
		echo "This ensures only CARET's libtracetools.so is available to the linker"
		echo "=========================================="
		
		local system_tracetools="/opt/ros/humble/lib/libtracetools.so"
		local system_tracetools_backup="/opt/ros/humble/lib/libtracetools.so.backup"
		local system_tracetools_removed=0
		
		# Temporarily rename system libtracetools.so to prevent linker from finding it
		if [ -f "$system_tracetools" ]; then
			echo "Temporarily renaming system libtracetools.so to prevent linker conflicts..."
			sudo mv "$system_tracetools" "$system_tracetools_backup"
			system_tracetools_removed=1
		fi
		
		# Build failed packages with CARET (system libtracetools.so is now unavailable)
		local packages_to_build=$(tr '\n' ' ' < "$failed_packages_file" | sed 's/ $//')
		echo "Retrying packages with CARET (system libtracetools.so removed): $packages_to_build"
		
		# Log to installation_env
		{
			echo "=== Retry with CARET (system libtracetools.so removed) ==="
			echo "Packages: $packages_to_build"
			echo "CMAKE_ARGS=${CMAKE_ARGS}"
			echo "System libtracetools.so: ${system_tracetools} (temporarily renamed)"
			echo "============================================================"
		} | tee -a "${SCRIPT_DIR}/installation_env"
		
		colcon build --packages-select $packages_to_build \
		  --symlink-install \
		  --cmake-clean-cache \
		  --cmake-args ${CMAKE_ARGS} \
		  2>&1 | tee -a "$build_log"
		
		local retry_without_system_tracetools_exit_code=${PIPESTATUS[0]}
		
		# Restore system libtracetools.so
		if [ $system_tracetools_removed -eq 1 ] && [ -f "$system_tracetools_backup" ]; then
			echo "Restoring system libtracetools.so..."
			sudo mv "$system_tracetools_backup" "$system_tracetools"
		fi
		
		# Update failed packages list
		rm -f "$failed_packages_file"
		detect_failed_packages "$build_log" "$failed_packages_file"
		
		if [ ! -s "$failed_packages_file" ]; then
			echo "✓ All packages built successfully after retry with system libtracetools.so removed!"
			return 0
		fi
		
		echo "Still have $(wc -l < "$failed_packages_file" | tr -d ' ') failed package(s) after removing system libtracetools.so"
	fi
	
	# Final status - if packages still failed, try building without CARET
	if [ -s "$failed_packages_file" ]; then
		echo ""
		echo "=========================================="
		echo "⚠ WARNING: Some packages failed after all CARET retries"
		echo "Failed packages written to: $failed_packages_file"
		echo "=========================================="
		cat "$failed_packages_file"
		
		# Copy failed packages to build_without_caret file
		local build_without_caret_file="${SCRIPT_DIR}/build_without_caret"
		cp "$failed_packages_file" "$build_without_caret_file"
		echo ""
		echo "=========================================="
		echo "Attempting to build remaining packages WITHOUT CARET..."
		echo "Packages to build without CARET:"
		cat "$build_without_caret_file"
		echo "=========================================="
		
		# Build without CARET: remove CARET-specific environment variables and CMake args
		# CRITICAL: Unset LD_PRELOAD FIRST before using any shell commands (tr, grep, paste, etc.)
		# Otherwise, these commands will fail because they try to load CARET libraries
		local old_ld_preload="$LD_PRELOAD"
		unset LD_PRELOAD
		
		# Save current environment (after unsetting LD_PRELOAD so commands work)
		local old_ld_library_path="$LD_LIBRARY_PATH"
		local old_library_path="$LIBRARY_PATH"
		local old_cmake_library_path="$CMAKE_LIBRARY_PATH"
		local old_tracetools_dir="$tracetools_DIR"
		
		# Remove CARET paths from library paths (now safe because LD_PRELOAD is unset)
		export LD_LIBRARY_PATH=$(echo "$LD_LIBRARY_PATH" | tr ':' '\n' | grep -vF "${SCRIPT_DIR}/ros2_caret_ws/install" | paste -sd: -)
		export LIBRARY_PATH=$(echo "$LIBRARY_PATH" | tr ':' '\n' | grep -vF "${SCRIPT_DIR}/ros2_caret_ws/install" | paste -sd: -)
		export CMAKE_LIBRARY_PATH=$(echo "$CMAKE_LIBRARY_PATH" | tr ':' '\n' | grep -vF "${SCRIPT_DIR}/ros2_caret_ws/install" | paste -sd: -)
		unset tracetools_DIR
		
		# Remove CARET from CMAKE_PREFIX_PATH
		local old_cmake_prefix_path="$CMAKE_PREFIX_PATH"
		export CMAKE_PREFIX_PATH=$(echo "$CMAKE_PREFIX_PATH" | tr ':' '\n' | grep -vF "${SCRIPT_DIR}/ros2_caret_ws/install" | paste -sd: -)
		
		# CRITICAL: Clean build cache for failed packages before building without CARET
		# This ensures we start fresh without any CARET-linked artifacts
		echo "Cleaning build cache for packages to build without CARET..."
		local packages_to_build_without_caret=$(tr '\n' ' ' < "$build_without_caret_file" | sed 's/ $//')
		for pkg in $packages_to_build_without_caret; do
			if [ -d "build/$pkg" ]; then
				echo "  Cleaning build/$pkg..."
				rm -rf "build/$pkg"
			fi
			if [ -d "install/$pkg" ]; then
				echo "  Cleaning install/$pkg..."
				rm -rf "install/$pkg"
			fi
		done
		
		# Build with minimal CMake args (no CARET-specific settings)
		# Note: packages_to_build_without_caret is already defined above
		# Try to disable CARET tracing if possible (some packages may support this)
		local cmake_args_without_caret="-DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF"
		# Note: There's no standard CMake variable to disable CARET, but we try to ensure
		# CARET libraries are not found by explicitly excluding CARET paths
		
		echo "Building packages without CARET: $packages_to_build_without_caret"
		echo "CMAKE_ARGS (without CARET): $cmake_args_without_caret"
		echo ""
		echo "⚠ NOTE: If these packages fail with 'undefined reference' to CARET symbols"
		echo "  (ros_trace_message_construct, ros_trace_rclcpp_intra_publish, etc.),"
		echo "  it means they depend on CARET-instrumented libraries (like rclcpp)"
		echo "  that were built WITH CARET. These packages cannot be built without CARET"
		echo "  unless all their dependencies are also rebuilt without CARET."
		
		# Log to installation_env
		{
			echo "=== Building WITHOUT CARET ==="
			echo "Packages: $packages_to_build_without_caret"
			echo "CMAKE_ARGS: $cmake_args_without_caret"
			echo "CMAKE_PREFIX_PATH: $CMAKE_PREFIX_PATH"
			echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
			echo "==============================="
		} | tee -a "${SCRIPT_DIR}/installation_env"
		
		colcon build --packages-select $packages_to_build_without_caret \
		  --symlink-install \
		  --cmake-clean-cache \
		  --cmake-args ${cmake_args_without_caret} \
		  2>&1 | tee -a "$build_log"
		
		local build_without_caret_exit_code=${PIPESTATUS[0]}
		
		# Restore environment
		export LD_LIBRARY_PATH="$old_ld_library_path"
		export LIBRARY_PATH="$old_library_path"
		export CMAKE_LIBRARY_PATH="$old_cmake_library_path"
		if [ -n "$old_ld_preload" ]; then
			export LD_PRELOAD="$old_ld_preload"
		fi
		if [ -n "$old_tracetools_dir" ]; then
			export tracetools_DIR="$old_tracetools_dir"
		fi
		export CMAKE_PREFIX_PATH="$old_cmake_prefix_path"
		
		# Check if build without CARET succeeded
		rm -f "$failed_packages_file"
		detect_failed_packages "$build_log" "$failed_packages_file"
		
		if [ ! -s "$failed_packages_file" ]; then
			echo ""
			echo "=========================================="
			echo "✓ All packages built successfully (some without CARET)"
			echo "Packages built without CARET are in: $build_without_caret_file"
			echo "=========================================="
			return 0
		else
			# Log permanently failed packages and continue
			local unable_to_build_file="${SCRIPT_DIR}/unable_to_build.txt"
			cp "$failed_packages_file" "$unable_to_build_file"
			echo ""
			echo "=========================================="
			echo "⚠ WARNING: Some packages could not be built after all attempts"
			echo "These packages have been logged to: $unable_to_build_file"
			echo "The installation will continue..."
			echo "=========================================="
			cat "$unable_to_build_file"
			return 0  # Continue execution instead of failing
		fi
	else
		echo "✓ All packages built successfully!"
		return 0
	fi
}

# -------------------- Colcon Build ------------------------
cd "${SCRIPT_DIR}/autoware"

# CRITICAL: Apply CARET ament_cmake_auto fix before building
# This ensures CMake prefers CARET's instrumented libraries over system ROS 2 libraries
# See: https://github.com/tier4/caret/issues/69
apply_caret_ament_cmake_auto_fix

# Clean any Autoware overlay from the current shell environment so that CMake
# sees a clean base (opt/ros + ros2_humble + CARET) instead of resolving
# rclcpp / friends from a previously sourced autoware/install.
# This is CRITICAL when building with --packages-up-to, because dependencies
# are built first and must use CARET's rclcpp, not a previously built autoware rclcpp.
clean_env_for_autoware_build

# Reset CMAKE_PREFIX_PATH to just .local (from bashrc), then source in same order as working script
# This ensures a clean environment that matches test_autoware_dummy_perception_publisher.sh
export CMAKE_PREFIX_PATH="$HOME/.local"

source_autoware_build_env

# CRITICAL: Reorder CMAKE_PREFIX_PATH to ensure CARET's tracetools is found FIRST by CMake
# After sourcing, CMAKE_PREFIX_PATH may have /opt/ros/humble before CARET's install,
# which causes find_package(tracetools) to find the system version (without CARET symbols).
# We MUST put CARET's install directory FIRST so CMake finds the CARET-instrumented tracetools.
CARET_INSTALL="${SCRIPT_DIR}/ros2_caret_ws/install"
if [ -d "${CARET_INSTALL}" ]; then
	# Extract CARET's path from CMAKE_PREFIX_PATH if present
	CARET_PATH=$(echo "$CMAKE_PREFIX_PATH" | tr ':' '\n' | grep -F "${CARET_INSTALL}" | head -n1)
	if [ -n "${CARET_PATH}" ]; then
		# Remove CARET's path from CMAKE_PREFIX_PATH
		CMAKE_PREFIX_PATH=$(echo "$CMAKE_PREFIX_PATH" | tr ':' '\n' | grep -vF "${CARET_INSTALL}" | paste -sd: -)
		# Put CARET's path FIRST
		export CMAKE_PREFIX_PATH="${CARET_PATH}:${CMAKE_PREFIX_PATH}"
	else
		# CARET path not found, add it first
		export CMAKE_PREFIX_PATH="${CARET_INSTALL}:${CMAKE_PREFIX_PATH}"
	fi
fi

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
export LIBRARY_PATH="${SCRIPT_DIR}/ros2_caret_ws/install/lib${LIBRARY_PATH:+:${LIBRARY_PATH}}"
export LD_LIBRARY_PATH="${SCRIPT_DIR}/ros2_caret_ws/install/lib:${LD_LIBRARY_PATH}"
export CMAKE_LIBRARY_PATH="${SCRIPT_DIR}/ros2_caret_ws/install/lib${CMAKE_LIBRARY_PATH:+:${CMAKE_LIBRARY_PATH}}"
export LDFLAGS="-L${SCRIPT_DIR}/ros2_caret_ws/install/lib"
export LD_PRELOAD="${SCRIPT_DIR}/ros2_caret_ws/install/lib/libcaret.so"

# Explicitly set tracetools_DIR to force CMake to use CARET's tracetools
# This ensures find_package(tracetools) finds the CARET version even if CMAKE_PREFIX_PATH order fails
if [ -f "${SCRIPT_DIR}/ros2_caret_ws/install/share/tracetools/cmake/tracetoolsConfig.cmake" ]; then
	export tracetools_DIR="${SCRIPT_DIR}/ros2_caret_ws/install/share/tracetools/cmake"
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
else
	echo "#########################################"
	echo "#########################################"
	echo "Autoware colcon build already ran. Skipping build."
	echo "Use -b flag to force rebuild."
	echo "#########################################"
	echo "#########################################"
fi

