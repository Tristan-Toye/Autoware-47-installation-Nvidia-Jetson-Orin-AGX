#!/usr/bin/env bash
# Set up development environment for Autoware Core/Universe.
# Usage: setup-dev-env.sh <ros2_installation_type('core' or 'universe')> [-y] [-v] [--no-nvidia]
# Note: -y option is only for CI.

set -e

# Function to print help message
print_help() {
    echo "Usage: setup-dev-env.sh [OPTIONS]"
    echo "Options:"
    echo "  --help          Display this help message"
    echo "  -h              Display this help message"
    echo "  -y              Use non-interactive mode"
    echo "  -v              Enable debug outputs"
    echo "  --no-nvidia     Disable installation of the NVIDIA-related roles ('cuda' and 'tensorrt')"
    echo "  --no-cuda-drivers Disable installation of 'cuda-drivers' in the role 'cuda'"
    echo "  --runtime       Disable installation dev package of role 'cuda' and 'tensorrt'"
    echo "  --data-dir      Set data directory (default: $HOME/autoware_data)"
    echo "  --download-artifacts"
    echo "                  Download artifacts"
    echo "  --module        Specify the module (default: all)"
    echo ""
}

SCRIPT_DIR=$(readlink -f "$(dirname "$0")")

# Parse arguments
args=()
option_data_dir="$HOME/autoware_data"

while [ "$1" != "" ]; do
    case "$1" in
    --help | -h)
        print_help
        exit 1
        ;;
    -y)
        # Use non-interactive mode.
        option_yes=true
        ;;
    -v)
        # Enable debug outputs.
        option_verbose=true
        ;;
    --no-nvidia)
        # Disable installation of the NVIDIA-related roles ('cuda' and 'tensorrt').
        option_no_nvidia=true
        ;;
    --no-cuda-drivers)
        # Disable installation of 'cuda-drivers' in the role 'cuda'.
        option_no_cuda_drivers=true
        ;;
    --runtime)
        # Disable installation dev package of role 'cuda' and 'tensorrt'.
        option_runtime=true
        ;;
    --data-dir)
        # Set data directory
        option_data_dir="$2"
        shift
        ;;
    --download-artifacts)
        # Set download artifacts option
        option_download_artifacts=true
        ;;
    --module)
        option_module="$2"
        shift
        ;;
    *)
        args+=("$1")
        ;;
    esac
    shift
done

# Select installation type
target_playbook="autoware.dev_env.universe" # default

