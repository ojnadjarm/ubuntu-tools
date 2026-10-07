#!/usr/bin/env python3
"""Build a code-review selftest home: the template tree plus a 35-day fake audit log and real-looking hook timings."""
import datetime as dt
import gzip
import json
import os
import random
import shutil
import sys

here = os.path.dirname(os.path.abspath(__file__))
home = os.path.abspath(sys.argv[1])
if os.path.exists(home):
    sys.exit(f'build.py: {home} exists')
shutil.copytree(os.path.join(here, 'template'), home, symlinks=True)
rng = random.Random(74)
now = dt.datetime.now().astimezone()
fmt = '%Y-%m-%dT%H:%M:%S%z'


def row(t, summary, tool='Bash'):
    op = summary.split()[0]
    return json.dumps({'ts': t.strftime(fmt), 'session': 'fx%06d' % rng.randrange(10**6), 'cwd': '~/agents',
                       'tool': tool, 'op': op, 'summary': summary}) + '\n'


used = ['orbit-lite start', 'disk-report ~/agents/log', 'log-size ~/agents/log', 'pc status --brief',
        'agents-status', 'guide disk']
old, new = [], []
for day in range(35, -1, -1):
    for _ in range(6):
        t = now - dt.timedelta(days=day, hours=rng.randrange(24), minutes=rng.randrange(60))
        line = row(t, rng.choice(used))
        (old if day > 7 else new).append((t, line))
    if day % 3 == 0:
        t = now - dt.timedelta(days=day, hours=2)
        (old if day > 7 else new).append((t, row(t, 'fleet-demo', tool='Skill')))
log = os.path.join(home, 'agents', 'log')
with gzip.open(os.path.join(log, 'actions.jsonl.1.gz'), 'wt') as fh:
    fh.writelines(l for _, l in sorted(old))
with open(os.path.join(log, 'actions.jsonl'), 'w') as fh:
    fh.writelines(l for _, l in sorted(new))

# Real hook timings (the T73 shape): the meta file lands 0.1-0.6 s after the start hook fires.
with open(os.path.join(log, 'orbit-lite.log'), 'w') as fh:
    fh.write('# ts\tagent_id\thook_ms\tmeta_ms\tlabel_posted\n')
    for i in range(40):
        t = now - dt.timedelta(hours=40 - i)
        lag = rng.choice([0, 0, 90, 140, 180, 220, 260, 310, 380, 450, 520, 610])
        aid = '%09x' % rng.randrange(16**9)
        label = f'T{50 + i % 20} lane {i}' if lag == 0 else 'worker'
        fh.write(f'{t.strftime(fmt)}\t{aid}\t0\t{lag}\t{label}\n')
print(home)
