#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# hevc-rc-2 board test (TEST run, pausable/resumable): VEPU580 HEVC CBR on two kernels
#   old = 16rc2  (k16-rc2: the driver HEVC rate control and the H.264 code before the helper)
#   new = 16hrc2 (k16-hevcrc: core CBR helper + I picture size bound)
# per kernel: H.265 CBR cases + H.264 CBR regression cases; new also: rate control traces of
# 4 H.265 cases and 3 H.265 encodes wider than 4096 (venc8k's v8run.sh).
# Each finished case is a CSV row and is skipped on restart. Pauses between cases when
# work/_out/BOARD-WANT/ is non-empty or work/_out/BOARD-PAUSE exists (restores stock,
# releases the lock, waits, re-takes the lock, re-installs the kernel and continues).
# Writes results2/END (DONE or BLOCKED <reason>) when it stops for good.
# usage: hevcrc-test.sh        (no arguments; log: results2/run.log)
set -u
W=$HOME/orangepi5/work/_out
D=$W/k15/hevc-rc
T=$D/tools2
R=$D/results2
ME=hevc-rc2
TMP=~/.claude/jobs/35761d63/tmp/hevc-rc2
S=$(cat ~/.claude/jobs/35761d63/tmp/ssh.cmd)
O="-q -o BatchMode=yes -o UserKnownHostsFile=$HOME/orangepi5/.ssh/known_hosts -i $HOME/orangepi5/.ssh/opi5_ed25519"
B=/var/tmp/hevcrc2
CSV=hevcrc.csv
WCSV=wide.csv
mkdir -p "$R/sizes" "$R/trace" "$R/psnr" "$TMP"
rm -f "$R/END"
exec >> "$R/run.log" 2>&1
log() { echo "$(date -u '+%F %T') $*"; }

PHASES="old new"
debs_of() { case $1 in old) echo "$HOME/orangepi5/out/test/k16rc2/debs";;
	new) echo "$HOME/orangepi5/out/test/hrc2/debs";; esac; }
