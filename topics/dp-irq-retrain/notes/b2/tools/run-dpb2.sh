#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# JOB dp-black-2 (TEST): silent DP black, A/B of the VOP2 DP interface enable order in one kernel (7.3.0-16dpb1,
# rockchipdrm.dp_if_gate alternated per iteration by tools/dpblack-board.sh). Blocks D1..D7 of $ITER iterations,
# each block one board session (own boot + camera calibration, so lighting drift is recalibrated every ~1 h).
# Pausable/resumable: run.sh exits 10 when it paused for a BOARD-WANT file or BOARD-PAUSE (stock 15 restored,
# lock released); this wrapper then waits until both are clear and reruns the block, which skips the finished
# iterations. A finished block (iter.tsv has $ITER rows) is skipped on a rerun of this wrapper, so rerunning the
# whole command after an interruption also resumes. Any run.sh failure (exit 1/3: install, boot check, board
# unreachable) stops the job ("BLOCK FAILED"); a session that ended early without failing (stall, timeout) is
# retried up to 2 times.
#   bash tools/run-dpb2.sh
set -u
W=$HOME/orangepi5/work/_out; O=$W/k15/dp-silent-black/b2; ITER=${ITER:-200}
H=$O/run-dpb2.log
cd "$O" || exit 1
log() { echo "[$(date +%T)] run-dpb2: $*" >> "$H"; }
rows() { local c; c=$(grep -c . "$O/run-$1/out/iter.tsv" 2>/dev/null); echo "${c:-0}"; }
log "start (ITER=$ITER)"
for tag in D1 D2 D3 D4 D5 D6 D7; do
	tries=0
	while [ "$(rows $tag)" -lt "$ITER" ]; do
		while [ -n "$(ls -A $W/BOARD-WANT 2>/dev/null)" ] || [ -e "$W/BOARD-PAUSE" ]; do sleep 300; done
		log "block $tag: session start, $(rows $tag) of $ITER done"
		KREV=16dpb1 KDIR=out/test/dpblack/debs TAG=$tag ITER=$ITER RUN_TIMEOUT=5400 bash tools/run.sh
		rc=$?
		log "block $tag: session rc=$rc, $(rows $tag) of $ITER done"
		if grep -qE 'DP-1 NOT CONNECTED|NO TESTMATRIX|NO DP_IF_GATE PARAM' "$O/run-$tag/out/board.log" 2>/dev/null; then
			log "BLOCK FAILED: $tag: $(grep -E 'DP-1 NOT CONNECTED|NO TESTMATRIX|NO DP_IF_GATE PARAM' "$O/run-$tag/out/board.log" | tail -1)"
			log "finished (failed)"; exit 1
		fi
		[ $rc = 10 ] && continue
		if [ $rc != 0 ]; then log "BLOCK FAILED: $tag rc=$rc (see run-$tag/host.log)"; log "finished (failed)"; exit 1; fi
		tries=$((tries + 1))
		[ "$(rows $tag)" -ge "$ITER" ] && break
		[ $tries -ge 3 ] && { log "block $tag incomplete after $tries sessions, going on"; break; }
	done
done
log "finished"
