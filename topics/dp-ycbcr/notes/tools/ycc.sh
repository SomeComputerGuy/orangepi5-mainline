#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# ycc.sh <dev|test> <kernel: stock | pkgrev e.g. 15ycc1> <unit>...   (host side, DP colour-format work)
#   unit = probe:<tag>   read-only DP colour-format probe (kmsctl commits, drm.debug KMS|ATOMIC, vop2 summary)
#        | list:<name>   lists/<name>.tsv run by fmtck.py in chunks of $CHUNK cases
# Pausable + resumable: every finished chunk is copied to the host at once (run-<kernel>-<chunk>/, fixed names);
# finished chunks/probes are skipped on restart and a partly done chunk is pushed back so fmtck resumes it.
# Between units: BOARD-PAUSE -> hold position with the lock (no restore/reboot) until it is gone; test mode:
# BOARD-WANT/ non-empty -> restore stock 15, release BOARD-LOCK, wait until clear and resume. dev mode: short holds; writes
# BOARD-WANT/dp-ycc while waiting for the lock and honours only BOARD-PAUSE.
set -u
MODE=$1 KREV=$2; shift 2; UNITS=("$@")
TOP=$HOME/orangepi5; W=$TOP/work/_out; D=$W/k15/dp-ycc; LOG=$D/ycc.log
S=$(cat ~/.claude/jobs/35761d63/tmp/ssh.cmd); ME="dp-ycc $$"; CHUNK=${CHUNK:-15}
STOCK_V="#16 SMP PREEMPT_DYNAMIC Sat Nov  7 04:32:10"
if [ "$KREV" = stock ]; then KT=$STOCK_V; KTAG=stock15; else KT="#$KREV SMP"; KTAG=$KREV; KDIR=$TOP/out/test/k$KREV/debs; fi
log() { echo "[$(date +%T)] $*" | tee -a $LOG; }
want() { [ -n "$(ls -A $W/BOARD-WANT 2>/dev/null | grep -vx dp-ycc)" ]; }
paused() { [ -e $W/BOARD-PAUSE ]; }
must_yield() { paused || { [ $MODE = test ] && want; }; }
up() { for i in $(seq 1 60); do timeout 10 $S true 2>/dev/null && return 0; sleep 10; done; return 1; }
dpkg_idle() { until ! $S 'sudo fuser /var/lib/dpkg/lock-frontend' >/dev/null 2>&1; do sleep 10; done; }
HELD=0 CHANGED=0

