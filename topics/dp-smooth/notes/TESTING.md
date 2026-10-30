# dp-smooth on-board tests (after reboot with updates/opi5-dp-smooth installed)

```sh
modinfo -n dw_dp typec_displayport        # both must point at updates/opi5-dp-smooth/
P=/sys/bus/typec/devices/port0-partner.0/displayport
aux() { sudo dd if=/dev/drm_dp_aux0 bs=1 count=2 skip=$((0x202)) 2>/dev/null | od -An -tx1; }
aux                                       # 77 00 = lanes 0/1 CR+EQ locked (2-lane dongle)
echo C | sudo tee $P/pin_assignment; sleep 3; aux; dmesg | grep -E 'dw-dp|Retrain' | tail
echo D | sudo tee $P/pin_assignment; sleep 3; aux; dmesg | grep -E 'dw-dp|Retrain' | tail
lsusb -t                                  # AX88179 may sit at 480M after the C step; cycle
                                          # /sys/bus/usb/devices/7-1:1.0/7-1-port3/disable 1→0 to get 5000M back
```
Pass: after each switch `aux` shows `77 00` again within ~1 s, and dmesg shows a
"full-training link: 2 lanes at 5400 MHz" (or fast-training) with no modeset. The picture comes back
by itself. Fail: `00 00` and a black screen (that is the old behaviour).

Smoothness (any kernel):
```sh
opi5-play ~/codecsweep/work/ref_h265_1920x1080_30.mkv dp     # visually smooth 30 fps
tools/flipmeasure.sh x 86 65 <clip> 8 skip-vsync=true; tools/cadence.py out/x.trace   # Δseq mostly 1
```
