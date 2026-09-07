#!/usr/bin/env python3
"""Merge (or remove) this harness's hooks in ~/.claude/settings.json — idempotent.

usage: merge-settings.py install|uninstall <settings.json> <fragment.json> <harness-home>

Adds exactly one group per event, dropping any earlier copy of the same command or of a
command the fragment supersedes. Every other key — permissions, model, effortLevel, the
Moodle Stop hook — is preserved byte for byte. Prints "no changes" when nothing moved.
"""
import json, os, sys

if len(sys.argv) != 5 or sys.argv[1] not in ("install", "uninstall"):
    sys.exit(__doc__)
mode, spath, fpath, home = sys.argv[1:]

frag = json.load(open(fpath))
def expand(o):
    if isinstance(o, str):
        return o.replace("@HARNESS_HOME@", home)
    if isinstance(o, list):
        return [expand(x) for x in o]
    if isinstance(o, dict):
        return {k: expand(v) for k, v in o.items()}
    return o
frag = expand(frag)

data = json.load(open(spath)) if os.path.exists(spath) else {}
before = json.dumps(data, indent=2)
hooks = data.setdefault("hooks", {})

ours = set(frag.get("_supersedes", []))
for groups in frag["hooks"].values():
    for g in groups:
        for h in g.get("hooks", []):
            ours.add(h["command"])

# Assigning an existing key keeps its position, so the file's key order never churns.
for event, groups in frag["hooks"].items():
    kept = [g for g in hooks.get(event, [])
            if not any(h.get("command") in ours for h in g.get("hooks", []))]
    if mode == "install":
        kept = kept + groups
    if kept:
        hooks[event] = kept
    else:
        hooks.pop(event, None)
if not hooks:
    data.pop("hooks", None)

after = json.dumps(data, indent=2)
if after == before:
    print("no changes")
    sys.exit(0)

out = os.environ.get("SETTINGS_OUT", spath)
tmp = out + ".tmp"
with open(tmp, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
os.replace(tmp, out)
print(f"settings {mode}ed: {out}")
