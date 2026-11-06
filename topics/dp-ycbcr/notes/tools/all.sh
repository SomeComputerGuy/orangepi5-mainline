#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# all.sh: DEV stock probe, DEV 15ycc1 boot + probe + sanity/HDR smoke, then the TEST DP colour matrix (yielding).
D=$HOME/orangepi5/work/_out/k15/dp-ycc
bash $D/tools/ycc.sh dev stock probe:stock15 || exit $?
bash $D/tools/ycc.sh dev 15ycc1 probe:ycc1 list:sane list:dp_sane list:dp_hdr15 || exit $?
bash $D/tools/ycc.sh test 15ycc1 list:dp_00 list:dp_01 list:dp_02 list:dp_03
