#!/bin/bash
# irqrate.sh N : print VOP irq/s for N seconds
irq=$(awk "/fdd90000.vop/{sub(\":\",\"\",\$1); print \$1; exit}" /proc/interrupts)
get() { awk -v i="$irq:" "\$1==i{s=0; for(k=2;k<=9;k++) s+=\$k; print s}" /proc/interrupts; }
p=$(get); for s in $(seq 1 $1); do sleep 1; c=$(get); echo -n "$((c-p)) "; p=$c; done; echo
