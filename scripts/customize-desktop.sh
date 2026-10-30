#!/bin/bash
# mmdebstrap customize hook for IMAGE_VARIANT=desktop; runs before customize-rootfs.sh
# (which then adds the common overlay, the kernel and the first-boot cleanup):
# desktop overlay, Jellyfin MPV Shim, graphical boot
set -euo pipefail
R=$1 TOP=$2

# mmdebstrap's copies of the build-time third-party sources (NNNN<name>.sources);
# the image uses overlay-desktop's mozilla.sources and the google-chrome.sources
# that Chrome's postinst writes
rm -f "$R"/etc/apt/sources.list.d/[0-9][0-9][0-9][0-9]*.sources
rsync -rlt --chown=root:root --chmod=D755,F644 "$TOP/overlay-desktop/" "$R/"
chmod 755 "$R"/usr/local/bin/*
chmod 600 "$R/etc/netplan/01-network-manager-all.yaml"   # netplan wants it private

# Jellyfin MPV Shim: the pinned, sha256-checked wheels in a venv that uses
# Ubuntu's python3-mpv/-requests/-pil/... (system site packages); python3-mpv
# loads libmpv2, our v4l2request build
W=$R/tmp/opi5-wheels
mkdir -p "$W"
while read -r sha file url; do
  case $sha in ''|'#'*) continue ;; esac
  curl -fsSL --retry 3 -o "$W/$file" "$url"
  echo "$sha  $W/$file" | sha256sum -c --quiet
done < "$TOP/scripts/jellyfin-mpv-shim.wheels"
V=/opt/jellyfin-mpv-shim
chroot "$R" python3 -m venv --system-site-packages "$V"
chroot "$R" env PIP_DISABLE_PIP_VERSION_CHECK=1 "$V/bin/pip" install -q --no-index --no-deps \
  --no-cache-dir /tmp/opi5-wheels/*.whl
rm -rf "$W"
chroot "$R" "$V/bin/python" -c 'import jellyfin_mpv_shim, jellyfin_apiclient_python, python_mpv_jsonipc, mpv, requests, PIL'
ln -sf "$V/bin/jellyfin-mpv-shim" "$R/usr/local/bin/jellyfin-mpv-shim"
pkg=$(chroot "$R" "$V/bin/python" -c 'import jellyfin_mpv_shim, os; print(os.path.dirname(jellyfin_mpv_shim.__file__))')
id=com.github.iwalton3.jellyfin-mpv-shim
install -Dm644 "$R$pkg/integration/$id.desktop" "$R/usr/local/share/applications/$id.desktop"
for s in 16 32 48 64 128 256; do
  install -Dm644 "$R$pkg/integration/jellyfin-$s.png" "$R/usr/local/share/icons/hicolor/${s}x$s/apps/$id.png"
done

# Google Chrome: VA-API decoding needs the render node named explicitly (Chrome only
# considers PCI GPUs; panthor is a platform device and the only render node here).
# The override is a copy of Chrome's launcher, made at image build time, with the
# flags added (it doesn't follow later changes to Chrome's own .desktop file);
# delete it to get Chrome's defaults.
CHROME_FLAGS="--ozone-platform=wayland --use-gl=angle --use-angle=gles --render-node-override=/dev/dri/renderD128 --enable-features=AcceleratedVideoDecodeLinuxGL"
if [ -f "$R/usr/share/applications/google-chrome.desktop" ]; then
  mkdir -p "$R/usr/local/share/applications"
  sed "s|^Exec=/usr/bin/google-chrome-stable|Exec=/usr/bin/google-chrome-stable $CHROME_FLAGS|" \
    "$R/usr/share/applications/google-chrome.desktop" > "$R/usr/local/share/applications/google-chrome.desktop"
  grep -q -- "--render-node-override" "$R/usr/local/share/applications/google-chrome.desktop"
fi

chroot "$R" systemctl set-default graphical.target
