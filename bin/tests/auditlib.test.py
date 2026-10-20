#!/usr/bin/env python3
"""auditlib: the rotated jsonl reader and the failure clusters. Fixtures only."""
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
check('read_jsonl: a missing file is empty', auditlib.read_jsonl(path + '.none') == [])
got = [auditlib.parse_age(a) for a in ('90s', '30m', '2h', '7d')]
check('parse_age: s, m, h and d', got == [90, 1800, 7200, 604800], got)
for bad in ('5x', '4days', '', None):
    try:
        auditlib.parse_age(bad)
        got = 'accepted'
    except ValueError as e:
        got = str(e)
    check(f'parse_age refuses {bad!r} with one message', got == f'bad --since {bad!r} (use 90s, 30m, 2h, 7d)', got)

ec = auditlib.error_cluster
bash = lambda cmd, err: ec({'tool': 'Bash', 'op': ' '.join(cmd.split()[:2]), 'summary': cmd, 'error': err})
a = bash('cat notes.md; grep -E x /srv/u/a12.txt', 'Exit code 1\n# notes 12\nleftover output line')
b = bash('sed -n 1,5p b.md; grep foo ~/agents/b7.txt', 'Exit code 1\nother leftover 9')
check('cluster: status command kept, leftover output dropped', a == b == 'grep · exit 1', (a, b))
c = bash('ls; echo "a;b" | head -3; systemctl --user is-active x.service', 'Exit code 3\nrc=0\ninactive')
d = bash('pc units stop x --apply 2>&1; systemctl --user is-active x.service', 'Exit code 3\nrollback: pc undo dm7j1oxl9yly\ninactive')
check('cluster: last command after ; and quotes, not the first', c == d == 'systemctl · exit 3', (c, d))
e = bash("cat > f.py <<'EOF'\nprint(1); x\nEOF\npython3 f.py", 'Exit code 1\n1\nTraceback (most recent call last):\n  File "f.py", line 1\nNameError: name x')
check('cluster: heredoc skipped, Traceback names its error', e == 'exit 1 · NameError', e)
f = bash('mkdir -p a; brief-lint x', 'Exit code 127\nPASS 3\n/bin/bash: line 4: brief-lint: command not found')
g = bash('cd d; ls; cp a b', 'Exit code 1\nls: cannot access \'/tmp/x/run\': No such file or directory')
h = bash('touch x', 'Exit code 1\nok 3\npwd: error retrieving current directory: getcwd: cannot access parent directories')
check('cluster: known patterns name the error alone',
      (f, g, h) == ('exit 127 · command not found', 'exit 1 · No such file or directory', 'exit 1 · cwd was deleted (getcwd)'), (f, g, h))
i = bash('grep -rn x .; sed -n 1p y', 'Exit code 97\nKB/a.md:18: lots of leftover')
check('cluster: known exit code names a cut message', i == 'exit 97 · refused inside the code-review sandbox', i)
j = bash('npx tsc --noEmit', 'Exit code 2\nsrc/a.ts(3,1): error TS2304: Cannot find name')
k = bash('ffmpeg -i a.webm b.wav', 'Exit code 1\n-rw-r 38144062 a.webm\n[opus @ 0x6044310d3500] Error parsing Opus packet header.\n3.29 s')
check('cluster: tsc code; else last diagnostic line, ids folded',
      (j, k) == ('exit 2 · error TS2304', 'ffmpeg · exit 1 · [opus @ <id>] Error parsing Opus packet header.'), (j, k))
check('cluster: pc keeps its verb', ec({'op': 'pc status', 'error': 'Exit code 1'}) == 'pc status · exit 1', ec({'op': 'pc status', 'error': 'Exit code 1'}))
c = ec({'tool': 'WebFetch', 'op': 'WebFetch https://x.org/a', 'error': 'Command failed with no output'})
check('cluster: no exit code keeps the first line', c == 'WebFetch · Command failed with no output', c)
long = bash('grep x y; ' + 'z' * 500, 'Exit code 1')
check('cluster: a cut summary falls back to the op', long == 'grep · exit 1', long)

