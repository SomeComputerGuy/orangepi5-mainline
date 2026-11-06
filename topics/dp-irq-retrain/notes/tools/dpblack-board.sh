#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# dp-silent-black: repeated dual-head modesets ON THE BOARD (login user, sudo for KMS and debugfs reads).
# Read-only apart from KMS commits and dynamic debug switches; never touches registers, Type-C roles or the
# DP monitor's power/input.
#   dpblack-board.sh <outdir> <iterations>
# Start: camera calibration (camcal.sh, retried up to 3x). Then <iterations> times, each its own kmsctl client like
# the camcal clients that showed the silent black (fbcon 4K/4K -> 1080p60 bars on HDMI-A-1 and DP-1):
#   commit, wait 8 s, camera verdict per head (DP re-checked after 4 s if not GOOD), DPCD 0x200-0x207, 0x600 and
#   0x2002-0x2005 read through the DP AUX chardev (AUX reads only), then the client exits (fbcon restore commit).
# Kernel log followed into kmsg-all.txt with markers "=== dpblack <n> start/end"; dynamic debug on for dw-dp,
# the rockchip dw-dp glue and the USB-C/DP PHY (Alt Mode Attention events show up as PHY mux "new mode").
# One row per iteration in iter.tsv (resumable: the rows there are skipped; STOP file = stop at the next iteration):
#   n  DP=<verdict>  DP2=<retest verdict or ->  HDMI=<verdict>  dpcd=<hex 0x200-0x207> pwr=<0x600> esi=<0x2002-0x2005>
#   err=<error lines in this iteration's kernel log>
set -u
O=$1; N=$2
T=/var/tmp/dpblack/tools TM=/var/tmp/testmatrix
export TM CAM_CAPS=image/jpeg,width=3840,height=2160 CAM_RGB=1280x720 CAL_DIR=$O/cal
mkdir -p "$O/it"; exec > >(tee -a "$O/board.log") 2>&1
say() { echo "[$(date +%T)] $*"; }
stopflag() { [ -e /var/tmp/dpblack/STOP ]; }
kms() { sudo env KMSCTL_PROBE=0 python3 -I $T/kmsctl.py "$@"; }
sudo dmesg -w >> "$O/kmsg-all.txt" 2>&1 &
KLOG=$!; KP=
trap 'sudo kill $KLOG 2>/dev/null; [ -n "$KP" ] && sudo kill $KP 2>/dev/null' EXIT
mark() { echo "=== $*" | sudo tee /dev/kmsg > /dev/null; sleep 0.2; }
ERRPAT='WARNING|BUG:|Oops|Call trace|failed to enable link|link training failed|clock recovery failed|channel equalization failed|Retrain link failed|giving up|POST_BUF_EMPTY|failed to enable video'

say "kernel $(uname -rv)"
[ -f $TM/lib/camcheck.py ] && [ -f $TM/lib/tv-input.sh ] || { say "NO TESTMATRIX: $TM/lib/camcheck.py or tv-input.sh missing"; exit 1; }
for c in /sys/class/drm/card*-DP-1; do
  [ "$(cat $c/status 2>/dev/null)" = connected ] || { say "DP-1 NOT CONNECTED ($c: $(cat $c/status 2>&1))"; exit 1; }
done
DDC=/sys/kernel/debug/dynamic_debug/control
for q in 'module dw_dp +pt' 'file dw_dp-rockchip.c +pt' 'file phy-rockchip-usbdp.c +pt'; do
  echo "$q" | sudo tee $DDC > /dev/null 2>&1 && say "dyndbg: $q" || say "dyndbg not available: $q"
done
echo 0 | sudo tee /sys/module/drm/parameters/debug > /dev/null

# DP-1's AUX chardev (name of the AUX channel = the dw-dp device)
AUX=
for a in /sys/class/drm_dp_aux_dev/drm_dp_aux*; do
  [ -e "$a" ] || continue
  grep -q 'fde50000.dp\|DP-1\|dp' "$a/name" 2>/dev/null && AUX=/dev/$(basename "$a") && say "DP AUX: $AUX ($(cat $a/name))"
done
[ -n "$AUX" ] || say "no DP AUX chardev: DPCD columns will be '-'"
dpcd() {  # dpcd -> "dpcd=<8 bytes 0x200> pwr=<0x600> esi=<4 bytes 0x2002>"
  [ -n "$AUX" ] || { echo "dpcd=- pwr=- esi=-"; return; }
  sudo python3 -I -c '
import os, sys
fd = os.open(sys.argv[1], os.O_RDONLY)
def rd(a, n):
    try:
        return os.pread(fd, n, a).hex()
    except OSError as e:
        return "err%d" % e.errno
print("dpcd=%s pwr=%s esi=%s" % (rd(0x200, 8), rd(0x600, 1), rd(0x2002, 4)))' "$AUX" 2>&1 | tail -1
}

sudo systemctl stop gdm 2>/dev/null; sudo pkill -x weston 2>/dev/null; sleep 2
sudo sh $TM/lib/tv-input.sh

# calibration (both screens must calibrate; a failed HDMI calibration = TV not on this input: switch and retry)
if [ -s "$CAL_DIR/calib-HDMI-A-1.json" ] && [ -s "$CAL_DIR/calib-DP-1.json" ] && [ -s "$O/iter.tsv" ]; then
  # resumed session: calibrate again anyway (lighting changes), keep the old one if that fails
  mkdir -p "$O/cal-old"; cp "$CAL_DIR"/calib-*.json "$O/cal-old/" 2>/dev/null
