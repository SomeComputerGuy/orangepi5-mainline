# Set /dev/rtc0 from the (NTP-synced) system clock: python3 -I rtc-set.py (as root)
import fcntl, struct, time
t = time.gmtime()
buf = struct.pack("9i", t.tm_sec, t.tm_min, t.tm_hour, t.tm_mday, t.tm_mon - 1, t.tm_year - 1900, 0, 0, 0)
with open("/dev/rtc0", "wb") as f:
    fcntl.ioctl(f, 0x4024700a, buf)  # RTC_SET_TIME
