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

		# Force CARET's rclcpp and rclcpp_components during configure to avoid system targets
		if [ -f "${CARET_INSTALL_DIR}/share/rclcpp/cmake/rclcppConfig.cmake" ]; then
			CMAKE_ARGS="${CMAKE_ARGS} -Drclcpp_DIR=${CARET_INSTALL_DIR}/share/rclcpp/cmake"
		fi
		if [ -f "${CARET_INSTALL_DIR}/share/rclcpp_components/cmake/rclcpp_componentsConfig.cmake" ]; then
			CMAKE_ARGS="${CMAKE_ARGS} -Drclcpp_components_DIR=${CARET_INSTALL_DIR}/share/rclcpp_components/cmake"
		fi
		
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