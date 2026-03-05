#!/bin/bash
set -e
set +x

# Build script for Autoware WITHOUT CARET/LTTng tracing
# Usage: build_autoware_no_tracing.sh <SCRIPT_DIR> [rebuild_flag] [packages_to_build]

SCRIPT_DIR="$1"
REBUILD_FLAG="${2:-0}"
PACKAGES_TO_BUILD="${3:-}"
export SCRIPT_DIR="${SCRIPT_DIR}"

if [ -z "$SCRIPT_DIR" ]; then
  echo "Error: SCRIPT_DIR argument is required"
  exit 1
fi

export PATH="/usr/local/cuda/bin:$PATH"
OPENCV_STUBS_DIR="${HOME}/.local/lib/opencv_stubs"
if [ -d "${OPENCV_STUBS_DIR}" ]; then
  export LIBRARY_PATH="${OPENCV_STUBS_DIR}${LIBRARY_PATH:+:${LIBRARY_PATH}}"
  export LDFLAGS="-L${OPENCV_STUBS_DIR} ${LDFLAGS:-}"
fi


source_autoware_build_env() {
  # shellcheck disable=SC1091
  source /opt/ros/humble/setup.bash
}

detect_failed_packages() {
	local log_file="$1"
	local failed_file="$2"
	
	local summary_section=""
	if grep -q "^Summary:" "$log_file" 2>/dev/null; then
		summary_section=$(sed -n '/^Summary:/,$p' "$log_file" 2>/dev/null || echo "")
		echo "Found Summary: in log file"
	elif grep -q "Summary:" "$log_file" 2>/dev/null; then
		summary_section=$(sed -n '/Summary:/,$p' "$log_file" 2>/dev/null || echo "")
		echo "Found summary with fallback method"
	else
		summary_section=$(tail -100 "$log_file" 2>/dev/null || echo "")
		echo "Summary not found, taking last 100 lines"
	fi
	
	if echo "$summary_section" | grep -q "packages failed:"; then
		echo "$summary_section" | grep "packages failed:" | \
			sed 's/.*packages failed: *//' | \
			tr ' ' '\n' | \
			grep -v '^$' | \
			sort -u > "$failed_file" || true
	fi
	
	if [ -s "$failed_file" ]; then
		grep -E "Failed[[:space:]]+<<<" "$log_file" 2>/dev/null | \
			sed 's/.*Failed[[:space:]]\+<<< \([^ ]*\).*/\1/' | \
			sort -u >> "$failed_file" || true
	else
		grep -E "Failed[[:space:]]+<<<" "$log_file" 2>/dev/null | \
			sed 's/.*Failed[[:space:]]\+<<< \([^ ]*\).*/\1/' | \
			sort -u > "$failed_file" || true
	fi
	
	if [ -d "log/latest_build" ]; then
		find log/latest_build -name "stderr" -exec grep -l "error\|Error\|ERROR\|failed\|Failed" {} \; 2>/dev/null | \
		while read -r stderr_file; do
			package_name=$(basename "$(dirname "$stderr_file")")
			echo "$package_name" >> "$failed_file"
		done
	fi
	
	sort -u "$failed_file" -o "$failed_file" 2>/dev/null || true
	sed -i '/^$/d' "$failed_file" 2>/dev/null || true
	
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

build_with_retry() {
	local initial_packages="${1:-}"
	local build_log="${SCRIPT_DIR}/autoware_build.log"
	local failed_packages_file="${SCRIPT_DIR}/failed_packages.txt"
	
	local colcon_packages_args=""
	if [ -n "$initial_packages" ]; then
		colcon_packages_args="--packages-select $initial_packages"
		echo "=========================================="
		echo "Building selected packages: $initial_packages"
		echo "=========================================="
	else
		echo "=========================================="
		echo "Building Autoware (continuing on errors)..."
		echo "=========================================="
	fi
	
	CMAKE_ARGS="-DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF"
	export CXXFLAGS="${CXXFLAGS:-} -Wno-error=deprecated-declarations -Wno-error=pedantic -Wno-error=narrowing -Wno-error=maybe-uninitialized -Wno-error=attributes"

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
	
	rm -f "$failed_packages_file"
	detect_failed_packages "$build_log" "$failed_packages_file" || true
	
	if [ ! -s "$failed_packages_file" ]; then
		echo "All packages built successfully!"
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

copy_autoware_dummy_perception_publisher() {
	local source_dir="${SCRIPT_DIR}/autoware_dummy_perception_publisher"
	local target_dir="${SCRIPT_DIR}/autoware/src/universe/autoware_universe/simulator/autoware_dummy_perception_publisher"
	
	if [ -d "$source_dir" ]; then
		echo "Copying autoware_dummy_perception_publisher to target location..."
		if [ -d "$target_dir" ]; then
			echo "  Removing existing folder: $target_dir"
			rm -rf "$target_dir"
		fi
		echo "  Copying from: $source_dir"
		echo "  To: $target_dir"
		cp -r "$source_dir" "$target_dir"
		echo "autoware_dummy_perception_publisher folder copied successfully"
	else
		echo "Warning: Source directory not found: $source_dir"
		echo "  Skipping copy operation"
	fi
}

apply_pcl_pedantic_fix() {
	local cmake_file="${SCRIPT_DIR}/autoware/src/universe/autoware_universe/simulator/autoware_dummy_perception_publisher/CMakeLists.txt"
	
	if [ ! -f "$cmake_file" ]; then
		echo "Warning: CMakeLists.txt not found: $cmake_file"
		return
	fi
	
	if grep -q "PCL uses anonymous structs/unions; silence pedantic Werror" "$cmake_file"; then
		echo "PCL pedantic fix already applied to autoware_dummy_perception_publisher CMakeLists.txt"
		return
	fi
	
	echo "Applying PCL pedantic fix to autoware_dummy_perception_publisher CMakeLists.txt..."
	
	cp "$cmake_file" "${cmake_file}.bak"
	
	local insert_after_line=$(grep -n '\$<INSTALL_INTERFACE:include>)' "$cmake_file" | head -1 | cut -d: -f1)
	
	if [ -z "$insert_after_line" ]; then
		echo "Warning: Could not find insertion point in CMakeLists.txt"
		mv "${cmake_file}.bak" "$cmake_file"
		return
	fi
	
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
	
	if grep -q "PCL uses anonymous structs/unions; silence pedantic Werror" "$cmake_file"; then
		echo "PCL pedantic fix successfully applied to autoware_dummy_perception_publisher CMakeLists.txt"
		rm -f "${cmake_file}.bak"
	else
		echo "Warning: Fix may not have been applied correctly. Restoring backup..."
		mv "${cmake_file}.bak" "$cmake_file"
	fi
}

apply_pcl_pedantic_fix

# Remove system libtracetools.so reference from pcl_ros export (build compatibility)
if grep -q 'libtracetools.so' /opt/ros/humble/share/pcl_ros/cmake/export_pcl_rosExport.cmake 2>/dev/null; then
  sudo cp /opt/ros/humble/share/pcl_ros/cmake/export_pcl_rosExport.cmake /opt/ros/humble/share/pcl_ros/cmake/export_pcl_rosExport.cmake.bak
  sudo sed -i -e 's/\/opt\/ros\/humble\/lib\/libtracetools.so;//g' /opt/ros/humble/share/pcl_ros/cmake/export_pcl_rosExport.cmake
else
  echo "pcl_ros export_pcl_rosExport.cmake already patched (libtracetools.so reference removed)"
fi

source_autoware_build_env

export CUDAToolkit_ROOT=/usr/local/cuda
export spconv_DIR="$HOME/.local/lib/cmake/spconv"
export cumm_DIR="$HOME/.local/share/cmake/cumm"

# Debug: show environment before build
{
	echo "=== Build Environment (no tracing) ==="
	echo "CMAKE_PREFIX_PATH=$CMAKE_PREFIX_PATH"
	echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
	echo "LIBRARY_PATH=$LIBRARY_PATH"
	echo "CMAKE_LIBRARY_PATH=$CMAKE_LIBRARY_PATH"
	echo "LDFLAGS=$LDFLAGS"
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
	echo "Cleaned build directories"
	build_with_retry 
	touch "${SCRIPT_DIR}/.autoware_build_flag"
elif [ ! -f "${SCRIPT_DIR}/.autoware_build_flag" ]; then
	build_with_retry 
	touch "${SCRIPT_DIR}/.autoware_build_flag"
elif [ -n "$PACKAGES_TO_BUILD" ]; then
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
