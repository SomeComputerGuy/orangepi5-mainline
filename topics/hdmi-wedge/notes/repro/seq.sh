#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Timing shortcuts for wedge.py (TCL Beyond TV mode list)
T1080="timing=148500/1920:2008:2052:2200/1080:1084:1089:1125/1048581"
T4096="timing=593407/4096:4184:4272:4400/2160:2168:2178:2250/2097157"
T3840="timing=593407/3840:4016:4104:4400/2160:2168:2178:2250/1048581"
T3840_594="timing=594000/3840:4016:4104:4400/2160:2168:2178:2250/1048581"
T4K120="timing=1188000/3840:4016:4104:4400/2160:2168:2178:2250/1048581"
B8="prop:max bpc=8"; B10="prop:max bpc=10"
RGB="prop:color format=RGB"; Y444="prop:color format=YUV 4:4:4"; Y422="prop:color format=YUV 4:2:2"
Y420="prop:color format=YUV 4:2:0"; AUTO="prop:color format=AUTO"
LIN="plane=59,fmt=XR24,mod=linear"; AFBC30="plane=35,fmt=XR30,mod=0x800000000000051"
AFBC24="plane=35,fmt=XR24,mod=auto"; LIN30="plane=59,fmt=XR30,mod=linear"
W="python3 -I /var/tmp/wedge/wedge.py"
T4096_594="timing=594000/4096:4184:4272:4400/2160:2168:2178:2250/2097157"
T3840_5994="timing=593407/3840:4016:4104:4400/2160:2168:2178:2250/1048581"