# ---- work units -> chunk list; done markers live on the host
mkdir -p $D/lists/chunks
WORK=()
for u in "${UNITS[@]}"; do
  case $u in
    probe:*) WORK+=("$u");;
    list:*) n=${u#list:}; rm -f $D/lists/chunks/$n.c*.tsv
            split -d -l $CHUNK --additional-suffix=.tsv $D/lists/$n.tsv $D/lists/chunks/$n.c
            for f in $D/lists/chunks/$n.c*.tsv; do WORK+=("chunk:$(basename $f .tsv)"); done;;
  esac
done
is_done() {  # unit
  case $1 in
    probe:*) [ -f $D/probe-${1#probe:}/done ];;
    chunk:*) local c=${1#chunk:} r=$D/run-$KTAG-${1#chunk:}
             [ -f $r/done ] || { [ -f $r/fmt.tsv ] && [ $(($(wc -l < $r/fmt.tsv)-1)) -ge $(wc -l < $D/lists/chunks/$c.tsv) ]; };;
  esac
}
pending() { for u in "${WORK[@]}"; do is_done "$u" || echo "$u"; done; }

# ---- lock handling
take_lock() {
  [ $MODE = dev ] && mkdir -p $W/BOARD-WANT && echo "dp-ycc: DP colour-format dev check ($KTAG)" > $W/BOARD-WANT/dp-ycc
  # dev: queue behind every other BOARD-WANT older than ours; test: wait until BOARD-WANT/ is empty
  until ! paused && { [ $MODE = dev ] && [ -z "$(find $W/BOARD-WANT -maxdepth 1 -type f ! -name dp-ycc ! -newer $W/BOARD-WANT/dp-ycc 2>/dev/null)" ] || \
        { [ $MODE = test ] && ! want; }; } && (set -C; echo "$ME" > "$W/BOARD-LOCK") 2>/dev/null; do sleep 120; done
  rm -f $W/BOARD-WANT/dp-ycc; HELD=1; log "lock taken ($ME, $MODE $KTAG)"
}
restore() {
  log "restore stock 15"
  NOLOCK=1 bash $W/k14/install-check.sh >> $LOG 2>&1
  log "restore rc=$?: $(head -1 $W/k14/boot.txt) $(grep usb_missing $W/k14/boot.txt)"
  grep -q "$STOCK_V" $W/k14/boot.txt || log "WARNING: stock 15 not confirmed after restore"
  CHANGED=0
}
release() {
  [ $HELD = 1 ] || return 0
  $S 'echo 0 | sudo tee /sys/module/drm/parameters/debug >/dev/null' >/dev/null 2>&1
  [ $CHANGED = 1 ] && restore
  $S 'sudo systemctl start gdm' >/dev/null 2>&1
  grep -q "^$ME" "$W/BOARD-LOCK" 2>/dev/null && rm -f "$W/BOARD-LOCK"
  HELD=0; log "lock released"
}
trap 'release; rm -f $W/BOARD-WANT/dp-ycc' EXIT

# ---- per hold: right kernel, tools on the board, display stack stopped, mode lists unchanged
setup() {
  up || { log "board unreachable"; return 1; }
  local K; K=$($S 'uname -v')
  if [[ "$K" != *"$KT"* ]]; then
    [ "$KREV" = stock ] && { log "running '$K', not stock 15"; return 1; }
    log "install $KREV from $KDIR"
    $S "mkdir -p /var/tmp/fmtk && rm -f /var/tmp/fmtk/*.deb" || return 1
    for d in image headers; do $S "cat > /var/tmp/fmtk/$d.deb" < $KDIR/linux-$d-7.3.0-opi5_7.3.0-${KREV}_arm64.deb || return 1; done
    dpkg_idle; CHANGED=1
    $S 'sudo dpkg -i /var/tmp/fmtk/image.deb /var/tmp/fmtk/headers.deb >/dev/null 2>&1; echo dpkg=$?' | tee -a $LOG
    dpkg_idle
    $S 'sudo systemctl reboot' 2>/dev/null; sleep 60; up || { log "no ssh after reboot"; return 1; }
    sleep 20
    $S 'uname -rv; echo warn=$(sudo dmesg | grep -cE "WARNING|BUG:|Oops"); sudo dmesg | grep -E "WARNING|BUG:|Oops" | head -3;
        lsusb | awk "{print \$6}" | grep -v "^1d6b:" | sort > /tmp/usb-now.txt; echo "usb_missing=$(comm -23 /var/tmp/usb-expected.txt /tmp/usb-now.txt | tr "\n" " ")";
        for c in /sys/class/drm/card*-*; do echo "$(basename $c) $(cat $c/status)"; done' | tee -a $LOG
    K=$($S 'uname -v'); [[ "$K" == *"$KT"* ]] || { log "kernel after install is '$K'"; return 1; }
  fi
  log "kernel: $K"
  tar -C $D -cf - tools lists | $S 'sudo rm -rf /var/tmp/ycc/tools /var/tmp/ycc/lists; mkdir -p /var/tmp/ycc && tar -C /var/tmp/ycc -xf -' || return 1
  $S "sudo systemctl stop gdm; sudo pkill -x weston; sleep 2; sudo sh /var/tmp/testmatrix/lib/tv-input.sh; \
      sudo python3 -I /var/tmp/ycc/tools/kmsctl.py list > /var/tmp/ycc/list-$KTAG.json" >> $LOG 2>&1
  $S "cat /var/tmp/ycc/list-$KTAG.json" > $D/list-$KTAG.json
  python3 -I - $D/list-$KTAG.json $W/k12/dualmatrix/kms-list.json $D/lists/dp-modes.json <<'P' || { log "HDMI or DP-1 mode list differs (DP not attached?)"; return 3; }
import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:3]); dp = [tuple(x) for x in json.load(open(sys.argv[3]))]
m = lambda d, n: [(x["name"], x["clock"], x["htotal"], x["vtotal"], x["flags"]) for x in next(c for c in d["connectors"] if c["name"] == n)["modes"]]
sys.exit(0 if m(a, "HDMI-A-1") == m(b, "HDMI-A-1") and m(a, "DP-1") == dp else 1)
P
}

run_probe() {  # tag
  local P=$D/probe-$1; mkdir -p $P; log "probe $1"
  $S 'uname -rv' > $P/uname.txt
  for mode in 0 5; do for bpc in 8 10; do for cf in "AUTO" "RGB" "YUV 4:4:4" "YUV 4:2:2" "YUV 4:2:0"; do
    t="m${mode}_${bpc}_${cf//[ :]/}"; [ -s $P/$t.txt ] && continue
    $S "sudo dmesg -C; echo 0x14 | sudo tee /sys/module/drm/parameters/debug >/dev/null; cd /var/tmp/ycc; \
        (sudo timeout 20 python3 -I tools/kmsctl.py show --hold 4 \
          --head 'conn=DP-1,mode=$mode,prop:max bpc=$bpc,prop:color format=$cf,plane=65,fmt=XR24,mod=linear' 2>&1 | head -3) & \
        sleep 3; echo '== vop2'; sudo sh -c 'cat /sys/kernel/debug/dri/*/vop2/summary' 2>/dev/null | grep -E 'Video Port|Connector|bus_format|output_mode|Display mode' ; wait; \
        echo 0 | sudo tee /sys/module/drm/parameters/debug >/dev/null; echo '== dmesg'; \
        sudo dmesg | grep -E 'bus format|Bridge atomic|bus format chain|Skipping' | head -20" > $P/$t.txt.tmp 2>&1 && mv $P/$t.txt.tmp $P/$t.txt
  done; done; done
  touch $P/done
}

