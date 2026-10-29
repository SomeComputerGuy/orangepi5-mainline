#!/bin/bash
# guard.sh <timeout> <cmd...>: run a command, then report new IEP IOMMU faults and
# IEP errors in dmesg. Exit 99 if faults were seen (caller must stop).
T=$1; shift
before=$(sudo -n dmesg | grep -c "fdbb0800.iommu: Page fault")
timeout -k 5 "$T" "$@"
rc=$?
sleep 0.5
after=$(sudo -n dmesg | grep -c "fdbb0800.iommu: Page fault")
errs=$(sudo -n dmesg | grep -c "rockchip-iep.*\(failed\|timed out\|timeout\)")
echo "[guard] rc=$rc iommu_faults=+$((after - before)) iep_err_total=$errs"
[ "$after" -ne "$before" ] && exit 99
exit $rc
