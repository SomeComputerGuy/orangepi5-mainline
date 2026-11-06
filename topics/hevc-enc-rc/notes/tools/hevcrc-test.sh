#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# hevc-rc board test (TEST run, pausable/resumable): VEPU580 HEVC CBR on three kernels
#   old = 15h1rc2 (driver HEVC rate control, the base of k15-hevcrc)
#   new = 15hrc1  (k15-hevcrc: core CBR, I QP delta 4)
#   d2  = 15hrc1b (k15-hevcrc-d2: the same with I QP delta 2, comparison only)
# plus an H.264 regression check (old vs new) of the shared rate control helper.
# Each finished case is a CSV row and is skipped on restart. Pauses between cases when
# work/_out/BOARD-WANT/ is non-empty or work/_out/BOARD-PAUSE exists (restores stock 15,
# releases the lock, waits, re-takes the lock, re-installs the kernel and continues).
# Writes results/END (DONE or BLOCKED <reason>) when it stops for good.
# usage: hevcrc-test.sh        (no arguments; log: results/run.log)
set -u
W=$HOME/orangepi5/work/_out
D=$W/k15/hevc-rc
T=$D/tools
R=$D/results
V=$W/k15/venc-rc/tools
ME=hevc-rc
TMP=~/.claude/jobs/35761d63/tmp/hevc-rc
S=$(cat ~/.claude/jobs/35761d63/tmp/ssh.cmd)
O="-q -o BatchMode=yes -o UserKnownHostsFile=$HOME/orangepi5/.ssh/known_hosts -i $HOME/orangepi5/.ssh/opi5_ed25519"
B=/var/tmp/hevcrc
CSV=hevcrc.csv
mkdir -p "$R/sizes" "$R/trace" "$TMP"
rm -f "$R/END"
exec >> "$R/run.log" 2>&1
log() { echo "$(date -u '+%F %T') $*"; }

PHASES="old new d2"
debs_of() { case $1 in old) echo "$HOME/orangepi5/out/test/h1rc2/debs";;
	new) echo "$HOME/orangepi5/out/test/hevcrc/debs";; d2) echo "$HOME/orangepi5/out/test/hevcrc-d2/debs";; esac; }
rev_of() { case $1 in old) echo 15h1rc2;; new) echo 15hrc1;; d2) echo 15hrc1b;; esac; }
HEVC="bbb1080:h265:rkv:2000 bbb1080:h265:rkv:4000 bbb1080:h265:rkv:8000
yacht1080:h265:rkv:2000 yacht1080:h265:rkv:4000 yacht1080:h265:rkv:8000
bbb2160:h265:rkv:20000 bbb2160:h265:rkv:40000 jelly2160:h265:rkv:20000 jelly2160:h265:rkv:40000"
H264="bbb1080:h264:rkv:4000 yacht1080:h264:rkv:2000 bbb1080:h264:h1:4000"
cases_of() { case $1 in old|new) echo $HEVC $H264;; d2) echo $HEVC;; esac; }

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
	timeout 300 scp $O "<user>@<board-ip>:hwenc-test/hevcrc/sizes-*" "$R/sizes/" 2>/dev/null
	timeout 300 scp $O "<user>@<board-ip>:hwenc-test/hevcrc/trace-*" "$R/trace/" 2>/dev/null
}
on_kernel() { timeout 30 $S 'uname -v' 2>/dev/null | grep -q "^#$1 "; }
install() { # $1 phase
	on_kernel "$(rev_of "$1")" && return 0
	log "install $(rev_of "$1")"
	timeout 1200 "$V/install-test.sh" "$(debs_of "$1")" > "$TMP/install-$1.log" 2>&1
	cat "$TMP/install-$1.log"
	alive && on_kernel "$(rev_of "$1")" || { restore; end "BLOCKED install of $(rev_of "$1") failed, see $TMP/install-$1.log"; }
}
run_case() { # $1 label $2 case [$3 TRACE]; one retry after a stall
	local try st
	for try in 1 2; do
		timeout 900 $S "cd $B && TRACE=${3:-0} bash hrun.sh $B/$CSV $1 $2" < /dev/null 2>> "$R/hrun.err"
		st=$?
		copy_off
		[ $st != 124 ] && return 0
		log "case $1 $2 stalled (try $try)"
		alive || { end "BLOCKED board not answering ssh after a stalled case $1 $2 (lock kept)"; }
	done
	restore; end "BLOCKED case $1 $2 stalled twice"
}
# a case is done when its CSV row exists, or when it produced no row once (failed.txt)
done_case() { grep -q "^$1,${2//:/,}," "$R/$CSV" 2>/dev/null || grep -qx "$1,$2" "$R/failed.txt" 2>/dev/null; }

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
		# new kernels: re-run H.265 cases below -3% with the rate control trace
		if [ -z "$todo" ] && [ "$p" != old ]; then
			for c in $(awk -F, -v l="$p" '$1 == l && $3 == "h265" && $7 < -3 { print $2 ":" $3 ":" $4 ":" $5 }' "$R/$CSV"); do
				done_case "$p-trace" "$c" || todo="$todo T$c"
			done
		fi
		[ -z "$todo" ] && break
		[ $have_lock = 1 ] || { acquire; alive || end "BLOCKED board not answering ssh"; }
		timeout 60 $S "mkdir -p $B" && timeout 300 scp $O "$T/hrun.sh" "<user>@<board-ip>:$B/" || end "BLOCKED cannot copy hrun.sh to the board (lock kept)"
		[ -s "$R/$CSV" ] && timeout 300 scp $O "$R/$CSV" "<user>@<board-ip>:$B/$CSV"
		install "$p"
		for c in $todo; do
			if paused; then
				log "pause requested"; copy_off; restore
				while paused; do sleep 300; done
				continue 2
			fi
			log "$p $c"
			case $c in T*) l=$p-trace c=${c#T} t=1;; *) l=$p t=0;; esac
			run_case "$l" "$c" $t
			done_case "$l" "$c" || { echo "$l,$c" >> "$R/failed.txt"; log "case $l $c gave no result"; }
		done
	done
	echo "$p" >> "$R/phases.done"
	log "phase $p done"
done
[ $have_lock = 1 ] && restore
python3 -I "$T/verdict.py" "$R" > "$R/VERDICT.txt" 2>&1
cat "$R/VERDICT.txt"
end DONE
