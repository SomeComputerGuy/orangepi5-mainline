#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# rga-fu DEV board session (copy of k15/rga3-nv15/tools/run.sh with its own names and paths).
#  1. host: inputs (prep-fu.py: symlinks to the rga3-nv15 inputs + NV20 picture), take BOARD-LOCK (BOARD-WANT/rga-fu while waiting, first come
#     first served, honours BOARD-PAUSE);
#  2. session "stock" on the stock 7.3.0-15 kernel (baseline): board.sh stock info compliance regress cases;
#  3. install 7.3.0-$KREV (whole debs, dpkg -i), reboot, boot check; session "test": the same phases;
#  4. copy results after every poll, restore stock 15 (k14/install-check.sh, NOLOCK=1), check uname -v,
#     release the lock (every exit path).
# Board steps run as systemd unit rgafu-run with a stall watchdog (no new output for 8 min) and a 60 min limit.
# BOARD-PAUSE: the board script stops at the next case/phase; results are kept; rerunning the command resumes
# (finished phases/cases are skipped, a finished stock session isn't repeated).
#   KREV=15rgafu1 KDIR=out/test/rgafu/debs TAG=fu1 STOCK=0 PH="info compliance regress cases" run.sh
# Optional: STOCK=0 skips the stock-15 baseline session; PH="info compliance cases" picks the phases;
# CASES=<file in tools/> is pushed as the case list (default cases.txt).
set -u
TOP=$HOME/orangepi5; W=$TOP/work/_out; O=$W/k15/rga-fu; S=$(cat ~/.claude/jobs/35761d63/tmp/ssh.cmd)
LOCK=$W/BOARD-LOCK; ME="rga-fu $$"; WANT=$W/BOARD-WANT/rga-fu
KREV=${KREV:?} KDIR=${KDIR:?} TAG=${TAG:-$KREV} STOCK=${STOCK:-1} CASES=${CASES:-cases.txt}
R=$O/run-$TAG; mkdir -p "$R/out"; BT=/var/tmp/rgafu
log() { echo "[$(date +%T)] $*" | tee -a "$R/host.log"; }

restore15() {
	NOLOCK=1 bash $W/k14/install-check.sh > "$R/restore15.log" 2>&1; log "install-check.sh rc=$?"
	cp $W/k14/boot.txt "$R/boot-15.txt" 2>/dev/null
	grep -q "^7.3.0-opi5 #16 SMP.*Sat Nov  7 04:32:10" "$R/boot-15.txt" && grep -q "^warn=0$" "$R/boot-15.txt" &&
		grep -q "^usb_missing=$" "$R/boot-15.txt" || { log "BOOT CHECK FAILED (stock 15)"; return 3; }
}
release() {
	rm -f "$WANT"
	[ "$(cat "$LOCK" 2>/dev/null)" = "$ME" ] || return
	timeout 900 $S 'while systemctl list-units --no-legend "rgafu-*" | grep -q . || sudo -n fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 5; done' 2>/dev/null
	if ! timeout 15 $S 'uname -v' 2>/dev/null | grep -q '^#16 SMP.*Sat Nov  *7 04:32:10'; then
		log "restoring stock 15 before releasing the lock"
		restore15 || { log "RESTORE FAILED: keeping BOARD-LOCK, board needs attention"; return; }
	fi
	log "uname -v: $(timeout 15 $S 'uname -v' 2>/dev/null)"
	rm -f "$LOCK"; log "lock released"
}
copyback() { timeout 300 $S "tar -C $BT/out -cf - ." 2>/dev/null | tar -C "$R/out" -xf - 2>/dev/null; }

