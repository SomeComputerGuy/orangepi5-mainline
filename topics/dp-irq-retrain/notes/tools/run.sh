#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# dp-silent-black board session (copy of k15/vop2-splice/tools/run.sh, adapted): take BOARD-LOCK, install the
# 7.3.0-$KREV kernel (whole debs, dpkg -i; KREV=15 KDIR=out/debs = stock baseline), boot check, run
# tools/dpblack-board.sh as board systemd unit dpblack-run under a stall watchdog, copy results off every 30 s,
# restore stock 7.3.0-15 (k14/install-check.sh, NOLOCK=1) and check uname -v before the lock is released (every
# exit path).
#   KREV=15dpirq1 KDIR=out/test/dpirq/debs TAG=F1 ITER=60 run.sh
# TEST run: writes no BOARD-WANT file, takes the free lock only while BOARD-WANT/ is empty and BOARD-PAUSE is
# absent, and stops at the next iteration when a BOARD-WANT file or BOARD-PAUSE appears (exit 10 = paused,
# rerun to resume: the finished iterations are skipped). Exit 0 = session ended (complete or not, see iter.tsv),
# 1/3 = failure (install, boot check, unreachable). RUN_TIMEOUT=<s> board-session timeout (default 3600).
set -u
TOP=$HOME/orangepi5; W=$TOP/work/_out; O=$W/k15/dp-silent-black; S=$(cat ~/.claude/jobs/35761d63/tmp/ssh.cmd)
LOCK=$W/BOARD-LOCK; ME="dp-silent-black $$";
KREV=${KREV:?} KDIR=${KDIR:?} TAG=${TAG:-$KREV}; ITER=${ITER:-60}
R=$O/run-$TAG; mkdir -p "$R"
log() { echo "[$(date +%T)] $*" | tee -a "$R/host.log"; }

restore15() {
	NOLOCK=1 bash $W/k14/install-check.sh > "$R/restore15.log" 2>&1; log "install-check.sh rc=$?"
	cp $W/k14/boot.txt "$R/boot-15.txt" 2>/dev/null
	grep -q "^7.3.0-opi5 #15 SMP.*Wed Nov  4 20:25:22" "$R/boot-15.txt" && grep -q "^warn=0$" "$R/boot-15.txt" &&
		grep -q "^usb_missing=$" "$R/boot-15.txt" || { log "BOOT CHECK FAILED (stock 15)"; return 3; }
}
release() {
	[ "$(cat "$LOCK" 2>/dev/null)" = "$ME" ] || return
	timeout 900 $S 'while systemctl list-units --no-legend "dpblack-*" | grep -q . || sudo -n fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 5; done' 2>/dev/null
	if ! timeout 15 $S 'uname -v' 2>/dev/null | grep -q '^#15 SMP.*Wed Nov  *4 20:25:22'; then
		log "restoring stock 15 before releasing the lock"
		restore15 || { log "RESTORE FAILED: keeping BOARD-LOCK, board needs attention"; return; }
	fi
	log "uname -v: $(timeout 15 $S 'uname -v' 2>/dev/null)"
	rm -f "$LOCK"; log "lock released"
}

# TEST run: never writes a BOARD-WANT file; takes the free lock only while BOARD-WANT/ is empty and no BOARD-PAUSE
TESTRUN=1; PAUSED=0
log "TEST run: waiting for a free lock and an empty BOARD-WANT/"
while :; do
	if [ -z "$(ls -A $W/BOARD-WANT 2>/dev/null)" ] && [ ! -e "$W/BOARD-PAUSE" ] && [ ! -e "$LOCK" ] &&
		(set -C; echo "$ME" > "$LOCK") 2>/dev/null; then break; fi
	sleep 60
done
trap release EXIT
log "board lock taken ($ME)"
timeout 15 $S true || { log "board unreachable"; exit 1; }

# install + boot check (install-check.sh logic, on the test debs)
d=$TOP/$KDIR
$S "cat > /var/tmp/usb-expected.txt" < $W/k14/usb-expected.txt
$S "mkdir -p /var/tmp/dpblack/debs && rm -f /var/tmp/dpblack/debs/*.deb" || exit 1
for p in image headers; do $S "cat > /var/tmp/dpblack/debs/$p.deb" < $d/linux-$p-7.3.0-opi5_7.3.0-${KREV}_arm64.deb || exit 1; done
timeout 900 $S 'while sudo -n fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 5; done'
log "installing $KREV: $(timeout 900 $S 'sudo -n dpkg -i /var/tmp/dpblack/debs/image.deb /var/tmp/dpblack/debs/headers.deb >/dev/null 2>&1; echo dpkg=$?; true')"
timeout 900 $S 'while sudo -n fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 5; done; dpkg -l linux-image-7.3.0-opi5 | tail -1; stat -c "initrd=%s" /boot/initrd.img-7.3.0-opi5' > "$R/dpkg.txt"
grep -q "^ii  linux-image-7.3.0-opi5 *7.3.0-$KREV " "$R/dpkg.txt" && ! grep -q "^initrd=0$" "$R/dpkg.txt" || { log "INSTALL FAILED: $(cat $R/dpkg.txt)"; exit 3; }
timeout 20 $S 'sudo -n systemctl reboot' 2>/dev/null; sleep 60
for i in $(seq 1 30); do timeout 8 $S true 2>/dev/null && break; sleep 10; done
timeout 120 $S 'for i in $(seq 1 18); do lsusb | awk "{print \$6}" | sort > /tmp/u.txt; [ -z "$(comm -23 /var/tmp/usb-expected.txt /tmp/u.txt)" ] && break; sleep 5; done'
timeout 120 $S 'set +e; uname -rv; echo "warn=$(sudo dmesg | grep -cE "WARNING|BUG:|Oops|Call trace")"
sudo dmesg | grep -E "WARNING|BUG:|Oops" | head -5
lsusb | awk "{print \$6}" | grep -v "^1d6b:" | sort > /tmp/usb-now.txt
echo "usb_missing=$(comm -23 /var/tmp/usb-expected.txt /tmp/usb-now.txt | tr "\n" " ")"
for c in /sys/class/drm/card*-*; do echo "$(basename $c) $(cat $c/status)"; done
echo "failed_units=$(systemctl --failed --no-legend | wc -l)"' > "$R/boot-$KREV.txt"
cat "$R/boot-$KREV.txt" >> "$R/host.log"
grep -q "^7.3.0-opi5 #$KREV " "$R/boot-$KREV.txt" || { log "BOOT CHECK FAILED: not running #$KREV"; exit 3; }
grep -q "^usb_missing=$" "$R/boot-$KREV.txt" || { log "BOOT CHECK FAILED: USB devices missing"; exit 3; }
grep -q "^warn=0$" "$R/boot-$KREV.txt" || { log "BOOT CHECK FAILED: kernel warnings"; exit 3; }

