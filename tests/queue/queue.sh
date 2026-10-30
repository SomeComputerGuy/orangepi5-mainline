#!/bin/bash
# Unattended board test queue (runs ON the board). Summary: ~/queue/summary.txt
Q=$HOME/queue; mkdir -p $Q; S=$Q/summary.txt
say() { echo "[$(date +%T)] $*" | tee -a $S; }
say "queue start; kernel $(uname -v); rockchip-vdec $(modinfo -n rockchip_vdec)"
while pgrep -f ccu-verify.sh >/dev/null; do sleep 30; done
say "1. CCU verify finished: $(ls -dt $HOME/ccu/run-*/ | head -1)summary.txt"
cp "$(ls -dt $HOME/ccu/run-*/ | head -1)summary.txt" $Q/ccu-verify.txt 2>/dev/null
say "2. CCU fluster"; (cd $HOME/ccu && timeout 3600 bash $HOME/ccu/fluster.sh ccu > $Q/ccu-fluster.log 2>&1); say "   rc=$? $(tail -6 $(ls -dt $HOME/ccu/fluster-*/ | head -1)summary.txt 2>/dev/null | tr '\n' ';')"
if [ -x $HOME/cq/run-fluster.sh ] || [ -f $HOME/cq/run-fluster.sh ]; then
  say "3. codec-quality fluster (rkvdec + Hantro)"; (cd $HOME/cq && timeout 3600 bash $HOME/cq/run-fluster.sh > $Q/cq-fluster.log 2>&1); say "   rc=$? $(tail -12 $HOME/cq/fluster-results.txt 2>/dev/null | tr '\n' ';')"
fi
say "4. browser VA-API driver: probe correct perf gst"; (cd $HOME/browser-hwdec && timeout 1800 ./run-tests.sh probe correct perf gst > $Q/va-tests.log 2>&1); say "   rc=$? $(cat $HOME/browser-hwdec/results/*/SUMMARY.txt 2>/dev/null | tail -20 | tr '\n' ';')"
say "5. browser VA-API driver: fluster"; (cd $HOME/browser-hwdec && timeout 3000 ./run-tests.sh fluster > $Q/va-fluster.log 2>&1); say "   rc=$? $(cat $HOME/browser-hwdec/results/*/SUMMARY.txt 2>/dev/null | tail -10 | tr '\n' ';')"
say "kernel errors: $(sudo -n dmesg | grep -cE 'Oops|SError|BUG:|Internal error')"
say "DONE"
