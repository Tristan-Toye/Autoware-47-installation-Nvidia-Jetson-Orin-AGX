#!/bin/bash
set -e

# ROS 2 Humble Installation Script with Tracing Support
# This script installs ROS 2 Humble from source with tracing support

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}"

if [ -f "${SCRIPT_DIR}/.ros_humble_flag" ]; then
	echo "#########################################"
	echo "#########################################"
    	echo "ROS 2 Humble is already installed. Skipping ROS installation."
	echo "#########################################"
	echo "#########################################"
else
	echo "Installing ROS 2 Humble..."

	# Locale configuration
	locale  # check for UTF-8
	sudo apt update && sudo apt install locales
	sudo locale-gen en_US en_US.UTF-8
	sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
	export LANG=en_US.UTF-8
	locale  # verify settings
	
	# ROS 2 repository setup
	sudo apt install software-properties-common
	sudo add-apt-repository universe
	sudo apt update && sudo apt install curl -y
	export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F\" '{print $4}')
	curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb"
	sudo dpkg -i /tmp/ros2-apt-source.deb
	
	sudo apt update
	sudo apt upgrade

	# ROS 2 desktop installation
	sudo apt install ros-humble-desktop
	
	# Development dependencies
	sudo apt update && sudo apt install -y \
	  python3-flake8-docstrings \
	  python3-pip \
	  python3-pytest-cov \
	  ros-dev-tools \
	  python3-colcon-common-extensions
	
	sudo apt install -y \
	   python3-flake8-blind-except \
	   python3-flake8-builtins \
	   python3-flake8-class-newline \
	   python3-flake8-comprehensions \
	   python3-flake8-deprecated \
	   python3-flake8-import-order \
	   python3-flake8-quotes \
	   python3-pytest-repeat \
	   python3-pytest-rerunfailures

	source /opt/ros/humble/setup.bash

	# ROS 2 tracing installation
	sudo apt install lttng-tools liblttng-ust-dev python3-babeltrace python3-lttng
	cd "${SCRIPT_DIR}"
	if [ ! -d ros2_tracing ]; then
		git clone https://gitlab.com/ros-tracing/ros2_tracing.git
	fi
	cd "${SCRIPT_DIR}/ros2_tracing"
	colcon build --packages-up-to tracetools
	colcon build --packages-up-to tracetools --allow-overriding tracetools
	
	touch "${SCRIPT_DIR}/.ros_humble_flag"
	
	echo "✅ ROS 2 Humble installation complete!"
fi

# Clean up conflicting ROS APT repositories
sudo rm -f /etc/apt/sources.list.d/ros-latest.list