run_chunk() {  # chunk name, e.g. dp_00.c03
  local c=$1 R=run-$KTAG-$1 conn=DP-1 n last="" idle=0 st
  case $c in sane.*) conn=HDMI-A-1;; esac
  n=$(wc -l < $D/lists/chunks/$c.tsv); log "chunk $c ($n cases, $conn)"
  # push a partial host copy back so fmtck resumes it
  $S "sudo rm -rf /var/tmp/ycc/$R /var/tmp/ycc/$R.done"
  [ -d $D/$R ] && tar -C $D -cf - $R | $S "sudo tar -C /var/tmp/ycc -xf -"
  $S "cd /var/tmp/ycc && (sudo -E env CONN=$conn CAM_RGB=1280x720 CAL_DIR=/var/tmp/tm/cam2 TM=/var/tmp/testmatrix timeout -s TERM $((n*90)) \
       python3 -I tools/fmtck.py $R lists/chunks/$c.tsv > $R.log 2>&1; sudo touch $R.done) > /dev/null 2>&1 & true"
  while :; do
    sleep 30
    st=$($S "[ -e /var/tmp/ycc/$R.done ] && echo done || echo run; wc -l < /var/tmp/ycc/$R/fmt.tsv 2>/dev/null" 2>/dev/null)
    if [ -z "$st" ]; then idle=$((idle+30)); [ $idle -ge 600 ] && { log "board unreachable 10 min"; return 1; }; continue; fi
    [ "$(echo "$st" | sed -n 2p)" = "$last" ] && idle=$((idle+30)) || { idle=0; last=$(echo "$st" | sed -n 2p); }
    [ "$(echo "$st" | head -1)" = done ] && break
    [ $idle -ge 300 ] && { log "STALL: no new case in 5 min, stopping fmtck"; $S "sudo pkill -TERM -x timeout"; sleep 10; break; }
  done
  $S "sudo tar -C /var/tmp/ycc -cf - $R $R.log" | tar -C $D -xf - && log "copied $R ($(($(wc -l < $D/$R/fmt.tsv)-1))/$n)"
  $S 'sudo dmesg' > $D/$R/dmesg-end.txt 2>/dev/null
  local a=$(( $(cat $D/$R/attempts 2>/dev/null || echo 0) + 1 )); echo $a > $D/$R/attempts
  if ! is_done chunk:$c && [ $a -ge 2 ]; then log "chunk $c incomplete after $a attempts, giving up on the rest"; touch $D/$R/done; fi
  if [ $c = sane.c00 ] && awk -F'\t' 'NR>1 && $17 !~ /^GOOD/ {bad=1} END {exit !bad}' $D/$R/fmt.tsv; then
    log "SANITY FAIL (camera/calib?): $(cut -f2,17 $D/$R/fmt.tsv | tail -n +2 | tr '\n' ' ')"; return 4
  fi
}

# ---- main loop: hold, work until done or yield, release, wait, repeat
log "start $MODE $KTAG: ${UNITS[*]}"
while [ -n "$(pending)" ]; do
  take_lock
  setup; rc=$?
  if [ $rc != 0 ]; then log "setup failed rc=$rc, stopping"; exit $rc; fi
  for u in $(pending); do
    # BOARD-PAUSE (coordinator/user using the board): hold position, keep the lock, no restore, no reboot
    if paused; then log "paused by BOARD-PAUSE, holding the lock"; while paused; do sleep 30; done; log "pause cleared"; fi
    if must_yield; then log "yield: BOARD-WANT=[$(ls $W/BOARD-WANT 2>/dev/null | tr '\n' ' ')] PAUSE=$([ -e $W/BOARD-PAUSE ] && echo y || echo n)"; break; fi
    case $u in
      probe:*) run_probe ${u#probe:};;
      chunk:*) run_chunk ${u#chunk:} || { r=$?; log "chunk failed rc=$r, stopping"; exit $r; };;
    esac
  done
  release
done
log "all units done ($MODE $KTAG)"
