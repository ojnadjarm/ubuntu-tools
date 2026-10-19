#!/usr/bin/env python3
"""Score `guide` on the hand-labelled real queries in guide-eval.tsv: top-3 hit rate and noise rate (read-only, real KB)."""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
GUIDE = os.environ.get("GUIDE_BIN", os.path.join(HERE, "..", "guide"))


def top3(query):
    """Keys of the first 3 results, as orbit-hook sees them: guide slug or /skill."""
    out = subprocess.run([GUIDE, query], capture_output=True, text=True).stdout.splitlines()
    keys = []
    for line in out:
        m = re.match(r"^(guide|skill) +\S+ (\S+)(?:  → invoke (\S+))?", line)
        if m:
            keys.append(os.path.basename(m[2])[:-3] if m[1] == "guide" else m[3].split()[0])
    return keys[:3]


rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(HERE, "guide-eval.tsv")) if l.strip() and not l.startswith("#")]
hits = labelled = shown = noise = silent_ok = unlabelled = 0
for q, want in rows:
    rel = set() if want == "-" else set(want.split(","))
    got = top3(q)
    bad = [k for k in got if k not in rel]
    shown += len(got)
    noise += len(bad)
    if rel:
        labelled += 1
        hit = any(k in rel for k in got)
        hits += hit
    else:
        unlabelled += 1
        silent_ok += not got
        hit = not got
    if "-v" in sys.argv:
        print(f"{'ok ' if hit else 'MISS'} {q!r:45} → {got}  noise={len(bad)}")
print(f"top3_hit={hits}/{labelled} ({100 * hits / labelled:.0f}%) noise={noise}/{shown} ({100 * noise / max(shown, 1):.0f}%) "
      f"silent_on_none={silent_ok}/{unlabelled}")
