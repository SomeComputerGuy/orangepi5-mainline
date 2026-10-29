#!/bin/sh
# Reload hantro_vpu twice, only if the VPUs are healthy. Logs to /var/tmp/hmc/reload.log
L=/var/tmp/hmc/reload.log
bad() { sudo -n dmesg | grep -ciE "rk_iommu.*fault|vsi_iommu.*fault|stall request timed out|frame processing timed out|WARNING|BUG|Oops"; }
for r in 1 2; do
  n=$(bad); echo "round $r: bad=$n" >> $L
  [ "$n" = 0 ] || { echo "unhealthy, stop" >> $L; sync; exit 1; }
  sudo -n dmesg > /var/tmp/hmc/dmesg-before-reload$r.txt; sync
  sudo -n modprobe -r hantro_vpu || { echo "rmmod failed" >> $L; exit 1; }
  sudo -n dmesg | tail -20 >> $L; sync
  sleep 1
  sudo -n modprobe hantro_vpu
  sleep 2
  sudo -n dmesg | tail -12 >> $L; sync
done
echo done >> $L; sync
