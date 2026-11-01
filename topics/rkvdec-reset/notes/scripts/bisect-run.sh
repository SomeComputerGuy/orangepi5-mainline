#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# bisect-run.sh <variant>... (host): for each variant module dir in board ~/rr/mods: install it as the
# CCU drop-in of the KASAN kernel, boot it once, run bis2.sh (fluster JVT-AVC_V1 x6 + svasp.sh 16),
# copy the result to the host after every data point.
O=$HOME/orangepi5/work/_out/rkvdec-reset/bisect; B=~/.claude/jobs/35761d63/tmp/onb.sh
S="$(cat ~/.claude/jobs/35761d63/tmp/ssh.cmd)"
for v in "$@"; do
	echo "$(date +%T) $v: install+boot" >> $O/progress
	timeout 300 $B "cd ~/rr && ./install.sh mod mods/$v ccu >/dev/null && ./install.sh once >/dev/null && sync && sudo -n systemctl reboot" || true
	timeout 100 tail -f /dev/null
	timeout 900 $B "uname -r; md5sum /lib/modules/7.3.0-opi5-kasan/updates/opi5-rkvdec-reset/rockchip-vdec.ko ~/rr/mods/$v/rockchip-vdec.ko | cut -c1-12; sudo -n dmesg | grep -E '2 cores|rkvdec-canary' | cut -c1-110; cd ~/rr; setsid nohup ./bis2.sh $v ${NF:-6} ${NS:-16} >/dev/null 2>&1 </dev/null &" > $O/boot-$v.txt 2>&1
	bid=$(timeout 300 $B "cat /proc/sys/kernel/random/boot_id")
	# alive = same boot; a slow ssh under a KASAN load is not a lost board
	while :; do
		r=$(timeout 300 $B "cat /proc/sys/kernel/random/boot_id; grep -c DONE ~/rrres/bis-$v.txt" 2>/dev/null)
		if [ -n "$r" ] && [ "${r%%$'\n'*}" != "$bid" ]; then echo "$(date +%T) $v: BOARD REBOOTED (crash/watchdog) before DONE; that boot: $(timeout 300 $B "j=\$(sudo -n journalctl -k -b -1 --no-pager); echo timeouts \$(echo \"\$j\" | grep -c \"timed out\"), not-attached \$(echo \"\$j\" | grep -c \"not attached\"), KASAN/Oops \$(echo \"\$j\" | grep -cE \"BUG: KASAN|Oops|CANARY\")")" >> $O/progress; continue 2; fi
		[ "${r##*$'\n'}" = 1 ] && break
		[ -n "$r" ] && [ "${r##*$'\n'}" = "${r%%$'\n'*}" ] && { echo "$(date +%T) $v: result file missing, giving up" >> $O/progress; break; }
		timeout 60 tail -f /dev/null
	done
	timeout 300 $B "cat ~/rrres/bis-$v.txt 2>/dev/null; sudo -n journalctl -k -b 0 --no-pager > ~/rrres/dmesg-$v.txt; c=\$(grep -c \"timed out\" ~/rrres/dmesg-$v.txt); f=\$(grep -c \"not attached\" ~/rrres/dmesg-$v.txt); echo \"boot: timeouts \$c, IOMMU not-attached faults \$f\"" > $O/bis-$v.txt 2>&1
	mkdir -p $O/$v; timeout 300 $B "cd ~/rrres && tar cf - fluster-$v-* dmesg-$v.txt" | tar xf - -C $O/$v
	echo "$(date +%T) $v: done: $(grep -cE 'DIFFERENT' $O/bis-$v.txt) of ${NF:-6} fluster runs differ; $(grep -E 'bit-exact|since start|boot: ' $O/bis-$v.txt | tr '\n' ' ')" >> $O/progress
done
echo "$(date +%T) ALL DONE" >> $O/progress
