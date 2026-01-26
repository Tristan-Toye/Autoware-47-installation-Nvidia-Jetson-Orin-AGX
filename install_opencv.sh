#!/bin/bash
set -e

# OpenCV Installation Script
# This script installs OpenCV 4.x with CUDA and OpenGL support from source

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}"

if [ -f "${SCRIPT_DIR}/.opencv_built_flag" ] && [ -f /usr/local/lib/cmake/opencv4/OpenCVConfig.cmake ]; then
	echo "#########################################"
	echo "#########################################"
    	echo "✅ OpenCV build flag found. Skipping build."
    	echo "#########################################"
	echo "#########################################"
else
	echo "Installing OpenCV with CUDA and OpenGL support..."
	
	sudo apt remove python3-opencv -y
	sudo apt update
	sudo apt install -y build-essential pkg-config libgtk-3-dev \
	libavcodec-dev libavformat-dev libswscale-dev libv4l-dev \
	libxvidcore-dev libx264-dev libjpeg-dev libpng-dev libtiff-dev \
	gfortran openexr libatlas-base-dev python3-dev python3-numpy \
	libtbb2 libtbb-dev libdc1394-dev

	cd "${SCRIPT_DIR}"
	if [ -d opencv ]; then
		echo "opencv directory already exists. Skipping clone."
	else
		git clone https://github.com/opencv/opencv.git
	fi
	if [ -d opencv_contrib ]; then
		echo "contrib directory already exists. Skipping clone."
	else
		git clone https://github.com/opencv/opencv_contrib.git
	fi
	cd "${SCRIPT_DIR}/opencv"
	git checkout 4.x
	cd "${SCRIPT_DIR}/opencv_contrib"
	git checkout 4.x

	sudo apt-get install -y libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev 

	# Apply OpenGL header patch for ARM64
	# https://devtalk.nvidia.com/default/topic/1007290/jetson-tx2/building-opencv-with-opengl-support-/post/5141945/#5141945
	cd /usr/local/cuda/include
	sudo mkdir -p patches
	cd patches
	sudo touch OpenGLHeader.patch
	sudo cp "${SCRIPT_DIR}/OpenGLHeader.patch" OpenGLHeader.patch
	cd ../
	sudo patch -N cuda_gl_interop.h $PWD'/patches/OpenGLHeader.patch' 

	cd "${SCRIPT_DIR}/opencv"
	mkdir -p build && cd build

	cmake -D CMAKE_BUILD_TYPE=Release \
	-D CMAKE_INSTALL_PREFIX=/usr/local \
	-D OPENCV_EXTRA_MODULES_PATH="${SCRIPT_DIR}/opencv_contrib/modules" \
	-D OPENCV_GENERATE_PKGCONFIG=ON \
	-D WITH_CUDA=ON \
	-D CUDA_ARCH_BIN=8.7 \
	-D CUDA_ARCH_PTX="" \
	-D ENABLE_FAST_MATH=ON \
	-D CUDA_FAST_MATH=ON \
	-D WITH_CUBLAS=ON \
	-D WITH_CUDNN=ON \
	-D OPENCV_DNN_CUDA=ON \
	-D WITH_OPENGL=ON \
	-D WITH_QT=ON \
	-D WITH_GTK=ON \
	-D BUILD_TESTS=OFF \
	-D BUILD_PERF_TESTS=OFF \
	-D BUILD_EXAMPLES=OFF \
	-D BUILD_opencv_python3=ON \
	-D BUILD_opencv_barcode=ON \
	..

	make -j$(nproc)
	sudo make install
	touch "${SCRIPT_DIR}/.opencv_built_flag"
	
	echo "✅ OpenCV installation complete!"
fi

