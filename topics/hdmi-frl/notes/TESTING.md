# B6 HDMI 2.1 FRL — on-board test procedure

Needs: an HDMI 2.1 sink whose EDID HF-VSDB advertises Max_FRL_Rate >= 3 (6 Gbps × 3 lanes), plus
an Ultra High Speed (48G) HDMI cable on HDMI0. A full kernel build is required (DRM core changes):
scripts/build-kernel.sh with `patches/0300-001…121` added to `patches/linux/` (optionally the DT
`dt/0300-122`), then install the deb and reboot. Don't reload the display stack at runtime.

## 0. Before switching kernels (stock 7.3.0-opi5, read-only)
```sh
cat /sys/class/drm/card0-HDMI-A-1/status
edid-decode /sys/class/drm/card0-HDMI-A-1/edid | grep -iA20 'HDMI Forum'   # Max FRL Rate, SCDC Present
```
Pass: connected, and the HF-VSDB shows `Max FRL Rate: >= 3`. Otherwise FRL can't be tested (TMDS
regression only).

## 1. Boot / probe
```sh
dmesg | grep -iE 'hdmi|hdptx|vop2|scdc|frl' ; dmesg --level=err,warn
```
Pass: no new errors or warnings, and the connector still enumerates.

## 2. TMDS regression (do this first; lowest risk)
```sh
modetest -M rockchip -c | sed -n '/HDMI-A-1/,/props/p'
modetest -M rockchip -s <conn>@<crtc>:1920x1080@60
modetest -M rockchip -s <conn>@<crtc>:3840x2160@60     # 594 MHz, scrambled TMDS
cat /sys/kernel/debug/dri/0/HDMI-A-1/scdc_status 2>/dev/null || ls /sys/kernel/debug/dri/*/
speaker-test -D hw:<hdmi card>,0 -c2 -t sine -l1
```
Pass: picture on screen, SCDC shows scrambling enabled for 4K60, audio is heard.

## 3. FRL (one mode at a time; risk: a training failure falls back to TMDS or fails the modeset — a hard hang is unlikely but possible, so keep serial/SSH open)
```sh
modetest -M rockchip -s <conn>@<crtc>:3840x2160@120   # needs >= 4 lanes x 8G (~28.5 Gbps) with RGB 8bpc
modetest -M rockchip -s <conn>@<crtc>:3840x2160@100
dmesg | grep -iE 'frl|flt|ltp|ffe|train'
cat /sys/kernel/debug/dri/0/HDMI-A-1/scdc_status        # FRL rate, FLT ready, lane lock, Ch_Locked
kmscube -D /dev/dri/card0 (with the 4K120 mode active)
```
Pass: training completes at a rate of 4×8 or 4×10 Gbps (the source is capped at 10 G/lane), the
scdc_status shows FRL lanes locked and no character errors climbing, a stable picture with no
flicker, and no VOP2 POST_BUF_EMPTY errors in dmesg. Also check HDMI audio (in FRL mode, ACR uses the
FRL N/CTS helper).
Expected unavailable: 7680x4320@60. Mainline VOP2 limits VP0 to 4096×2304, so 8K modes are pruned.

## 4. Hot-plug / fallback
Unplug and replug 5×. Then use a non-2.1 sink or an HDMI 2.0 cable: training should fall back to a
lower rate or to TMDS with no oops.
