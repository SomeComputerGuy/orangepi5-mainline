# RUNNER-SUMMARY 014-venc8k-1 (TEST)
Result: FAIL (verdict.py last line OVERALL FAIL)
Start 2026-11-06 04:58:18 (lock taken immediately), END 05:10:20 ("END: DONE"). Command: nohup bash ~/orangepi5/work/_out/k15/venc8k/tools/venc8k-test.sh (started by the watcher).
Stock restore: run.log "05:07:41 restore stock 15" ... "05:10:20 lock released". Live uname -v could not be checked at summary time: the next job (010 mpeg4-m4v1) already holds BOARD-LOCK and the board runs #15m4v1. BOARD-LOCK is not venc8k.
failed.txt: does not exist. logs/dmesg-new-*.txt: no lines. v8run.err lines with gst failed/no element/no source/no disk space: none.
venc8k.csv lines: 33 (expected 35) -> FAIL; VERDICT says "new rows: 23 of 25 expected".
## VERDICT (verbatim)
== wide and regression cases on the new kernel ==
case             size         frm rc       psnrY    left   right     fps verdict
r1080-h264-cbr   1920x1080     60 8000   45.482081      NA      NA  170.03 PASS
r1080-h264-cqp   1920x1080     60 cqp    39.671634      NA      NA  167.59 PASS
r1080-h265-cbr   1920x1080     60 8000   47.019317      NA      NA  172.51 PASS
r1080-h265-cqp   1920x1080     60 cqp    40.672800      NA      NA  172.08 PASS
r2160-h264-cbr   3840x2160     30 40000  49.080867      NA      NA   49.53 PASS
r2160-h264-cqp   3840x2160     30 cqp    41.784697      NA      NA   49.64 PASS
r2160-h265-cbr   3840x2160     30 40000  51.127743      NA      NA   49.40 PASS
r2160-h265-cqp   3840x2160     30 cqp    43.004063      NA      NA   47.60 PASS
r4096-h265-cqp   4096x2160     30 cqp    43.117265      NA      NA   46.52 PASS
w16384-h264-cqp  16384x2048    16 cqp    43.259128 42.978664 43.356791   12.34 PASS
w16384-h265-cqp  16384x2048    16 cqp    4.594191 5.370013 4.363598   12.10 FAIL ffmpeg messages=1; psnr_y=4.594191<36; psnr_left=5.370013<36; psnr_right=4.363598<36
w4104-h265-cqp   4104x2160     30 cqp    4.777492 4.773476 7.565300   45.15 FAIL psnr_y=4.777492<36; psnr_left=4.773476<36; psnr_right=7.565300<36
w4112-h264-cqp   4112x2160     30 cqp    41.736261 41.735633 41.899915   46.55 PASS
w5120-h264-cbr   5120x2880     30 60000  48.838214 48.464387 50.773426   29.92 PASS
w5120-h264-cqp   5120x2880     30 cqp    42.697286 42.666693 42.821859   29.75 PASS
w5120-h265-cbr   5120x2880     30 60000  4.771808 4.386247 6.787750   30.16 FAIL ffmpeg messages=8; psnr_y=4.771808<32; psnr_left=4.386247<32; psnr_right=6.787750<32
w5120-h265-cqp   5120x2880     30 cqp    4.682906 4.294064 6.721735   29.90 FAIL psnr_y=4.682906<36; psnr_left=4.294064<36; psnr_right=6.721735<36
w7680-h264-cbr   7680x4320     16 100000 49.849723 49.794067 49.914216   12.31 PASS
w7680-h264-cqp   7680x4320     16 cqp    42.804495 43.377295 42.230815   12.67 PASS
w7680-h265-cbr   7680x4320     16 100000 4.458124 4.239607 4.722110   12.42 FAIL psnr_y=4.458124<32; psnr_left=4.239607<32; psnr_right=4.722110<32
w7680-h265-cqp   7680x4320     16 cqp    4.550360 4.339667 4.804374   12.47 FAIL ffmpeg messages=2; psnr_y=4.550360<36; psnr_left=4.339667<36; psnr_right=4.804374<36
w8192-h264-cqp   8192x4320     16 cqp    42.378346 42.335068 42.422060   11.82 PASS
w8192-h265-cqp   8192x4320     16 cqp    4.493816 4.338081 4.655343   11.57 FAIL ffmpeg messages=5; psnr_y=4.493816<36; psnr_left=4.338081<36; psnr_right=4.655343<36

== regression: new (15v8k1) vs old (15hrc1) ==
r1080-h264-cbr   bytes 1998297 -> 1998297  psnr 45.482081 -> 45.482081  fps 169.84 -> 170.03  SAME
r1080-h264-cqp   bytes 654464 -> 654464  psnr 39.671634 -> 39.671634  fps 183.76 -> 167.59  SAME
r1080-h265-cbr   bytes 2001007 -> 2001007  psnr 47.019317 -> 47.019317  fps 170.81 -> 172.51  SAME
r1080-h265-cqp   bytes 488777 -> 488777  psnr 40.672800 -> 40.672800  fps 175.21 -> 172.08  SAME
r2160-h264-cbr   bytes 5451937 -> 5451937  psnr 49.080867 -> 49.080867  fps 49.15 -> 49.53  SAME
r2160-h264-cqp   bytes 1076462 -> 1076462  psnr 41.784697 -> 41.784697  fps 50.09 -> 49.64  SAME
r2160-h265-cbr   bytes 5378413 -> 5378413  psnr 51.127743 -> 51.127743  fps 49.41 -> 49.40  SAME
r2160-h265-cqp   bytes 786174 -> 786174  psnr 43.004063 -> 43.004063  fps 49.61 -> 47.60  SAME
r4096-h265-cqp   bytes 813557 -> 813557  psnr 43.117265 -> 43.117265  fps 46.67 -> 46.52  SAME

new rows: 23 of 25 expected

largest passing wide size h264: 16384x2048
largest passing wide size h265: none
OVERALL FAIL
## Files
END
logs
phases.done
run.log
RUNNER-SUMMARY.md
v8run.err
venc8k.csv
VERDICT.txt ; logs/: 87 files
