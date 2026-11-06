#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""probetab.py <probe dir>: markdown table of a ycc.sh probe (request, commit result, DP-1 VOP2 bus format)."""
import json, os, re, sys
P = sys.argv[1]
print("| mode | max bpc | color format | commit | errno/err | DP-1 bus format | output_mode | last-bridge fmt |")
print("|---|---|---|---|---|---|---|---|")
for mode in ("0", "5"):
    for bpc in ("8", "10"):
        for cf in ("AUTO", "RGB", "YUV444", "YUV422", "YUV420"):
            f = f"{P}/m{mode}_{bpc}_{cf}.txt"
            if not os.path.exists(f):
                continue
            t = open(f).read()
            ok, err = "?", ""
            for line in t.splitlines():
                if line.startswith("{"):
                    try:
                        j = json.loads(line); ok = "OK" if j.get("ok") else "FAIL"
                        err = str(j.get("errno", "")) + (" " + j.get("err", "") if j.get("err") else "")
                    except ValueError:
                        pass
                    break
            bus = om = ""
            for blk in re.split(r"(?=Video Port\d)", t):
                # stock15 probe kept no Connector lines; DP-1 is on Video Port2 in every run
                if "Connector: DP-1" in blk or ("Connector:" not in t and blk.startswith("Video Port2")):
                    m = re.search(r"bus_format\[(\w+)\]: (\S+)", blk); o = re.search(r"output_mode\[(\w+)\]", blk)
                    bus = f"{m[1]} {m[2]}" if m else ""; om = o[1] if o else ""
            chains = re.findall(r"ending with bus format (0x\w+)", t)
            print(f"| {mode} | {bpc} | {cf} | {ok} | {err.strip()} | {bus if ok == 'OK' else '-'} | {om if ok == 'OK' else '-'} | {chains[0] if chains else ''} |")
