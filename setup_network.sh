#!/usr/bin/env bash
set -euo pipefail
set -x

add_line_if_missing() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"
}
iface="lo"

# Ensure we have the absolute path to ip
ip_bin="$(command -v ip)"

# Turn on multicast on the interface now
sudo "$ip_bin" link set "$iface" multicast on

service_name="multicast-${iface}.service"
service_file="/etc/systemd/system/${service_name}"

export iface ip_bin

envsubst '$iface $ip_bin'  < "${SCRIPT_DIR}/${service_name}" | sudo tee "${service_file}" > /dev/null

# sudo cp "${SCRIPT_DIR}/${service_name}" "${service_file}"


# Reload + enable + start (needs sudo)
sudo systemctl daemon-reload
sudo systemctl enable "$service_name"
sudo systemctl start "$service_name"
echo "Installed and started $service_name"

# Validation
echo "##################################################"
echo "##################################################"
echo "Validating network setup $iface multicast"
# sudo systemctl status "$service_name" || true
sudo systemctl --no-pager --full --lines=0 status "$service_name" || true
sudo journalctl  --no-pager -u "$service_name" -n 20 || true
"$ip_bin" link show "$iface"
echo "##################################################"
echo "##################################################"
# Remove ROS_LOCALHOST_ONLY from bashrc (per Autoware docs)
sed -i -E '/^[[:space:]]*#/!{/^[[:space:]]*(export[[:space:]]+)?ROS_LOCALHOST_ONLY[[:space:]]*=/d;}' "$HOME/.bashrc"

#-----------------------------------------------------------------------------

# Tuning Cyclone DDS

#-----------------------------------------------------------------------------

cyclone_conf_name="10-cyclone-max.conf"
cyclone_conf_file="/etc/sysctl.d/${cyclone_conf_name}"
# Increase receive buffer + IP fragmentation thresholds (immediate)
sudo sysctl -w net.core.rmem_max=2147483647
sudo sysctl -w net.ipv4.ipfrag_time=3
sudo sysctl -w net.ipv4.ipfrag_high_thresh=134217728

# Persist these settings (use sudo tee)
sudo cp "${SCRIPT_DIR}/${cyclone_conf_name}" "${cyclone_conf_file}"

# Reload sysctl from config files
sudo sysctl --system

# Validation: Cyclone DDS related sysctls
echo "##################################################"
echo "##################################################"
echo "Validating Cyclone DDS-related sysctl settings"
sysctl net.core.rmem_max net.ipv4.ipfrag_time net.ipv4.ipfrag_high_thresh

echo "##################################################"
echo "##################################################"

# Build CYCLONEDDS_URI and add to .bashrc if missing

envsubst '$iface'  < "${SCRIPT_DIR}/cyclonedds.xml" | sudo tee "${SCRIPT_DIR}/cyclonedds.xml" > /dev/null

CYCLONEDDS_XML="${SCRIPT_DIR}/cyclonedds.xml"
B="$HOME/.bashrc"


add_line_if_missing 'export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp' "$B"

add_line_if_missing "export CYCLONEDDS_URI=file://$CYCLONEDDS_XML" "$B"

echo "stored path as 'export CYCLONEDDS_URI=file://$CYCLONEDDS_XML' "

# Source for current shell (optional; new shells will pick it up automatically)
# shellcheck disable=SC1090
source "$B"

