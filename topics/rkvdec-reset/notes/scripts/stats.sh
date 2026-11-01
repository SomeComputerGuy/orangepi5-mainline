#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# stats.sh (board, started at boot by rr-stats.service as aruni): runs the bisect queue unattended.
# ~/rrres/stats/queue: one variant (dir in ~/rr/mods) per line, one block of $N fluster JVT-AVC_V1 -j2
# runs per boot of the KASAN kernel. Per run, a line in ~/rrres/stats/runs.tsv:
#   variant block run n_differ differing-vectors(vs single-core) timeouts not-attached KASAN/Oops/canary
# After a block: install the next variant, boot it once. A boot that isn't the KASAN kernel with a block
# marked running means that block crashed: logged, retried once by booting the next block.
set -u; S=~/rrres/stats; K=7.3.0-opi5-kasan; N=${N:-5}; cd ~/rr; mkdir -p $S
log() { echo "$(date +%T) $*" >> $S/log; }
next_boot() { v=$(head -1 $S/queue 2>/dev/null); v=${v%%:*}; [ -z "$v" ] && { log "queue empty: ALL DONE"; ./install.sh stock >/dev/null 2>&1; echo ALLDONE > $S/state; exit 0; }
	./install.sh mod mods/$v ccu >/dev/null 2>&1 && ./install.sh once >/dev/null && echo "$v" > $S/running && sync && sudo -n systemctl reboot; exit 0; }
echo $$ > $S/pid
[ -f $S/queue ] || exit 0
if [ "$(uname -r)" != $K ]; then
	[ -f $S/running ] || exit 0
	r=$(cat $S/running); c=$(cat $S/crashes 2>/dev/null || echo 0); log "CRASH/REBOOT during block $r (journal -1: $(sudo -n journalctl -k -b -1 --no-pager | grep -cE 'BUG:|Oops|Internal error|SError|panic') oops lines)"
	printf '%s\tCRASH\n' "$r" >> $S/runs.tsv
	echo $((c+1)) > $S/crashes; [ $((c+1)) -ge 2 ] && { log "2 crashes in a row: stopping"; echo STOPPED > $S/state; rm -f $S/running; exit 0; }
	sed -i 1d $S/queue; next_boot
fi
e=$(head -1 $S/queue); v=${e%%:*}; m1=$(md5sum < /lib/modules/$K/updates/opi5-rkvdec-reset/rockchip-vdec.ko 2>/dev/null); m2=$(md5sum < mods/$v/rockchip-vdec.ko)
[ "$m1" = "$m2" ] || { log "module mismatch for $v: installing"; next_boot; }
echo 0 > $S/crashes; echo "running $v" > $S/state
timeout 90 tail -f /dev/null	# let the boot settle
c=$(grep -c "^$v	" $S/runs.tsv 2>/dev/null); b=$(( ${c:-0} / N + 1 )); log "block $v #$b start"
export FLDIR=$HOME/rrres RRLOG=$HOME/rrres
if [ "$e" != "$v" ]; then	# variant:svasp = the SVA-next-to-SP1_BT_A pair test, 16 rounds (64 decodes)
	k0=$(sudo -n dmesg | wc -l); r=$(./svasp.sh 16 2>&1 | tail -1); k=$(sudo -n dmesg | tail -n +$k0)
	printf '%s\tsvasp\t%s\ttimeouts %s, KASAN/Oops/canary %s\n' "$v" "$r" "$(echo "$k" | grep -c 'timed out')" "$(echo "$k" | grep -cE 'BUG: KASAN|Oops|CANARY|WARNING:')" >> $S/runs.tsv
	log "block $e done"; sed -i 1d $S/queue; rm -f $S/running; next_boot
fi
for i in $(seq 1 $N); do
	n0=$(sudo -n dmesg | wc -l)
	./fluster.sh st JVT-AVC_V1 >/dev/null 2>&1
	f=$HOME/rrres/fluster-st/GStreamer-H.264-V4L2SL-RKVDEC-JVT-AVC_V1.md
	got=$(grep -E '\|(❌|☠|⌛)' $f 2>/dev/null | cut -d'|' -f2 | tr -d ' ' | sort -u)
	ref=$(tr ' ' '\n' < ~/ccu/fluster-single/GStreamer-H.264-V4L2SL-RKVDEC-JVT-AVC_V1.fail.txt | grep -E '^[A-Za-z0-9]' | grep -v '^\[' | sort -u)
	d=$(comm -3 <(echo "$got") <(echo "$ref") | tr -d '\t' | grep . | tr '\n' ' ')
	[ -f "$f" ] || d="NO-RESULT"
	k=$(sudo -n dmesg | tail -n +$n0)
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$v" "$b" "$i" "$(echo $d | wc -w)" "${d:--}" "$(echo "$k" | grep -c 'timed out')" "$(echo "$k" | grep -c 'not attached')" "$(echo "$k" | grep -cE 'BUG: KASAN|Oops|CANARY|WARNING:')" >> $S/runs.tsv
done
log "block $v #$b done"; sed -i 1d $S/queue; rm -f $S/running; next_boot
