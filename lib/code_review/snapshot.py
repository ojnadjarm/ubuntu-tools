"""sha256 snapshots of trees and their diff (the selftest's outside-fixture check)."""
import hashlib
import json
import os
import re
import sys

SNAP_SKIP = re.compile(r'/(logs|state|__pycache__|node_modules|\.pytest_cache)(/|$)|\.lock$|/log/|/plans/|'
                       r'/research/|/asr-corpus/|/bench/runs/|FILE-CLAIMS\.md$|/drop/|/browser/profile')


def snapshot(roots):
    out = {}
    for root in roots:
        for a, ds, fs in os.walk(root):
            ds[:] = [d for d in ds if not SNAP_SKIP.search(os.path.join(a, d) + '/')]
            for f in fs:
                p = os.path.join(a, f)
                if SNAP_SKIP.search(p) or os.path.islink(p):
                    continue
                try:
                    out[p] = hashlib.sha256(open(p, 'rb').read()).hexdigest()
                except OSError:
                    continue
    return out


def cmd_snapshot(a):
    json.dump(snapshot(a.roots), open(a.out, 'w'))
    print(a.out)


def cmd_snapdiff(a):
    x, y = json.load(open(a.a)), json.load(open(a.b))
    diff = sorted(set(k for k in set(x) | set(y) if x.get(k) != y.get(k)))
    for k in diff:
        print(('changed ' if k in x and k in y else 'added   ' if k in y else 'removed ') + k)
    print(f'{len(diff)} difference(s) over {len(x)} file(s)')
    sys.exit(1 if diff else 0)
