"""### fleet-ci: the newest fleet-ci log's score, ci-load, red and recheck lines."""
import os, re

from .common import AG, latest

KEEP = re.compile(r'^(PASS|FAIL) \d+/\d+|^ci-load|fleet ci red|fleet ci green|^recheck ')


def rows(ctx):
    f = latest(os.path.join(AG, 'log', 'fleet-ci', '*.txt'))
    with open(f, errors='replace') as fh:
        out = [r.rstrip() for r in fh if KEEP.search(r)]
    return [os.path.basename(f)] + (out or ['no score line'])
