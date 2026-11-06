#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# rga3-nv15 board part (runs on the board as aruni, sudo -n inside). Resumable: every phase writes
# OUT/TAG/<phase>.done, every finished case a line in OUT/TAG/cases.tsv; both are skipped on a rerun.
# Stops between steps when B/STOP exists (BOARD-PAUSE/BOARD-WANT, set by run.sh).
#   board.sh TAG PHASES...   phases: info compliance regress cases
set -u
B=/var/tmp/rga3nv15; T=$B/tools; I=$B/inputs; TAG=$1; shift; O=$B/out/$TAG; mkdir -p $O; cd $O
log() { echo "[$(date +%T)] $*" >> $B/out/board.log; }
# kernel log of the current phase, appended (some sub-tests clear the ring buffer themselves)
klog() { sudo -n dmesg >> dmesg-${cur:-pre}.txt; sudo -n dmesg -C; }
stop() { [ -e $B/STOP ] && { klog; log "STOP: pausing before $1"; exit 10; }; true; }
node() { for d in /dev/video*; do v4l2-ctl -d $d -D 2>/dev/null | grep -q "Card type *: *$1\$" && { echo $d; return; }; done; }
R2=$(node rga2); R3=$(node rga3)
heap_rga2() { for h in /dev/dma_heap/*; do case ${h##*/} in system*) ;; *cma*|*reserved*|*default*) echo $h; return;; esac; done; echo /dev/dma_heap/system; }
H2=$(heap_rga2); H3=/dev/dma_heap/system
log "tag $TAG phases $* rga2=$R2 rga3=$R3 heaps rga2=$H2 rga3=$H3"
cur=pre; klog
for ph in "$@"; do
	[ -e $ph.done ] && { log "phase $ph already done"; continue; }
	stop "phase $ph"
	cur=$ph; log "phase $ph start"
	case $ph in
	info)
		{ uname -rv; echo "rga2=$R2 rga3=$R3 heap_rga2=$H2 heap_rga3=$H3"; ls -l /dev/dma_heap/
		  for d in $R2 $R3; do v4l2-ctl -d $d -D; v4l2-ctl -d $d --list-formats-out; v4l2-ctl -d $d --list-formats; v4l2-ctl -d $d -l; done
		  sudo -n dmesg | grep -iE 'rga|fdb[567]0'; } > info.txt 2>&1 ;;
	compliance)
		for n in rga2 rga3; do d=$(node $n); timeout 600 sudo -n v4l2-compliance -d $d < /dev/null > compliance-$n.txt 2>&1; echo "rc=$?" >> compliance-$n.txt; done ;;
	regress)
		klog; timeout 900 sudo -n bash $T/rga2-regress-board.sh $O/rga2reg > rga2reg-board.txt 2>&1
		sudo -n chown -R $(id -u) $O/rga2reg
		mkdir -p /var/tmp/rga3; cp $T/rga-test $T/board-tests.sh /var/tmp/rga3/; chmod +x /var/tmp/rga3/rga-test /var/tmp/rga3/board-tests.sh
		rm -rf /var/tmp/rga3/k12func-$TAG; klog
		timeout 1200 /var/tmp/rga3/board-tests.sh k12func-$TAG func < /dev/null > k12func-run.txt 2>&1
		rm -rf k12func; cp -r /var/tmp/rga3/k12func-$TAG k12func ;;
	cases)
		touch cases.tsv
		while IFS='|' read -r id nd inp src dst args nfr kind ref; do
			case $id in ''|'#'*) continue;; esac
			grep -q "^$id " cases.tsv && continue
			stop "case $id"
			[ $nd = rga2 ] && { d=$R2; h=$H2; } || { d=$R3; h=$H3; }
			a=${args//HEAP/$h}
			timeout -k 5 120 sudo -n $T/rga-xtest -d $d -i $I/$inp -s $src -t $dst -o $O/$id.raw -n $nfr $a < /dev/null > $id.log 2>&1; rc=$?
			sudo -n chown $(id -u) $O/$id.raw 2>/dev/null
			echo "$id $rc" >> cases.tsv; log "case $id rc=$rc"
			sync
		done < $T/cases.txt ;;
	esac
	klog
	touch $ph.done; log "phase $ph done"
done
log "tag $TAG all phases done"
echo "ALLDONE $TAG" >> $B/out/board.log
