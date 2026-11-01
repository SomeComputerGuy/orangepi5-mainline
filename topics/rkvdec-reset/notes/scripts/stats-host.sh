#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# stats-host.sh (host): keeps the board-side ~/rr/stats.sh queue going across its reboots without a boot
# service: once a minute, over one multiplexed ssh connection, start stats.sh if the board is up and it
# isn't running; copy ~/rrres/stats/{runs.tsv,log} to the host when they change. Stops on ALLDONE/STOPPED.
O=$HOME/orangepi5/work/_out/rkvdec-reset/bisect/stats; mkdir -p $O
S="$(cat ~/.claude/jobs/35761d63/tmp/ssh.cmd) -o ControlMaster=auto -o ControlPersist=10m -o ControlPath=/tmp/opi5-cm -o ConnectTimeout=10"
while :; do
	r=$(timeout 60 $S 'st=$(cat ~/rrres/stats/state 2>/dev/null); case "$st" in ALLDONE|STOPPED) ;; *) { [ -f ~/rrres/stats/pid ] && kill -0 $(cat ~/rrres/stats/pid) 2>/dev/null; } || { [ $(cut -d. -f1 /proc/uptime) -gt 60 ] && { setsid nohup ~/rr/stats.sh >/dev/null 2>&1 </dev/null & st="$st (started)"; }; } ;; esac; echo "$st"; echo ===; cat ~/rrres/stats/runs.tsv 2>/dev/null; echo ===; tail -3 ~/rrres/stats/log 2>/dev/null' 2>/dev/null)
	if [ -n "$r" ]; then
		echo "$r" | awk '/^===/{n++; next} n==1' > $O/runs.tsv.new; [ -s $O/runs.tsv.new ] && mv $O/runs.tsv.new $O/runs.tsv
		echo "$(date +%T) ${r%%$'\n'*} | $(echo "$r" | awk '/^===/{n++; next} n==2' | tail -1)" > $O/host-status
		case "${r%%$'\n'*}" in ALLDONE*|STOPPED*) break;; esac
	fi
	timeout 15 tail -f /dev/null
done
