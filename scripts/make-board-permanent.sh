#!/bin/bash
# Make the Orange Pi 5 test setup on this PC permanent:
#  - pin the Pi's DHCP lease on $OPI5_PORT to $OPI5_PI_IP (by its MAC, $OPI5_PI_MAC;
#    set both in local.env)
#  - add you to dialout, so /dev/ttyUSB0 works after replugs and reboots
#    (takes effect at your next login)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
. "$(dirname "$0")/env.sh"
NET=/etc/systemd/network/05-opi5-$OPI5_PORT.network
PI_MAC=$OPI5_PI_MAC PI_IP=$OPI5_PI_IP
[ -n "$PI_MAC" ] && [ -n "$PI_IP" ] || { echo "set OPI5_PI_MAC and OPI5_PI_IP in $TOP/local.env"; exit 1; }

[ -f "$NET" ] || { echo "$NET missing; run scripts/nat-on.sh first"; exit 1; }
if ! grep -q '^\[DHCPServerStaticLease\]' "$NET"; then
  printf '\n[DHCPServerStaticLease]\nMACAddress=%s\nAddress=%s\n' "$PI_MAC" "$PI_IP" >> "$NET"
  networkctl reload
  networkctl reconfigure "$OPI5_PORT"
fi
grep -A2 '^\[DHCPServerStaticLease\]' "$NET"

usermod -aG dialout "${SUDO_USER:?run with sudo from your own account}"
id -nG "${SUDO_USER:?run with sudo from your own account}" | tr ' ' '\n' | grep -x dialout >/dev/null && echo "dialout: added (log in again to use it)"
