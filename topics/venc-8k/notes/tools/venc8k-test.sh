#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# venc8k board test (TEST run, pausable/resumable): VEPU580 H.264/H.265 encode above 4096 wide.
#   old = 15hrc1  (k15-hevcrc, the base: 1080p/4K reference encodes)
#   new = 15v8k1  (k15-venc8k: external line buffer, limits 16384x8192)
# Each finished case is a CSV row and is skipped on restart. Pauses between cases when
# work/_out/BOARD-WANT/ is non-empty or work/_out/BOARD-PAUSE exists (restores stock 15,
# releases the lock, waits, re-takes the lock, re-installs the kernel and continues).
# Writes results/END (DONE or BLOCKED <reason>) when it stops for good.
# usage: venc8k-test.sh        (no arguments; log: results/run.log)
set -u
W=$HOME/orangepi5/work/_out
D=$W/k15/venc8k
T=$D/tools
R=$D/results
V=$W/k15/venc-rc/tools
ME=venc8k
TMP=~/.claude/jobs/35761d63/tmp/venc8k
S=$(cat ~/.claude/jobs/35761d63/tmp/ssh.cmd)
O="-q -o BatchMode=yes -o UserKnownHostsFile=$HOME/orangepi5/.ssh/known_hosts -i $HOME/orangepi5/.ssh/opi5_ed25519"
B=/var/tmp/venc8k
CSV=venc8k.csv
mkdir -p "$R/logs" "$TMP"
rm -f "$R/END"
exec >> "$R/run.log" 2>&1
log() { echo "$(date -u '+%F %T') $*"; }

PHASES="old new"
debs_of() { case $1 in old) echo "$HOME/orangepi5/out/test/hevcrc/debs";;
	new) echo "$HOME/orangepi5/out/test/venc8k/debs";; esac; }
rev_of() { case $1 in old) echo 15hrc1;; new) echo 15v8k1;; esac; }
# name:codec:WxH:frames:rc   (rc = cqp or CBR kbps)
REG="r1080-h264-cqp:h264:1920x1080:60:cqp r1080-h265-cqp:h265:1920x1080:60:cqp
r1080-h264-cbr:h264:1920x1080:60:8000 r1080-h265-cbr:h265:1920x1080:60:8000
r2160-h264-cqp:h264:3840x2160:30:cqp r2160-h265-cqp:h265:3840x2160:30:cqp
r2160-h264-cbr:h264:3840x2160:30:40000 r2160-h265-cbr:h265:3840x2160:30:40000
r4096-h265-cqp:h265:4096x2160:30:cqp"
WIDE="w4104-h265-cqp:h265:4104x2160:30:cqp w4112-h264-cqp:h264:4112x2160:30:cqp
w5120-h265-cqp:h265:5120x2880:30:cqp w5120-h265-cbr:h265:5120x2880:30:60000
w5120-h264-cqp:h264:5120x2880:30:cqp w5120-h264-cbr:h264:5120x2880:30:60000
w7680-h265-cqp:h265:7680x4320:16:cqp w7680-h265-cbr:h265:7680x4320:16:100000
w7680-h264-cqp:h264:7680x4320:16:cqp w7680-h264-cbr:h264:7680x4320:16:100000
w8192-h265-cqp:h265:8192x4320:16:cqp w8192-h264-cqp:h264:8192x4320:16:cqp
w16384-h265-cqp:h265:16384x2048:16:cqp w16384-h264-cqp:h264:16384x2048:16:cqp"
cases_of() { case $1 in old) echo $REG;; new) echo $REG $WIDE;; esac; }