if [ ${#args[@]} -ge 1 ]; then
    target_playbook="autoware.dev_env.${args[0]}"
fi

# Initialize ansible args
ansible_args=()

# Confirm to start installation
if [ "$option_yes" = "true" ]; then
    echo -e "\e[36mRun the setup in non-interactive mode.\e[m"
else
    echo -e "\e[33mSetting up the build environment can take up to 1 hour.\e[m"
    read -rp ">  Are you sure you want to run setup? [y/N] " answer

    # Check whether to cancel
    if ! [[ ${answer:0:1} =~ y|Y ]]; then
        echo -e "\e[33mCancelled.\e[0m"
        exit 1
    fi

    ansible_args+=("--ask-become-pass")
fi

# Check verbose option
if [ "$option_verbose" = "true" ]; then
    ansible_args+=("-vvv")
fi

# Check installation of NVIDIA libraries
if [ "$option_no_nvidia" = "true" ]; then
    ansible_args+=("--extra-vars" "prompt_install_nvidia=n")
elif [ "$option_yes" = "true" ]; then
    ansible_args+=("--extra-vars" "prompt_install_nvidia=y")
fi

# Check installation of CUDA Drivers
if [ "$option_no_cuda_drivers" = "true" ]; then
    ansible_args+=("--extra-vars" "cuda_install_drivers=false")
fi

# Check installation of dev package
if [ "$option_runtime" = "true" ]; then
    ansible_args+=("--extra-vars" "ros2_installation_type=ros-base") # ROS installation type, default "desktop"
    ansible_args+=("--extra-vars" "install_devel=N")
else
    ansible_args+=("--extra-vars" "install_devel=y")
fi

# Check downloading artifacts
if [ "$target_playbook" = "autoware.dev_env.openadkit" ]; then
    if [ "$option_download_artifacts" = "true" ]; then
        echo -e "\e[36mArtifacts will be downloaded to $option_data_dir\e[m"
        ansible_args+=("--extra-vars" "prompt_download_artifacts=y")
    else
        ansible_args+=("--extra-vars" "prompt_download_artifacts=N")
    fi
elif [ "$option_yes" = "true" ] || [ "$option_download_artifacts" = "true" ]; then
    echo -e "\e[36mArtifacts will be downloaded to $option_data_dir\e[m"
    ansible_args+=("--extra-vars" "prompt_download_artifacts=y")
fi

ansible_args+=("--extra-vars" "data_dir=$option_data_dir")

# Check module option
if [ "$option_module" != "" ]; then
    ansible_args+=("--extra-vars" "module=$option_module")
fi

# Load env
source "$SCRIPT_DIR/amd64.env"
if [ "$(uname -m)" = "aarch64" ]; then
    source "$SCRIPT_DIR/arm64.env"
fi

# Add env args
# shellcheck disable=SC2013
for env_name in $(sed -e "s/^\s*//" -e "/^#/d" -e "s/=.*//" <amd64.env); do
    ansible_args+=("--extra-vars" "${env_name}=${!env_name}")
done

# Install sudo
if ! (command -v sudo >/dev/null 2>&1); then
    apt-get -y update
    apt-get -y install sudo
fi

# Install git
if ! (command -v git >/dev/null 2>&1); then
    sudo apt-get -y update
    sudo apt-get -y install git
fi

# Install pip for ansible
if ! (python3 -m pip --version >/dev/null 2>&1); then
    sudo apt-get -y update
    sudo apt-get -y install python3-pip python3-venv
fi

# Install pipx for ansible
if ! (python3 -m pipx --version >/dev/null 2>&1); then
    sudo apt-get -y update
    python3 -m pip install --user pipx
fi

# Install ansible
python3 -m pipx ensurepath
export PATH="${PIPX_BIN_DIR:=$HOME/.local/bin}:$PATH"
pipx install --include-deps --force "ansible==6.*"




# Install ansible collections
echo -e "\e[36m"ansible-galaxy collection install -f -r "$SCRIPT_DIR/ansible-galaxy-requirements.yaml" "\e[m"
ansible-galaxy collection install -f -r "$SCRIPT_DIR/ansible-galaxy-requirements.yaml"

# ─── BOOTSTRAP L4T HEADERS ───────────────────────────────────────────────────

if [[ "$(uname -m)" == "aarch64" ]]; then
    echo "Ensuring NVIDIA L4T repo & kernel headers are installed..."
    sudo apt-key adv --fetch-keys https://repo.download.nvidia.com/jetson/jetson-ota-public.asc
    # Determine L4T release
    if [[ -f /etc/nv_tegra_release ]]; then
        L4T_MAJOR=$(grep -oP 'R\K[0-9]+' /etc/nv_tegra_release)
        L4T_MINOR=$(grep -oP 'REVISION:\s*\K[0-9]+' /etc/nv_tegra_release)
        RELEASE_STR="r${L4T_MAJOR}.${L4T_MINOR}"
    else
        RELEASE_STR="r36.4"
    fi
    cat <<EOF | sudo tee /etc/apt/sources.list.d/nvidia-l4t-apt-source.list >/dev/null
# NVIDIA L4T repositories for release ${RELEASE_STR}
deb https://repo.download.nvidia.com/jetson/common ${RELEASE_STR} main
deb https://repo.download.nvidia.com/jetson/t234    ${RELEASE_STR} main
deb https://repo.download.nvidia.com/jetson/ffmpeg  ${RELEASE_STR} main
EOF
    sudo apt-get update -y
    sudo apt-get install -y nvidia-l4t-apt-source nvidia-l4t-kernel-headers

    # ▶ Create a small *virtual* linux-headers-$(uname -r) that DEPENDS on NVIDIA's headers
    if ! dpkg -s "linux-headers-$(uname -r)" &>/dev/null; then
        sudo apt-get install -y equivs
        cat <<EOD >linux-headers-dummy-control
Section: misc
Priority: optional
Standards-Version: 3.9.2
Package: linux-headers-$(uname -r)
Provides: linux-headers-$(uname -r)
Depends: nvidia-l4t-kernel-headers
Description: Virtual package to satisfy linux-headers dependency on Jetson
 This virtual package depends on NVIDIA's L4T kernel headers and is only
 meant to satisfy tools that look specifically for linux-headers-\$(uname -r).
EOD
        equivs-build linux-headers-dummy-control
        sudo dpkg -i linux-headers-$(uname -r)_*.deb
        rm linux-headers-dummy-control linux-headers-$(uname -r)_*.deb
    fi

    # Also install the specific linux-headers package if available (harmless if none)
    KVER=$(uname -r)
    HDR_PKG=$(apt-cache search "^linux-headers-${KVER}" | awk '{print $1}' | head -n1 || true)
    if [[ -n "$HDR_PKG" ]]; then
        echo "Installing ${HDR_PKG} to satisfy kernel headers..."
        sudo apt-get install -y "${HDR_PKG}"
    fi
fi

# Run ansible
echo -e "\e[36m"ansible-playbook "$target_playbook" "${ansible_args[@]}" "\e[m"
if ansible-playbook "$target_playbook" "${ansible_args[@]}"; then
    echo -e "\e[32mCompleted.\e[0m"
    exit 0
else
    echo -e "\e[31mFailed.\e[0m"
    exit 1
fi


#disable agnocast load on boot
sudo rm -f /etc/modules-load.d/agnocast.conf || true