# board session: runs board.sh TAG phases as a unit; returns 0 when ALLDONE, 10 when paused, 1 otherwise
session() {
	local tag=$1; shift
	$S "sudo -n rm -f $BT/STOP; sudo -n systemctl reset-failed rgafu-run 2>/dev/null; sudo -n systemd-run --unit=rgafu-run --collect --uid=$(timeout 10 $S id -u) -p WorkingDirectory=$BT bash $BT/tools/board.sh $tag $*" 2>&1 | tail -1 | tee -a "$R/host.log"
	local t0=$(date +%s) last="" lastchange=$(date +%s) st m
	while :; do
		sleep 30
		st=$(timeout 15 $S "systemctl is-active rgafu-run" 2>/dev/null)
		copyback
		[ -e "$W/BOARD-PAUSE" ] && timeout 15 $S "touch $BT/STOP" 2>/dev/null && log "BOARD-PAUSE: stopping at the next case"
		[ "$st" = active ] || [ "$st" = activating ] || break
		m=$(timeout 15 $S "find $BT/out /var/tmp/rga3 -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1")
		if [ -n "$m" ] && [ "$m" != "$last" ]; then last=$m; lastchange=$(date +%s); fi
		if [ $(( $(date +%s) - lastchange )) -gt 480 ]; then log "STALL: no board progress for 8 min, stopping the unit"; timeout 30 $S "sudo -n systemctl stop rgafu-run"; break; fi
		if [ $(( $(date +%s) - t0 )) -gt 3600 ]; then log "TIMEOUT"; timeout 30 $S "sudo -n systemctl stop rgafu-run"; break; fi
	done
	copyback; log "session $tag: unit $(timeout 15 $S 'systemctl show -p Result rgafu-run' 2>/dev/null)"
	grep -q "^ALLDONE $tag" "$R/out/board.log" 2>/dev/null && return 0
	tail -1 "$R/out/board.log" 2>/dev/null | grep -q "STOP: pausing" && return 10
	return 1
}

# inputs and references on the host first (no board needed)
python3 -I $O/tools/prep-fu.py $O/inputs $W/k15/rga3-nv15/inputs >> "$R/host.log" 2>&1 || { log "PREP FAILED"; exit 1; }
[ -s $O/tools/rga-xtest ] || { log "missing tools/rga-xtest"; exit 1; }

# DEV turn, first come first served
[ -e "$WANT" ] || echo "rga-fu: DEV turn, RGA follow-up fixes test kernel $KREV (~20-30 min)" > "$WANT"
log "BOARD-WANT written, queue: $(ls -tr $W/BOARD-WANT | tr '\n' ' ')"
while :; do
	older=$(find $W/BOARD-WANT -maxdepth 1 -type f ! -name rga-fu ! -newer "$WANT" | head -1)
	if [ -z "$older" ] && [ ! -e "$W/BOARD-PAUSE" ] && [ ! -e "$LOCK" ] && (set -C; echo "$ME" > "$LOCK") 2>/dev/null; then break; fi
	sleep 60
done
rm -f "$WANT"
trap release EXIT
log "board lock taken ($ME)"
timeout 15 $S true || { log "board unreachable"; exit 1; }

# tools, inputs (once) and the results of an earlier, paused run
push_tools() {
	# a fresh run (nothing copied back yet) must not see an earlier run's results on the board
	if [ -z "$(ls -A "$R/out" 2>/dev/null)" ]; then $S "rm -rf $BT/out" || return 1; fi
	$S "mkdir -p $BT/tools $BT/inputs $BT/out" || return 1
	for f in board.sh rga-xtest; do $S "cat > $BT/tools/$f" < $O/tools/$f || return 1; done
	$S "cat > $BT/tools/cases.txt" < $O/tools/$CASES || return 1
	$S "cat > $BT/tools/rga2-regress-board.sh" < $W/k14/datasheet/d2/rga2-regress-board.sh || return 1
	$S "cat > $BT/tools/rga-test" < $W/k12/rga3/tools/rga-test || return 1
	$S "cat > $BT/tools/board-tests.sh" < $W/k12/rga3/board-tests.sh || return 1
	$S "chmod +x $BT/tools/*" || return 1
	if ! timeout 15 $S "test -e $BT/inputs/PREP-DONE"; then
		(cd $O/inputs && tar -chf - --exclude='src*.yuv' --exclude='*.yuv10' --exclude='*.mkv' --exclude='*.webm' --exclude=PREP-DONE .) |
			timeout 900 $S "tar -C $BT/inputs -xf -" && timeout 15 $S "touch $BT/inputs/PREP-DONE" || return 1
	fi
	[ -n "$(ls -A "$R/out" 2>/dev/null)" ] && tar -C "$R/out" -cf - . | $S "tar -C $BT/out -xf -" && log "pushed earlier results back (resume)"
	true
}