have_lock=0
paused() { [ -n "$(ls -A "$W/BOARD-WANT" 2>/dev/null)" ] || [ -e "$W/BOARD-PAUSE" ]; }
end() { echo "$1" > "$R/END"; log "END: $1"; exit 0; }
acquire() { # TEST run: only when the lock is free and nobody wants the board
	log "waiting for the board"
	while :; do
		if [ ! -e "$W/BOARD-LOCK" ] && ! paused &&
		   (set -C; echo "$ME $$ (TEST)" > "$W/BOARD-LOCK") 2>/dev/null; then
			have_lock=1; log "lock taken"; return 0
		fi
		sleep 120
	done
}
release() { grep -q "^$ME" "$W/BOARD-LOCK" 2>/dev/null && rm -f "$W/BOARD-LOCK"; have_lock=0; log "lock released"; }
restore() { # stock 15; keeps the lock and stops if the check fails
	log "restore stock 15"
	NOLOCK=1 timeout 900 bash "$W/k14/install-check.sh" > "$TMP/restore.log" 2>&1
	head -1 "$W/k14/boot.txt"
	if grep -q "Wed Nov  4 20:25:22" "$W/k14/boot.txt" && grep -q "^usb_missing=$" "$W/k14/boot.txt"; then
		release
	else
		end "BLOCKED stock restore check failed (lock kept), see $TMP/restore.log and $W/k14/boot.txt"
	fi
}
alive() { # board answers ssh within 15 min
	local i
	for i in $(seq 1 30); do timeout 20 $S true 2>/dev/null && return 0; sleep 30; done
	return 1
}
copy_off() {
	timeout 300 scp $O "<user>@<board-ip>:$B/$CSV" "$R/$CSV" 2>/dev/null
	timeout 300 scp $O "<user>@<board-ip>:hwenc-test/venc8k/*.txt" "<user>@<board-ip>:hwenc-test/venc8k/*.log" "$R/logs/" 2>/dev/null
}
on_kernel() { timeout 30 $S 'uname -v' 2>/dev/null | grep -q "^#$1 "; }
install() { # $1 phase
	on_kernel "$(rev_of "$1")" && return 0
	log "install $(rev_of "$1")"
	timeout 1200 "$V/install-test.sh" "$(debs_of "$1")" > "$TMP/install-$1.log" 2>&1
	cat "$TMP/install-$1.log"
	alive && on_kernel "$(rev_of "$1")" || { restore; end "BLOCKED install of $(rev_of "$1") failed, see $TMP/install-$1.log"; }
}
run_case() { # $1 label $2 case; one retry after a stall
	local try st
	for try in 1 2; do
		timeout 2400 $S "cd $B && bash v8run.sh $B/$CSV $1 $2" < /dev/null 2>> "$R/v8run.err"
		st=$?
		copy_off
		[ $st != 124 ] && return 0
		log "case $1 $2 stalled (try $try)"
		alive || { end "BLOCKED board not answering ssh after a stalled case $1 $2 (lock kept)"; }
	done
	restore; end "BLOCKED case $1 $2 stalled twice"
}
# a case is done when its CSV row exists, or when it produced no row once (failed.txt)
done_case() { grep -q "^$1,${2%%:*}," "$R/$CSV" 2>/dev/null || grep -qx "$1,$2" "$R/failed.txt" 2>/dev/null; }

for p in $PHASES; do
	[ -d "$(debs_of "$p")" ] || end "BLOCKED missing debs $(debs_of "$p")"
done
log "start $(id -un)"
for p in $PHASES; do
	grep -qx "$p" "$R/phases.done" 2>/dev/null && continue
	list=$(cases_of "$p")
	while :; do
		todo=""
		for c in $list; do done_case "$p" "$c" || todo="$todo $c"
		done
		[ -z "$todo" ] && break
		[ $have_lock = 1 ] || { acquire; alive || end "BLOCKED board not answering ssh"; }
		timeout 60 $S "mkdir -p $B" && timeout 300 scp $O "$T/v8run.sh" "<user>@<board-ip>:$B/" || end "BLOCKED cannot copy v8run.sh to the board (lock kept)"
		[ -s "$R/$CSV" ] && timeout 300 scp $O "$R/$CSV" "<user>@<board-ip>:$B/$CSV"
		install "$p"
		for c in $todo; do
			if paused; then
				log "pause requested"; copy_off; restore
				while paused; do sleep 300; done
				continue 2
			fi
			log "$p $c"
			run_case "$p" "$c"
			done_case "$p" "$c" || { echo "$p,$c" >> "$R/failed.txt"; log "case $p $c gave no result"; }
		done
	done
	echo "$p" >> "$R/phases.done"
	log "phase $p done"
done
[ $have_lock = 1 ] && restore
python3 -I "$T/verdict.py" "$R" > "$R/VERDICT.txt" 2>&1
cat "$R/VERDICT.txt"
end DONE
