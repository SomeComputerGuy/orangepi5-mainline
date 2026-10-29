#!/bin/bash
# Undo nat-on.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
. "$(dirname "$0")/env.sh"
PORT=$OPI5_PORT UPLINK=$OPI5_UPLINK
rm -f /etc/systemd/network/05-opi5-$PORT.network /etc/sysctl.d/90-opi5-nat.conf
sysctl -q -w net.ipv4.ip_forward=0
if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
  ufw route delete allow in on "$PORT" out on "$UPLINK" || true
  ufw delete allow in on "$PORT" to any port 67 proto udp || true
fi
networkctl reload
networkctl reconfigure "$PORT"
networkctl status "$PORT" --no-pager | grep -E 'State|Address'
