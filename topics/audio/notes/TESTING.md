# Audio tests on the Orange Pi 5 (after installing the DTB + module and rebooting)

Install (as root on the board):
```sh
cp rk3588s-orangepi-5-sata.dtb /usr/lib/linux-image-7.3.0-opi5/rockchip/   # from _out/audio/dtb
install -Dm644 dw-hdmi-qp.ko /lib/modules/7.3.0-opi5/updates/opi5-audio/dw-hdmi-qp.ko
depmod -a 7.3.0-opi5   # then reboot
```
Undo: restore `/var/tmp/rk3588s-orangepi-5-sata.dtb.orig` (or the K2 DTB), `rm -r updates/opi5-audio`, depmod, reboot.

## 1. Cards present
`cat /proc/asound/cards` -> `hdmi0`, `rockchipes8388`, **`dp0`**. `modinfo -n dw_hdmi_qp` ->
`updates/opi5-audio/...`. dmesg: no `asoc`/`spdif` probe errors.

## 2. Audible, as the normal user (`listen-test.sh all`)
Per output: spoken "Front Left" then "Front Right", then a 2 s 440 Hz tone (alsasink); at the end
an 880 Hz tone on the default device (autoaudiosink -> ALSA default = card 0 HDMI).
Pass: voice on the correct side and tone on each of TV (HDMI), Dell (DP; its headphone/line out),
headphones (jack plugged in). Fail: silence, wrong side, crackle.

## 3. HDMI FRL
The TV advertises FRL up to 4x12G (the driver caps at 4x10G) and VIC 118 (4K120).
1. With nothing else using the display: `modetest -M rockchip -s <HDMI conn id>@<crtc id>:3840x2160-120 &`
   (or weston `mode=3840x2160@120`), check `cat /sys/kernel/debug/dri/0/HDMI-A-1/scdc*`/dmesg for FRL
   rate, then `listen-test.sh hdmi`. Pass: audio as at 4K60.
2. Modeset while playing (patch 0002): start
   `gst-launch-1.0 audiotestsrc freq=440 volume=0.3 ! alsasink device=plughw:hdmi0` and switch
   4K60 (TMDS) -> 4K120 (FRL) -> 4K60 without stopping it. Pass: tone resumes after each switch.
   Without 0002 expected fail: no/garbled audio after the switch until the stream is restarted.

## 4. Jack switching (desktop / PipeWire)
`wpctl status`: with headphones out the "Headphone Jack" card is `off`, default sink HDMI. Plug in:
the "Headphone Jack" sink appears and becomes the default; unplug: back to HDMI.