# tools; resume: the rows of the finished iterations and the calibration go back to the board, and the earlier
# session's kernel log is kept under its own name (the board starts a new kmsg-all.txt)
$S "sudo -n rm -rf /var/tmp/dpblack/tools /var/tmp/dpblack/STOP /var/tmp/dpblack/out; mkdir -p /var/tmp/dpblack/tools /var/tmp/dpblack/out" || exit 1
for f in dpblack-board.sh kmsctl.py camverdict.py camcal.sh; do $S "cat > /var/tmp/dpblack/tools/$f" < $O/tools/$f || exit 1; done
if [ -s "$R/out/iter.tsv" ]; then
	$S "cat > /var/tmp/dpblack/out/iter.tsv" < "$R/out/iter.tsv" && log "resuming after $(grep -c . $R/out/iter.tsv) iterations"
	[ -d "$R/out/cal" ] && tar -C "$R/out" -cf - cal | $S "tar -C /var/tmp/dpblack/out -xf -"
fi
for f in kmsg-all board; do
	if [ -s "$R/out/$f.txt" ] || [ -s "$R/out/$f.log" ]; then
		k=1; while [ -e "$R/out/$f-s$k.txt" ] || [ -e "$R/out/$f-s$k.log" ]; do k=$((k + 1)); done
		[ -s "$R/out/$f.txt" ] && mv "$R/out/$f.txt" "$R/out/$f-s$k.txt"
		[ -s "$R/out/$f.log" ] && mv "$R/out/$f.log" "$R/out/$f-s$k.log"
		log "earlier $f kept as session $k"
	fi
done

$S "sudo -n systemctl reset-failed dpblack-run 2>/dev/null; sudo -n systemd-run --unit=dpblack-run --collect --uid=$(timeout 10 $S id -u) -p WorkingDirectory=/var/tmp/dpblack bash /var/tmp/dpblack/tools/dpblack-board.sh /var/tmp/dpblack/out $ITER" 2>&1 | tail -1 | tee -a "$R/host.log"
t0=$(date +%s); last=""; lastchange=$t0
while :; do
	sleep 30
	st=$(timeout 15 $S "systemctl is-active dpblack-run" 2>/dev/null)
	mkdir -p "$R/out"; timeout 300 $S "tar -C /var/tmp/dpblack/out -cf - ." 2>/dev/null | tar -C "$R/out" -xf - 2>/dev/null
	[ -e "$W/BOARD-PAUSE" ] && [ $PAUSED = 0 ] && timeout 15 $S "touch /var/tmp/dpblack/STOP" 2>/dev/null && PAUSED=1 && log "BOARD-PAUSE: stopping at the next iteration"
	if [ "$TESTRUN" = 1 ] && [ $PAUSED = 0 ] && [ -n "$(ls -A $W/BOARD-WANT 2>/dev/null)" ]; then
		timeout 15 $S "touch /var/tmp/dpblack/STOP" 2>/dev/null && PAUSED=1 &&
			log "BOARD-WANT: $(ls $W/BOARD-WANT | tr '\n' ' ')- pausing at the next case"
	fi
	[ "$st" = active ] || [ "$st" = activating ] || break
	m=$(stat -c %Y "$R/out/board.log" 2>/dev/null)
	if [ -n "$m" ] && [ "$m" != "$last" ]; then last=$m; lastchange=$(date +%s); fi
	if [ $(( $(date +%s) - lastchange )) -gt 420 ]; then log "STALL: no board progress for 7 min, stopping the unit"; timeout 30 $S "sudo -n systemctl stop dpblack-run"; break; fi
	if [ $(( $(date +%s) - t0 )) -gt ${RUN_TIMEOUT:-3600} ]; then log "TIMEOUT"; timeout 30 $S "sudo -n systemctl stop dpblack-run"; break; fi
done
timeout 300 $S "tar -C /var/tmp/dpblack/out -cf - ." | tar -C "$R/out" -xf - && log "results copied to $R/out ($(grep -c . $R/out/iter.tsv 2>/dev/null) iterations)"
timeout 30 $S "sudo -n dmesg" > "$R/dmesg-end.txt" 2>/dev/null
log "unit: $(timeout 15 $S 'systemctl show -p Result dpblack-run' 2>/dev/null)"
[ -e "$W/BOARD-PAUSE" ] && PAUSED=1
[ $PAUSED = 1 ] && { log "PAUSED: rerun to resume"; exit 10; }
exit 0
