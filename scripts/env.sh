# Sourced by the other scripts: paths and site-specific settings.
#
# Override any of these in $TOP/local.env (a shell fragment, ignored by git;
# see local.env.example). Values set in the environment also work, except for
# scripts that re-run themselves under sudo, which only see local.env.
TOP=${TOP:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
# shellcheck disable=SC1091
[ -f "$TOP/local.env" ] && . "$TOP/local.env"

# Source trees: scripts/fetch-sources.sh clones the pinned versions here
OPI5_SRC=${OPI5_SRC:-$TOP/src}

# The Orange Pi 5 over SSH (pi-*.sh). The image's default user is "ubuntu".
OPI5_PI=${OPI5_PI:-ubuntu@orangepi5}
OPI5_SSH_KEY=${OPI5_SSH_KEY:-$TOP/.ssh/opi5_ed25519}
OPI5_KNOWN_HOSTS=${OPI5_KNOWN_HOSTS:-$TOP/.ssh/known_hosts}

# Build PC network ports (nat-on.sh, bridge-on.sh): the LAN uplink and the
# port the board is cabled to, and the subnet nat-on.sh gives that port
OPI5_UPLINK=${OPI5_UPLINK:-enp129s0}
OPI5_PORT=${OPI5_PORT:-enp130s0}
OPI5_NAT_ADDR=${OPI5_NAT_ADDR:-172.31.55.1/24}
# make-board-permanent.sh: pin the board's DHCP lease (no defaults)
OPI5_PI_MAC=${OPI5_PI_MAC:-}
OPI5_PI_IP=${OPI5_PI_IP:-}

# Identity used when formatting/sending upstream patches
OPI5_NAME=${OPI5_NAME:-$(git config user.name 2>/dev/null || true)}
OPI5_EMAIL=${OPI5_EMAIL:-$(git config user.email 2>/dev/null || true)}
