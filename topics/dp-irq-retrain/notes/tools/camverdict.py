#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""camverdict.py <outprefix> [code] [pattern]: one webcam frame of the HDMI TV, classified against the
calibration (CALIB, default /var/tmp/tm/k10-hdmi/calib.json). Prints "<VERDICT>:<summary>" and exits 0 only
for GOOD. No camera, capture error or any other verdict exits non-zero: a display step without a trusted
GOOD frame is a failed step. Uses testmatrix/lib/camcheck.py (TM, default /var/tmp/testmatrix)."""
import json, os, sys

# Two screens in one frame: CAM_DUAL=1 or any argument of the form CONN=CODE[:PATTERN] (e.g. HDMI-A-1=1365 DP-1=2730).
# One capture, then each connector is judged against ITS OWN calibration ($CAL_DIR/calib-<CONN>.json, default
# /var/tmp/tm/cam2) and nothing outside that connector's quad. Prints one line per connector; exit 0 only if all GOOD.
TM = os.environ.get("TM", "/var/tmp/testmatrix")
sys.path.insert(0, TM + "/lib")
import camcheck  # noqa: E402


def dual(a):
    prefix = a[0]
    cam = camcheck.find()
    if not cam:
        print(f"NOCAM: no webcam matching {camcheck.CAM_NAME!r}", flush=True)
        return 4
    caldir = os.environ.get("CAL_DIR", "/var/tmp/tm/cam2")
    try:
        img = camcheck.load(camcheck.capture(prefix, cam))
    except Exception as e:  # noqa: BLE001
        print(f"CAMERR: {e!r}"[:200], flush=True)
        return 5
    bad = 0
    for arg in a[1:]:
        conn, _, rest = arg.partition("=")
        code, _, pat = rest.partition(":")
        try:
            cal = json.load(open(f"{caldir}/calib-{conn}.json"))
            r = camcheck.classify(cal, img, pat or "bars", int(code, 0))
            line = camcheck.cam_summary(r)
            bad += r["verdict"] != "GOOD"
        except Exception as e:  # noqa: BLE001
            line, bad = f"CAMERR: {e!r}"[:200], bad + 1
        print(f"{conn}: {line}", flush=True)
    return 0 if not bad else 3


def main(a):
    if os.environ.get("CAM_DUAL") or any("=" in x for x in a[1:]):
        return dual(a)
    prefix = a[0]
    code = int(a[1], 0) if len(a) > 1 else None
    pattern = a[2] if len(a) > 2 else "bars"
    cam = camcheck.find()
    if not cam:
        print(f"NOCAM: no webcam matching {camcheck.CAM_NAME!r}", flush=True)
        return 4
    try:
        cal = json.load(open(os.environ.get("CALIB", "/var/tmp/tm/k10-hdmi/calib.json")))
        r = camcheck.classify(cal, camcheck.load(camcheck.capture(prefix, cam)), pattern, code)
    except Exception as e:  # noqa: BLE001
        print(f"CAMERR: {e!r}"[:200], flush=True)
        return 5
    print(camcheck.cam_summary(r), flush=True)
    return 0 if r["verdict"] == "GOOD" else 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
