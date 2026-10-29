#!/bin/bash
# Give the second ethernet port ($OPI5_PORT) its own subnet with a DHCP server and
# NAT out through the main port, without touching the main port's config.
# The device on $OPI5_PORT gets an address from $OPI5_NAT_ADDR (.100-.149) and
# internet access via this PC. Set the OPI5_* variables in local.env.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
. "$(dirname "$0")/env.sh"
PORT=$OPI5_PORT UPLINK=$OPI5_UPLINK
NET=/etc/systemd/network/05-opi5-$PORT.network   # sorts before netplan's 10-netplan-*, so it wins
SYSCTL=/etc/sysctl.d/90-opi5-nat.conf
DNS=$(resolvectl dns "$UPLINK" | awk '{print $NF}')
DNS=${DNS:-1.1.1.1}

cat > "$NET" <<INI
[Match]
Name=$PORT

[Network]
Address=$OPI5_NAT_ADDR
DHCPServer=yes
IPMasquerade=ipv4
ConfigureWithoutCarrier=yes

[DHCPServer]
PoolOffset=100
PoolSize=50
EmitDNS=yes
DNS=$DNS
INI

# Replies from the internet enter via $UPLINK, so forwarding is needed there too
echo 'net.ipv4.ip_forward = 1' > "$SYSCTL"
sysctl -q -p "$SYSCTL"

# Only $PORT is reconfigured; $UPLINK's config is unchanged and left alone
networkctl reload
networkctl reconfigure "$PORT"

if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
  ufw route allow in on "$PORT" out on "$UPLINK"
  ufw allow in on "$PORT" to any port 67 proto udp
fi

sleep 3
networkctl status "$PORT" --no-pager | grep -E 'State|Address|Offered|DHCP'
echo "Undo with scripts/nat-off.sh"
