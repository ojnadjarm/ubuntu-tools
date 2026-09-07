#!/usr/bin/env python3
"""Derives the mirrored GetCurrentState (and its xrandr) from the recorded single-monitor one."""
import json
import sys

src, dst, xr = sys.argv[1:4]
s = json.load(open(src))
members = []
for m in s["data"][1]:
    for mode in m[1]:
        mode[6].pop("is-current", None)
    for mode in m[1]:
        if (mode[1], mode[2]) == (1920, 1080):
            mode[6]["is-current"] = {"type": "b", "data": True}
            break
    members.append(m[0])
s["data"][2] = [[0, 0, 1.0, 0, True, members, {}]]
json.dump(s, open(dst, "w"))
open(xr, "w").write("Screen 0: minimum 16 x 16, current 1920 x 1080, maximum 32767 x 32767\n")