fi
for try in 1 2 3; do
  rm -f "$CAL_DIR"/calib-*.json
  sudo env TM=$TM bash $T/camcal.sh "$CAL_DIR" > "$O/cal-$try.log" 2>&1; tail -4 "$O/cal-$try.log"
  [ -s "$CAL_DIR/calib-HDMI-A-1.json" ] && [ -s "$CAL_DIR/calib-DP-1.json" ] && break
  say "calibration $try incomplete ($(ls $CAL_DIR/calib-*.json 2>/dev/null | xargs -n1 basename | tr '\n' ' ')), TV input again"
  sudo sh $TM/lib/tv-input.sh; sleep 10
done
if [ ! -s "$CAL_DIR/calib-DP-1.json" ] && [ -s "$O/cal-old/calib-DP-1.json" ]; then cp "$O/cal-old"/calib-*.json "$CAL_DIR/"; say "using the previous session's calibration"; fi
[ -s "$CAL_DIR/calib-DP-1.json" ] || say "DP CALIBRATION FAILED"
[ -s "$CAL_DIR/calib-HDMI-A-1.json" ] || say "HDMI CALIBRATION FAILED"
mark "dpblack calibration done"

modeof() { kms list 2>/dev/null | python3 -I -c '
import json,sys
d=json.load(sys.stdin)
for c in d["connectors"]:
    if c["name"]==sys.argv[1]:
        for i,m in enumerate(c["modes"]):
            if m["hdisplay"]==1920 and m["vdisplay"]==1080 and round(m.get("vrefresh",60))==60: print(i); sys.exit()
        print(0)' "$1"; }
MH=$(modeof HDMI-A-1); MD=$(modeof DP-1)
say "mode index HDMI-A-1=$MH DP-1=$MD"
vword() { grep -oE "^$1: [A-Z]+" | awk '{print $2}' | head -1; }

done_n=$(grep -c . "$O/iter.tsv" 2>/dev/null); done_n=${done_n:-0}
say "iterations done earlier: $done_n of $N"
for n in $(seq 1 "$N"); do
  stopflag && { say "STOP requested before iteration $n"; break; }
  grep -q "^$n	" "$O/iter.tsv" 2>/dev/null && continue
  d=$O/it/$n; mkdir -p "$d"
  mark "dpblack $n start"
  sudo env KMSCTL_PROBE=0 python3 -I $T/kmsctl.py show \
    --head "conn=HDMI-A-1,mode=$MH,pattern=bars,code=1365" --head "conn=DP-1,mode=$MD,pattern=bars,code=2730" \
    --hold 600 < <(sleep 600) > "$d/kms.json" 2>&1 &
  KP=$!
  sleep 8
  v=$(python3 -I $T/camverdict.py "$d/cam1" HDMI-A-1=1365 DP-1=2730 2>&1); echo "$v" > "$d/verdict1.txt"
  dp=$(vword DP-1 <<< "$v"); hd=$(vword HDMI-A-1 <<< "$v"); dc=$(dpcd)
  dp2=
  if [ "${dp:-none}" != GOOD ]; then
    sleep 4
    v2=$(python3 -I $T/camverdict.py "$d/cam2" HDMI-A-1=1365 DP-1=2730 2>&1); echo "$v2" > "$d/verdict2.txt"
    dp2=$(vword DP-1 <<< "$v2"); dp2=${dp2:-none}; dc="$dc | $(dpcd)"
  fi
  ok=$(grep -c '"ok": true' "$d/kms.json")
  sudo kill $KP 2>/dev/null; wait $KP 2>/dev/null; KP=
  sleep 3   # the client's exit (fbcon restore commit) belongs to this iteration
  mark "dpblack $n end"
  sleep 0.5
  awk -v a="=== dpblack $n start" -v b="=== dpblack $n end" 'index($0, a) {p=1} p; index($0, b) {exit}' "$O/kmsg-all.txt" > "$d/kmsg.txt"
  err=$(grep -cE "$ERRPAT" "$d/kmsg.txt")
  # keep the camera frames of non-GOOD iterations and of every 10th one
  if [ "${dp:-none}" = GOOD ] && [ "${hd:-none}" = GOOD ] && [ $((n % 10)) != 0 ]; then rm -f "$d"/cam*.jpg; fi
  rm -f "$d"/cam*.rgb
  printf '%s\tDP=%s\tDP2=%s\tHDMI=%s\tcommit=%s\t%s\terr=%s\n' "$n" "${dp:-none}" "${dp2:--}" "${hd:-none}" "$ok" "$dc" "$err" >> "$O/iter.tsv"
  say "iteration $n: DP $dp${dp2:+ / $dp2} HDMI $hd commit_ok=$ok $dc err=$err"
done
for q in 'module dw_dp -p' 'file dw_dp-rockchip.c -p' 'file phy-rockchip-usbdp.c -p'; do echo "$q" | sudo tee $DDC > /dev/null 2>&1; done
say "done: $(grep -c . "$O/iter.tsv" 2>/dev/null) of $N iterations"
sudo dmesg | grep -cE 'WARNING|BUG:|Oops' | sed 's/^/total warnings: /'
