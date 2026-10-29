#!/usr/bin/env python3
"""Log a serial console with timestamps: serial-log.py [device] [baud] [logfile]

Each line is prefixed with seconds since the logger started, so gaps in the
boot (e.g. where U-Boot waits) are easy to spot."""
import os, sys, termios, time

dev = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB0"
baud = int(sys.argv[2]) if len(sys.argv) > 2 else 115200
log = sys.argv[3] if len(sys.argv) > 3 else "serial.log"

fd = os.open(dev, os.O_RDONLY | os.O_NOCTTY)
attrs = termios.tcgetattr(fd)
attrs[0] = 0                                   # iflag: raw
attrs[1] = 0                                   # oflag
attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
attrs[3] = 0                                   # lflag: no echo/canonical
speed = getattr(termios, f"B{baud}")
attrs[4] = attrs[5] = speed
termios.tcsetattr(fd, termios.TCSANOW, attrs)

start = time.monotonic()
buf = b""
with open(log, "a", buffering=1) as out:
    out.write(f"--- serial log {dev} @ {baud}, started {time.strftime('%F %T')} ---\n")
    while True:
        buf += os.read(fd, 4096)
        *lines, buf = buf.split(b"\n")
        for line in lines:
            text = line.rstrip(b"\r").decode("utf-8", "replace")
            out.write(f"[{time.monotonic() - start:8.3f}] {text}\n")