cls = lambda cmd, err: auditlib.error_class({'tool': 'Bash', 'op': ' '.join(cmd.split()[:2]), 'summary': cmd, 'error': err})
classes = (cls('grep -rn x .', 'Exit code 97\nleftover'),
           cls('ls; git log -3', 'Exit code 1\ngit: refused inside the code-review sandbox'),
           cls('pc units stop x --user --apply; systemctl --user is-active x.service', 'Exit code 3\ninactive'),
           cls('ls; which eye-tap claims', 'Exit code 1'),
           cls('grep -q foo bar.txt', 'Exit code 1'),
           cls('ls; [ -f /x ]', 'Exit code 1'),
           cls('bash ~/agents/bin/tests/pulse-5h-reset.test.sh', 'Exit code 1\nFAIL — got 3'),
           cls('grep -q foo bar.txt', 'Exit code 2\ngrep: bar.txt: No such file or directory'),
           cls('bash build.sh', 'Exit code 1\nFAIL — got 3'),
           cls('python3 f.py', 'Exit code 1\nKeyError: x'))
check('error_class: guarded, probe, red-first, else real',
      classes == ('guarded', 'guarded', 'probe', 'probe', 'probe', 'probe', 'red-first', 'real', 'real', 'real'), classes)
check('error_class: a non-Bash failure is real',
      auditlib.error_class({'tool': 'Read', 'op': 'Read', 'error': 'File does not exist'}) == 'real')

check('outcome_rows: clamped to the first row with an outcome',
      auditlib.outcome_rows([{}, {'ok': True}, {}]) == [{'ok': True}, {}] and auditlib.outcome_rows([{}]) == [],
      auditlib.outcome_rows([{}, {'ok': True}, {}]))

import subprocess
hd = tempfile.mkdtemp()
err = 'Exit code 1\n' + ''.join(f'progress line {i:03} ' + 'x' * 40 + '\n' for i in range(40)) + 'FATAL: disk quota exceeded'
ev = {'hook_event_name': 'PostToolUseFailure', 'tool_name': 'Bash', 'tool_input': {'command': 'make all'},
      'session_id': 's', 'error': err, 'agent_id': 'a'}
hook = os.path.join(os.path.dirname(BIN), 'adapters', 'claude', 'hooks', 'audit-log.py')
subprocess.run([hook], input=json.dumps(ev).encode(), env=dict(os.environ, HARNESS_HOME=hd))
ev.update(hook_event_name='PostToolUse', error='')
subprocess.run([hook], input=json.dumps(ev).encode(), env=dict(os.environ, HARNESS_HOME=hd))
got = [json.loads(l) for l in open(os.path.join(hd, 'log', 'actions.jsonl'))]
e = got[0].get('error', '')
check('hook: 2 KB failure keeps head + tail error, … marker',
      len(err) > 2000 and e.startswith('Exit code 1') and e.endswith('FATAL: disk quota exceeded')
      and '\n…\n' in e and len(e) <= 403, (len(err), len(e), e[-60:]))
check('hook: clipped error still clusters on the tail', auditlib.error_cluster(got[0]) == 'make · exit 1 · FATAL: disk quota exceeded', auditlib.error_cluster(got[0]))
check('hook: successful call has no error field', got[1].get('ok') is True and 'error' not in got[1], got[1])

for tool, old in (('agents-log', 'def log_files'), ('toolsmith-inputs', 'def read_log')):
    src = open(os.path.join(BIN, tool)).read()
    check(f'{tool} uses auditlib, no own rotation reader',
          'rotated_rows' in src and old not in src, tool)

for tool in ('toolsmith-inputs', 'agent-verify', 'pc-failures', '../hooks/wait_nudge.py'):
    src = open(os.path.join(BIN, tool)).read()
    check(f'{tool} uses auditlib, no own age map or jsonl reader',
          "'m': 60" not in src and 'gzip.open' not in src and 'from auditlib import' in src, tool)

print('auditlib.test.py: ' + ('all green' if not fail else 'FAILURES'))
sys.exit(fail)
