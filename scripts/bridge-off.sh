#!/bin/bash
# Undo bridge-on.sh: remove the bridge and return the uplink to plain DHCP
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
rm -f /etc/netplan/90-opi5-bridge.yaml /etc/systemd/network/10-netplan-br0.network.d/50-opi5-same-dhcp-id.conf
rmdir /etc/systemd/network/10-netplan-br0.network.d 2>/dev/null || true
if ip link show br0 >/dev/null 2>&1; then ip link delete br0; fi
netplan apply
sleep 3
ip -br addr
