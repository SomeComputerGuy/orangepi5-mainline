# SPDX-License-Identifier: GPL-2.0
# Set /dev/rtc0 from the (NTP-synced) system clock and read it back:
#   python3 -I rtc-set.py          set + read back (as root)
#   python3 -I rtc-set.py --read   read back only
# struct rtc_time: sec, min, hour, mday, mon (0-11), year-1900, wday (0=Sunday), yday (0-365), isdst.
# The weekday matters: the hym8563 alarm matches minute, hour, day AND weekday.
import fcntl, struct, sys, time
RTC_RD_TIME, RTC_SET_TIME = 0x80247009, 0x4024700a
DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
if "--read" not in sys.argv:
    t = time.gmtime()
    buf = struct.pack("9i", t.tm_sec, t.tm_min, t.tm_hour, t.tm_mday, t.tm_mon - 1,
                      t.tm_year - 1900, (t.tm_wday + 1) % 7, t.tm_yday - 1, 0)
    with open("/dev/rtc0", "wb") as f:
        fcntl.ioctl(f, RTC_SET_TIME, buf)
with open("/dev/rtc0", "rb") as f:
    r = struct.unpack("9i", fcntl.ioctl(f, RTC_RD_TIME, bytes(36)))
sysw = (time.gmtime().tm_wday + 1) % 7
ok = 0 <= r[6] < 7 and r[6] == sysw
print("rtc: %s %04d-%02d-%02d %02d:%02d:%02d (system weekday %s) %s" %
      (DAYS[r[6]] if 0 <= r[6] < 7 else "wday=%d" % r[6], r[5] + 1900, r[4] + 1, r[3],
       r[2], r[1], r[0], DAYS[sysw], "OK" if ok else "WEEKDAY MISMATCH"))
sys.exit(0 if ok else 1)
