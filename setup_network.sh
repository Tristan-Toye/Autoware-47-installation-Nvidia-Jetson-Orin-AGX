set -x
set -e 

iface="lo"

sudo ip link set "${iface}" multicast on


service_name="multicast-${iface}.service"
service_file="/etc/systemd/system/${service_name}"

cat > "$service_file" <<EOF
[Unit]
Description=Enable Multicast on ${iface}

[Service]
Type=oneshot
ExecStart=${ip_bin} link set ${iface} multicast on

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$service_name"
    systemctl start "$service_name"
    echo "Installed and started $service_name"


#validation
echo "Validating network setup lo mulicast"
systemctl status "$service_name" || true
ip link show "${iface}"

# remove ROS_LOCALHOST_ONLY variable from bashrc as specified in documentation
# https://autowarefoundation.github.io/autoware-documentation/main/installation/additional-settings-for-developers/network-configuration/dds-settings/#about-ros_localhost_only-environment-variable
sed -i -E '/^[[:space:]]*#/!{/^[[:space:]]*(export[[:space:]]+)?ROS_LOCALHOST_ONLY[[:space:]]*=/d;}' "$HOME/.bashrc"

# Increase the maximum receive buffer size for network packets
sudo sysctl -w net.core.rmem_max=2147483647  # 2 GiB, default is 208 KiB

# IP fragmentation settings
sudo sysctl -w net.ipv4.ipfrag_time=3  # in seconds, default is 30 s
sudo sysctl -w net.ipv4.ipfrag_high_thresh=134217728  # 128 MiB, default is 256 KiB

cat > /etc/sysctl.d/10-cyclone-max.conf <<EOF
# Increase the maximum receive buffer size for network packets
net.core.rmem_max=2147483647  # 2 GiB, default is 208 KiB

# IP fragmentation settings
net.ipv4.ipfrag_time=3  # in seconds, default is 30 s
net.ipv4.ipfrag_high_thresh=134217728  # 128 MiB, default is 256 KiB
EOF

#Validation cyclone dds
echo "Validating cycling DDS settings"
sysctl net.core.rmem_max net.ipv4.ipfrag_time net.ipv4.ipfrag_high_thresh

CYCLONEDDS_XML= "${SCRIPT_DIR}"/cyclonedds.xml
B="$HOME/.bashrc"

grep -qxF 'export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp' "$B" || printf '\nexport RMW_IMPLEMENTATION=rmw_cyclonedds_cpp\n' >> "$B"; \
grep -qxF "export CYCLONEDDS_URI=file://$CYCLONEDDS_XML" "$B" || printf 'export CYCLONEDDS_URI=file://%s\n' "$CYCLONEDDS_XML" >> "$B"
echo "stored pat as 'export CYCLONEDDS_URI=file://$CYCLONEDDS_XML' "

source ~/.bashrc
