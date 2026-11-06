#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# JOB dp-black-1 (TEST): silent DP black rate, stock 7.3.0-15 (baseline) vs 7.3.0-15dpirq1 (dw-dp link check fix),
# in alternating blocks of $ITER dual-head modesets, each block one board session (own boot) of tools/run.sh:
#   B1 (15) F1 (15dpirq1) B2 F2 B3 F3
# Pausable/resumable: run.sh exits 10 when it paused for a BOARD-WANT file or BOARD-PAUSE (stock 15 restored,
# lock released); this wrapper then waits until both are clear and reruns the block, which skips the finished
# iterations. A finished block (iter.tsv has $ITER rows) is skipped on a rerun of this wrapper, so rerunning the
# whole command after an interruption also resumes. Any run.sh failure (exit 1/3: install, boot check, board
# unreachable) stops the job ("BLOCK FAILED"); a session that ended early without failing (stall, timeout) is
# retried up to 2 times.
#   bash tools/run-dpblack.sh
set -u
W=$HOME/orangepi5/work/_out; O=$W/k15/dp-silent-black; ITER=${ITER:-60}
H=$O/run-dpblack.log
cd "$O" || exit 1
log() { echo "[$(date +%T)] run-dpblack: $*" >> "$H"; }
rows() { local c; c=$(grep -c . "$O/run-$1/out/iter.tsv" 2>/dev/null); echo "${c:-0}"; }
log "start (ITER=$ITER)"
for b in B1:15:out/debs F1:15dpirq1:out/test/dpirq/debs B2:15:out/debs F2:15dpirq1:out/test/dpirq/debs \
         B3:15:out/debs F3:15dpirq1:out/test/dpirq/debs; do
	tag=${b%%:*}; rest=${b#*:}; krev=${rest%%:*}; kdir=${rest#*:}
	tries=0
	while [ "$(rows $tag)" -lt "$ITER" ]; do
		while [ -n "$(ls -A $W/BOARD-WANT 2>/dev/null)" ] || [ -e "$W/BOARD-PAUSE" ]; do sleep 300; done
		log "block $tag ($krev): session start, $(rows $tag) of $ITER done"
		KREV=$krev KDIR=$kdir TAG=$tag ITER=$ITER RUN_TIMEOUT=3600 bash tools/run.sh
		rc=$?
		log "block $tag: session rc=$rc, $(rows $tag) of $ITER done"
		if grep -qE 'DP-1 NOT CONNECTED|NO TESTMATRIX' "$O/run-$tag/out/board.log" 2>/dev/null; then
			log "BLOCK FAILED: $tag: $(grep -E 'DP-1 NOT CONNECTED|NO TESTMATRIX' "$O/run-$tag/out/board.log" | tail -1)"
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