PH=${PH:-info compliance regress cases}
# 1) baseline on stock 15
if [ "$STOCK" = 1 ] && ! grep -q "^ALLDONE stock" "$R/out/board.log" 2>/dev/null; then
	if ! timeout 15 $S 'uname -v' | grep -q '^#16 SMP.*Sat Nov  *7 04:32:10'; then log "board not on stock 15, installing it"; restore15 || exit 3; fi
	push_tools || { log "PUSH FAILED"; exit 1; }
	log "session stock (uname -v: $(timeout 15 $S 'uname -v'))"
	session stock $PH; rc=$?
	[ $rc = 10 ] && { log "BOARD-PAUSE: paused in session stock, rerun to resume"; exit 10; }
	[ $rc = 0 ] || { log "SESSION FAILED: stock"; exit 1; }
fi

# 2) test kernel
d=$TOP/$KDIR
$S "cat > /var/tmp/usb-expected.txt" < $W/k14/usb-expected.txt
$S "mkdir -p $BT/debs && rm -f $BT/debs/*.deb" || exit 1
for p in image headers; do $S "cat > $BT/debs/$p.deb" < $d/linux-$p-7.3.0-opi5_7.3.0-${KREV}_arm64.deb || exit 1; done
timeout 900 $S 'while sudo -n fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 5; done'
log "installing $KREV: $(timeout 900 $S "sudo -n dpkg -i $BT/debs/image.deb $BT/debs/headers.deb >/dev/null 2>&1; echo dpkg=\$?; true")"
timeout 900 $S 'while sudo -n fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 5; done; dpkg -l linux-image-7.3.0-opi5 | tail -1; stat -c "initrd=%s" /boot/initrd.img-7.3.0-opi5' > "$R/dpkg.txt"
grep -q "^ii  linux-image-7.3.0-opi5 *7.3.0-$KREV " "$R/dpkg.txt" && ! grep -q "^initrd=0$" "$R/dpkg.txt" || { log "INSTALL FAILED: $(cat $R/dpkg.txt)"; exit 3; }
timeout 20 $S 'sudo -n systemctl reboot' 2>/dev/null; sleep 60
for i in $(seq 1 30); do timeout 8 $S true 2>/dev/null && break; sleep 10; done
timeout 120 $S 'for i in $(seq 1 18); do lsusb | awk "{print \$6}" | sort > /tmp/u.txt; [ -z "$(comm -23 /var/tmp/usb-expected.txt /tmp/u.txt)" ] && break; sleep 5; done'
timeout 120 $S 'set +e; uname -rv; echo "warn=$(sudo dmesg | grep -cE "WARNING|BUG:|Oops|Call trace")"
sudo dmesg | grep -E "WARNING|BUG:|Oops" | head -5
lsusb | awk "{print \$6}" | grep -v "^1d6b:" | sort > /tmp/usb-now.txt
echo "usb_missing=$(comm -23 /var/tmp/usb-expected.txt /tmp/usb-now.txt | tr "\n" " ")"
echo "iommu_err=$(sudo dmesg | grep -ciE "rk_iommu.*(timed out|fault)|page fault")"
echo "rga_bound=$(sudo dmesg | grep -ciE "rockchip-rga.*(bound|version)")"
echo "failed_units=$(systemctl --failed --no-legend | wc -l)"' > "$R/boot-$KREV.txt"
cat "$R/boot-$KREV.txt" >> "$R/host.log"
grep -q "^7.3.0-opi5 #$KREV " "$R/boot-$KREV.txt" || { log "BOOT CHECK FAILED: not running #$KREV"; exit 3; }
grep -q "^usb_missing=$" "$R/boot-$KREV.txt" || { log "BOOT CHECK FAILED: USB devices missing"; exit 3; }
grep -q "^warn=0$" "$R/boot-$KREV.txt" || { log "BOOT CHECK FAILED: kernel warnings"; exit 3; }
push_tools || { log "PUSH FAILED"; exit 1; }
log "session test (uname -v: $(timeout 15 $S 'uname -v'))"
session test $PH; rc=$?
[ $rc = 10 ] && { log "BOARD-PAUSE: paused in session test, rerun to resume"; exit 10; }
[ $rc = 0 ] || { log "SESSION FAILED: test"; exit 1; }
timeout 30 $S "sudo -n dmesg" > "$R/dmesg-end.txt" 2>/dev/null
log "all sessions done"
