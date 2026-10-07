#!/usr/bin/env python3
"""auditlib.rotated_rows: the one reader of a logrotated jsonl (live + .N.gz). Fixtures only."""
import gzip, json, os, sys, tempfile, time

BIN = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
fail = 0


def check(name, cond, got=''):
    global fail
    print(f'{"auditlib: " + name:64}' + ('OK' if cond else f'FAIL — {got}'))
    fail |= not cond


try:
    sys.path.insert(0, BIN)
    import auditlib
except ImportError as e:
    check('bin/auditlib.py imports', False, e)
    sys.exit(1)

now = time.time()
at = lambda h: time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime(now - h * 3600))
d = tempfile.mkdtemp()
path = os.path.join(d, 'actions.jsonl')


def write(p, hours):
    rows = ''.join(json.dumps({'ts': at(h), 'h': h}) + '\n' for h in hours) + 'not json\n'
    if p.endswith('.gz'):
        with gzip.open(p, 'wt') as f:
            f.write(rows)
    else:
        with open(p, 'w') as f:
            f.write(rows)


write(path, [2, 1])
write(path + '.1.gz', [30, 20])
write(path + '.2.gz', [100, 90])
write(path + '.3.gz', [500])
hs = lambda rows: [r['h'] for r in rows]

got = hs(auditlib.rotated_rows(path, now - 50 * 3600))
check('oldest first, stops at the file that reaches the cut', got == [100, 90, 30, 20, 2, 1], got)
got = hs(auditlib.rotated_rows(path, 0))
check('no cut reads the live file only', got == [2, 1], got)
got = hs(auditlib.rotated_rows(path, now - 10000 * 3600))
check('a cut older than every file reads them all', got == [500, 100, 90, 30, 20, 2, 1], got)
check('a missing log yields nothing', list(auditlib.rotated_rows(path + '.none', now)) == [])

for tool, old in (('agents-log', 'def log_files'), ('toolsmith-inputs', 'def read_log')):
    src = open(os.path.join(BIN, tool)).read()
    check(f'{tool} uses auditlib, no own rotation reader',
          'rotated_rows' in src and old not in src, tool)

print('auditlib.test.py: ' + ('all green' if not fail else 'FAILURES'))
sys.exit(fail)