rev_of() { case $1 in old) echo 16rc2;; new) echo 16hrc2;; esac; }
HEVC="bbb1080:h265:rkv:2000 bbb1080:h265:rkv:4000 bbb1080:h265:rkv:8000
yacht1080:h265:rkv:2000 yacht1080:h265:rkv:4000 yacht1080:h265:rkv:8000
bbb2160:h265:rkv:20000 bbb2160:h265:rkv:40000 jelly2160:h265:rkv:20000 jelly2160:h265:rkv:40000"
H264="bbb1080:h264:rkv:4000 yacht1080:h264:rkv:2000 bbb1080:h264:h1:4000"
TRACES="Tbbb1080:h265:rkv:2000 Tbbb1080:h265:rkv:8000 Tbbb2160:h265:rkv:20000 Tjelly2160:h265:rkv:20000"
WIDE="Ww4104-h265-cqp:h265:4104x2160:30:cqp Ww5120-h265-cbr:h265:5120x2880:30:60000 Ww8192-h265-cqp:h265:8192x4320:16:cqp"
cases_of() { case $1 in old) echo $HEVC $H264;; new) echo $HEVC $H264 $TRACES $WIDE;; esac; }

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
release() { grep -q "^$ME " "$W/BOARD-LOCK" 2>/dev/null && rm -f "$W/BOARD-LOCK"; have_lock=0; log "lock released"; }
restore() { # stock kernel (out/debs, version read from the deb by install-check.sh); keeps the lock and stops if the check fails
	log "restore stock"
	NOLOCK=1 timeout 900 bash "$W/k14/install-check.sh" > "$TMP/restore.log" 2>&1
	head -1 "$W/k14/boot.txt"
	if grep -q "Sat Nov  7 04:32:10" "$W/k14/boot.txt" && grep -q "^usb_missing=$" "$W/k14/boot.txt"; then
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
	timeout 300 scp $O "<user>@<board-ip>:$B/$WCSV" "$R/$WCSV" 2>/dev/null
	timeout 300 scp $O "<user>@<board-ip>:hwenc-test/hevcrc2/sizes-*" "$R/sizes/" 2>/dev/null
	timeout 300 scp $O "<user>@<board-ip>:hwenc-test/hevcrc2/trace-*" "$R/trace/" 2>/dev/null
	timeout 300 scp $O "<user>@<board-ip>:hwenc-test/hevcrc2/psnr-*" "$R/psnr/" 2>/dev/null
	timeout 300 scp $O "<user>@<board-ip>:hwenc-test/hrc2w/dmesg-*" "<user>@<board-ip>:hwenc-test/hrc2w/ffdec-*" "$R/trace/" 2>/dev/null
}
on_kernel() { timeout 30 $S 'uname -v' 2>/dev/null | grep -q "^#$1 "; }
install() { # $1 phase
	on_kernel "$(rev_of "$1")" && return 0
	log "install $(rev_of "$1")"
	timeout 1200 bash "$T/install-test.sh" "$(debs_of "$1")" > "$TMP/install-$1.log" 2>&1
	cat "$TMP/install-$1.log"
	alive && on_kernel "$(rev_of "$1")" || { restore; end "BLOCKED install of $(rev_of "$1") failed, see $TMP/install-$1.log"; }
}
run_case() { # $1 label $2 case $3 kind (H normal, T trace, W wide); one retry after a stall
	local try st cmd
	case $3 in
	W) cmd="cd $B && WORK=\$HOME/hwenc-test/hrc2w timeout 1800 bash v8run.sh $B/$WCSV $1 $2";;
	T) cmd="cd $B && TRACE=1 timeout 900 bash hrun.sh $B/$CSV $1 $2";;
	*) cmd="cd $B && TRACE=0 timeout 900 bash hrun.sh $B/$CSV $1 $2";;
	esac
	for try in 1 2; do
		timeout 2000 $S "$cmd" < /dev/null 2>> "$R/hrun.err"
		st=$?
		copy_off
		[ $st != 124 ] && return 0
		log "case $1 $2 stalled (try $try)"
		alive || { end "BLOCKED board not answering ssh after a stalled case $1 $2 (lock kept)"; }
	done
	restore; end "BLOCKED case $1 $2 stalled twice"
}
# a case is done when its CSV row exists, or when it produced no row once (failed.txt)
done_case() { # $1 label $2 case $3 kind
	if [ "$3" = W ]; then grep -q "^$1,${2%%:*}," "$R/$WCSV" 2>/dev/null && return 0
	else grep -q "^$1,${2//:/,}," "$R/$CSV" 2>/dev/null && return 0; fi
	grep -qx "$1,$2" "$R/failed.txt" 2>/dev/null
}
split_case() { # sets l (label), c (case), k (kind) from phase $1 and list entry $2
	case $2 in
	T*) l=$1-trace c=${2#T} k=T;;
	W*) l=$1 c=${2#W} k=W;;
	*) l=$1 c=$2 k=H;;
	esac
}

for p in $PHASES; do
	[ -d "$(debs_of "$p")" ] || end "BLOCKED missing debs $(debs_of "$p")"
done
log "start $(id -un)"
for p in $PHASES; do
	grep -qx "$p" "$R/phases.done" 2>/dev/null && continue
	todo=""
	for x in $(cases_of "$p"); do split_case "$p" "$x"; done_case "$l" "$c" "$k" || todo="$todo $x"; done
	while [ -n "$todo" ]; do
		[ $have_lock = 1 ] || { acquire; alive || end "BLOCKED board not answering ssh"; }
		timeout 60 $S "mkdir -p $B" && timeout 300 scp $O "$T/hrun.sh" "$W/k15/venc8k/tools/v8run.sh" "<user>@<board-ip>:$B/" ||
			end "BLOCKED cannot copy the scripts to the board (lock kept)"
		[ -s "$R/$CSV" ] && timeout 300 scp $O "$R/$CSV" "<user>@<board-ip>:$B/$CSV"
		[ -s "$R/$WCSV" ] && timeout 300 scp $O "$R/$WCSV" "<user>@<board-ip>:$B/$WCSV"
		install "$p"
		left=""
		for x in $todo; do
			if paused; then
				left="$left $x"; continue
			fi
			split_case "$p" "$x"
			log "$p $x"
			run_case "$l" "$c" "$k"
			done_case "$l" "$c" "$k" || { echo "$l,$c" >> "$R/failed.txt"; log "case $l $c gave no result"; }
		done
		todo=$left
		if [ -n "$todo" ]; then
			log "pause requested"; copy_off; restore
			while paused; do sleep 300; done
			log "resume"
		fi
	done
	echo "$p" >> "$R/phases.done"
	log "phase $p done"
done
[ $have_lock = 1 ] && restore
python3 -I "$T/verdict.py" "$R" > "$R/VERDICT.txt" 2>&1
cat "$R/VERDICT.txt"
end DONE
