#!/bin/bash
set -e

# Autoware Setup Script
# This script sets up the Autoware repository and installs dependencies

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}"

rerun_autoware_setup="${1:-0}"

if [ -f "${SCRIPT_DIR}/.autoware_setup_flag" ] && (( ! rerun_autoware_setup )); then
	echo "#########################################"
	echo "#########################################"
    	echo "Autoware setup already ran. Skipping setup-dev-env.sh script."
	echo "#########################################"
	echo "#########################################"
else
	echo "Setting up Autoware..."
	
	cd "${SCRIPT_DIR}"
	sudo apt install python3.10-venv -y

	if [ -d autoware ]; then
	    	echo "Autoware directory already exists. Checking out tag 1.5.0..."
		cd autoware
		git fetch --tags
		git checkout 1.5.0 || {
			echo "Warning: Could not checkout tag 1.5.0. Current branch/commit:"
			git describe --tags --always
			exit 1
		}
		echo "Autoware 1.5.0 checked out successfully"
		cd "${SCRIPT_DIR}"
	else
	  	git clone --branch 1.5.0 --tags https://github.com/autowarefoundation/autoware.git
		echo "#############################################"
		echo "Autoware 1.5.0 cloned and checked out"
		echo "#############################################"
	fi
	
	# Copy custom setup script
	cp "${SCRIPT_DIR}/setup-dev-env.sh" "${SCRIPT_DIR}/autoware/setup-dev-env.sh"
	cd "${SCRIPT_DIR}/autoware"

	# Run Autoware setup
	./setup-dev-env.sh -y --no-nvidia --no-cuda-drivers --download-artifacts
	touch "${SCRIPT_DIR}/.autoware_setup_flag"
	
	echo "✅ Autoware setup complete!"
fi

# ROS Dependencies Resolution
rebuild_autoware="${2:-0}"

if [ -f  "${SCRIPT_DIR}/.ros_dependencies" ] && (( ! rebuild_autoware )) ; then
	echo "#########################################"
	echo "#########################################"
    	echo "Rosdep dependencies already installed."
	echo "#########################################"
	echo "#########################################"
else
	echo "Installing ROS dependencies..."
	
	sudo apt -y update 
	sudo apt -y upgrade

	rosdep update
	sudo apt -y update

	[ -d src ] && sudo rm -rf src
	mkdir src
	cd "${SCRIPT_DIR}/autoware"
	vcs import src < autoware.repos
	vcs import src < extra-packages.repos

	rosdep install -y --from-paths src --ignore-src --rosdistro humble

	cd "${SCRIPT_DIR}"
	sudo apt install ros-humble-cv-bridge -y
	sudo apt install ros-humble-rosbag2-storage-default-plugins ros-humble-sqlite3-vendor 
	sudo apt install -y ros-humble-grid-map-cv \
		            ros-humble-grid-map-core \
		            ros-humble-grid-map-ros \
		            ros-humble-grid-map-msgs
	
	touch "${SCRIPT_DIR}/.ros_dependencies"
	
	echo "✅ ROS dependencies installation complete!"
fi

