#!/usr/bin/env python3
"""sleep-loop-block PreToolUse hook on fixture commands, then a replay of 7 days of real Bash commands.
Run: python3 sleep-loop-block.test.py"""
import glob, gzip, importlib.util, json, os, subprocess, tempfile, time

HERE = os.path.dirname(os.path.realpath(__file__))
HOOK = os.path.join(HERE, 'sleep-loop-block.py')
_s = importlib.util.spec_from_file_location('wait_nudge', os.path.join(HERE, 'wait_nudge.py'))
w = importlib.util.module_from_spec(_s)
_s.loader.exec_module(w)
WORK = tempfile.mkdtemp(prefix='slb-')
ENV = dict(os.environ, HOME=WORK, HARNESS_HOME=WORK)
bad = 0


def check(name, ok):
    global bad
    print(('ok   ' if ok else 'FAIL ') + name)
    bad |= not ok


def run(cmd, tool='Bash', raw=None):
    """(exit code, parsed stdout or None) of the hook fed one PreToolUse event."""
    ev = raw if raw is not None else json.dumps({'hook_event_name': 'PreToolUse', 'tool_name': tool,
                                                 'tool_input': {'command': cmd}, 'agent_id': 'a1'})
    p = subprocess.run([HOOK], input=ev, capture_output=True, text=True, env=ENV, cwd=WORK, timeout=10)
    return p.returncode, (json.loads(p.stdout) if p.stdout.strip() else None)


def denied(cmd):
    rc, out = run(cmd)
    o = (out or {}).get('hookSpecificOutput', {})
    return rc == 0 and o.get('permissionDecision') == 'deny', o.get('permissionDecisionReason', '')


# Selftest: the hook only reads stdin; it never runs the command it judges.
for cmd in [f'until [ -e {WORK}/x ]; do sleep 1; done; touch {WORK}/must-not-exist',
            f'touch {WORK}/must-not-exist-2; sleep 1']:
    run(cmd)
check('selftest: hook never executes the command',
      not os.path.exists(f'{WORK}/must-not-exist') and not os.path.exists(f'{WORK}/must-not-exist-2'))

DENY = [
    ('until grep -q "^exit" run.log; do sleep 3; done; cat run.log', "wait-for --label wait --file run.log --match '^exit'"),
    ('cd /x && until grep -q "ALL DONE" done.txt; do sleep 15; done', "wait-for --label wait --file done.txt --match 'ALL DONE'"),
    ('S=/tmp/a; until [ -s $S/o.log ] && grep -q ok $S/o.log; do sleep 5; done', "wait-for --label wait --until '[ -s $S/o.log ] && grep -q ok $S/o.log'"),
    ('while kill -0 4242 2>/dev/null; do sleep 5; done; echo done', 'wait-for --label wait --pid 4242'),
    ('while ! grep -q "^rc=" $f; do sleep 5; done', "wait-for --label wait --file $f --match '^rc='"),
    ('until curl -sf localhost:8080/health; do sleep 2; done', "wait-for --label wait --until 'curl -sf localhost:8080/health'"),
    ('for i in $(seq 30); do curl -sf x && break; sleep 2; done', "wait-for --label wait --until 'curl -sf x'"),
    ("timeout 590 bash -c 'until grep -q \"^EXIT\" out/make.log; do sleep 5; done'; tail -5 out/make.log",
     "wait-for --label wait --file out/make.log --match '^EXIT'"),
    ('f=x.log; timeout 500 bash -c "while ! grep -q \'^rc=\' $f; do sleep 5; done"; tail -6 $f',
     "wait-for --label wait --file $f --match '^rc='"),
]
for cmd, want in DENY:
    ok, reason = denied(cmd)
    check(f'deny {cmd[:55]!r}', ok and f'`{want}`' in reason or print('     got', reason))

PASS = [
    'sleep 1', 'sleep 1; ls', 'kill 7301; sleep 1; cat x', 'sleep 120; cat tasks/b1.output', 'watch -n 2 ls',
    "wait-for --label b --until '[ -e f ]'", 'wait-for --label b --pid 1; sleep 30',
    'for f in *.log; do grep -c x $f; sleep 1; done', 'while read f; do echo $f; sleep 1; done < list',
    "echo 'until [ -e f ]; do sleep 1; done'", "grep -n 'until x; do sleep 1; done' notes.md",
    "cat > wait.sh <<'EOF'\nuntil grep -q RC= ci.log; do sleep 20; done\nEOF\necho ok",
    'echo \'{"tool_input":{"command":"until [ -e /etc/hostname ]; do sleep 1; done"}}\' | ./audit-log.py',
    'claude -p "Step 1: run this exact Bash command: until [ -e /etc/hostname ]; do sleep 1; done"',
    'python3 - <<EOF\ncmd = "eval \'until grep -q X f; do sleep 5; done\'"\nEOF',
    'ls -la', '',
]
for cmd in PASS:
    rc, out = run(cmd)
    check(f'pass {cmd[:55]!r}', rc == 0 and out is None or print('     got', rc, out))
rc, out = run('', raw=json.dumps({'tool_name': 'Write', 'tool_input': {'content': 'until x; do sleep 1; done'}}))
check('pass a non-Bash tool', rc == 0 and out is None)
rc, out = run('', raw='not json')
check('fail open on bad input (exit 0, no output)', rc == 0 and out is None)

t0 = time.time()
for _ in range(10):
    run('ls -la; git status')
ms = (time.time() - t0) * 100
check(f'hook latency on a plain command {ms:.0f} ms < 100 ms', ms < 100)

# Replay: every Bash command of the last 7 days in the audit log (summaries, cut at 500 chars).
cut = time.strftime('%Y-%m-%dT%H:%M', time.localtime(time.time() - 7 * 86400))
cmds = []
for p in glob.glob(os.path.expanduser('~/agents/log/actions.jsonl*')):
    with (gzip.open(p, 'rt') if p.endswith('.gz') else open(p)) as f:
        for line in f:
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if r.get('ts', '') >= cut and r.get('tool') == 'Bash':
                cmds.append(r.get('summary', ''))
t0 = time.time()
hits = [c for c in cmds if w.loop_wait(c)]
dt = time.time() - t0
data = [c for c in hits if c.lstrip().startswith(('echo ', 'grep ', 'printf ', 'claude ')) or '<<' in c.split('until')[0]]
print(f'     replay: {len(cmds)} commands, {len(hits)} denied, {len(data)} with the loop in data, {dt:.2f} s')
check('replay: 0 denies where the loop is data (echo/grep/claude -p text, heredoc body)', not data)
check('replay: the parser costs < 1 ms per command', not cmds or dt / len(cmds) < 0.001)
lost = [c for c in hits if not denied(c)[0]]
check(f'replay: the fast path keeps all {len(hits)} denies ({len(lost)} lost)', not lost or print('     lost', lost[:3]))

subprocess.run(['rm', '-rf', WORK])
print('PASS' if not bad else 'FAIL')
raise SystemExit(bad)
