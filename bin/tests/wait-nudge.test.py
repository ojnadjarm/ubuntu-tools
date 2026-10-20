#!/usr/bin/env python3
"""wait_nudge hints on fixture commands, and the Claude audit hook emitting one under a temp HARNESS_HOME.
Run: python3 wait-nudge.test.py"""
import importlib.util, json, os, subprocess, sys, tempfile

HOME = os.path.expanduser('~/agents')
_s = importlib.util.spec_from_file_location('wait_nudge', f'{HOME}/hooks/wait_nudge.py')
w = importlib.util.module_from_spec(_s)
_s.loader.exec_module(w)
sys.path.insert(0, f'{HOME}/bin/tests/lib')
from budget import budget
bad = 0


def check(name, ok):
    global bad
    print(('ok   ' if ok else 'FAIL ') + name)
    bad |= not ok


def eq(cmd):
    h = w.hint(cmd)
    return h.split('`')[1] if h and 'hand-written' in h else h


CASES = [
    ('until grep -q "^exit" run.log; do sleep 3; done; cat run.log', "wait-for --label wait --file run.log --match '^exit'"),
    ('until grep -q "A\\|B" x.log 2>/dev/null; do sleep 5; done', "wait-for --label wait --file x.log --match 'A|B'"),
    ('while kill -0 4242 2>/dev/null; do sleep 5; done; echo done', 'wait-for --label wait --pid 4242'),
    ('while ps -p $p >/dev/null; do sleep 2; done', 'wait-for --label wait --pid $p'),
    ('until curl -sf localhost:8080/health; do sleep 2; done', "wait-for --label wait --until 'curl -sf localhost:8080/health'"),
    ('while pgrep -f frames-ab.sh >/dev/null; do sleep 30; done', "wait-for --label wait --until '! pgrep -f '\"'\"'[f]rames-ab.sh'\"'\"' >/dev/null'"),
    ('until [ -f out.json ]; do sleep 5; done', "wait-for --label wait --until '[ -f out.json ]'"),
    ('for i in $(seq 30); do curl -sf x && break; sleep 2; done', "wait-for --label wait --until 'curl -sf x'"),
    ('while true; do if [ -s o.txt ]; then break; fi; sleep 5; done', "wait-for --label wait --until '[ -s o.txt ]'"),
]
for cmd, want in CASES:
    got = eq(cmd)
    check(f'{cmd[:50]!r} -> wait-for', got == want or print('     got', got))

check('plain leading sleep 100 nudged', 'sleep 100' in (w.hint('sleep 100; cat tasks/b1.output') or ''))
check('sleep after & launch nudged', 'sleep 45' in (w.hint('nohup node a.mjs > a.log 2>&1 & sleep 45; tail a.log') or ''))
for quiet in ['kill 7301; sleep 1; cat x', 'sleep 3; ls', 'docker stats > d1; sleep 15; docker stats > d2',
              'wait-for --label b --pid 1; sleep 30', 'while read f; do echo $f; done < list',
              'for f in *.log; do grep -c x $f; sleep 1; done', 'echo until done; sleep 2', 'ls -la', '']:
    check(f'no nudge: {quiet[:40]!r}', w.hint(quiet) is None)
import time
t0 = time.time()
w.hint('sleep 1; ' + 'while x; do echo a; ' * 400)
took = time.time() - t0
check(f'an 8 KB command with open while loops scans in {took:.3f} s (budget {budget(0.5):.2f} s)', took < budget(0.5))
check('share counts wait-for vs hand loops',
      w.share([{'tool': 'Bash', 'summary': 'wait-for --label a --pid 1'},
               {'tool': 'Bash', 'summary': 'until grep -q x f; do sleep 1; done'},
               {'tool': 'Bash', 'summary': 'ls'}, {'tool': 'Read', 'summary': 'sleep 99'}]) == (1, 1, 50.0))

with tempfile.TemporaryDirectory() as t:
    hook = f'{HOME}/adapters/claude/hooks/audit-log.py'
    env = dict(os.environ, HARNESS_HOME=t)
    ev = {'hook_event_name': 'PostToolUse', 'tool_name': 'Bash', 'session_id': 's', 'cwd': t,
          'tool_input': {'command': 'until grep -q DONE b.log; do sleep 5; done'}}
    out = subprocess.run([hook], input=json.dumps(ev), capture_output=True, text=True, env=env)
    try:
        ctx = json.loads(out.stdout)['hookSpecificOutput']
    except ValueError:
        ctx = {}
    check('hook prints PostToolUse additionalContext', ctx.get('hookEventName') == 'PostToolUse'
          and 'wait-for --label wait --file b.log --match DONE' in ctx.get('additionalContext', ''))
    check('hook still writes the audit line to the temp log', os.path.exists(f'{t}/log/actions.jsonl'))
    check('hook prints exactly one line per command', len(out.stdout.splitlines()) == 1)
    for cmd in ['ls', 'plan-usage | tail -1']:
        ev['tool_input'] = {'command': cmd}
        out = subprocess.run([hook], input=json.dumps(ev), capture_output=True, text=True, env=env)
        check(f'hook: 0 nudges on plain {cmd!r}, exit 0', out.stdout == '' and out.returncode == 0)
    out = subprocess.run([hook], input=json.dumps({'hook_event_name': 'PostToolUse', 'tool_name': 'Agent',
                         'tool_input': {'prompt': 'until x; do sleep 5; done'}}), capture_output=True, text=True, env=env)
    check('hook: 0 nudges on an Agent launch', out.stdout == '')
    ev.update(agent_id='a1', tool_input={'command': 'until grep -q DONE b.log; do sleep 5; done'})
    out = subprocess.run([hook], input=json.dumps(ev), capture_output=True, text=True, env=env)
    check('hook: 0 nudges from a subagent call (async output would reach the main thread)', out.stdout == '')
raise SystemExit(bad)
