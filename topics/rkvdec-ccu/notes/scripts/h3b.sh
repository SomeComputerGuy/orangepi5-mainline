R=~/.local/share/fluster/resources; T=/usr/share/fluster/test_suites; E4=$(~/cq/elem.sh h264 rkvdec); P=/sys/module/rockchip_vdec/parameters
exp() { python3 -c "import json; d=json.load(open('$T/$1')); print([v['result'] for v in d['test_vectors'] if v['name']=='$2'][0])"; }
f() { ls $R/$1/$2/* | grep -vE '\.(md5|yuv|txt)$' | head -1; }
h264() { gst-launch-1.0 -q filesrc location=$(f $1 $2) ! h264parse ! $E4 ! videoconvert ! video/x-raw,format=I420 ! fdsink fd=1 2>/dev/null | md5sum | cut -d' ' -f1; }
for v in HCHP3_HHI_A HCAFF1_HHI_B CVFI1_Sony_D; do s=JVT-FR-EXT; [ $v = CVFI1_Sony_D ] && s=JVT-AVC_V1; e=$(exp h.264/$s.json $v)
for m in "1 1 1" "1 1 0" "0 1 1" "0 0 1"; do set -- $m; echo $1 | sudo -n tee $P/pipeline >/dev/null; echo $2 | sudo -n tee $P/ccu_hw >/dev/null; echo $3 | sudo -n tee $P/fieldpair >/dev/null
 ok=0; for i in 1 2 3 4 5 6; do [ "$(h264 $s $v)" = "$e" ] && ok=$((ok+1)); done; echo "$v p=$1 ccu=$2 fieldpair=$3: $ok/6"; done; done
echo 1 | sudo -n tee $P/pipeline $P/ccu_hw $P/fieldpair >/dev/null
