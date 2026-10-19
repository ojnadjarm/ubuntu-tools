#!/usr/bin/env python3
"""subagent-stop-gate on fixtures: missing or red check.json blocks (exit 2); green, stop_hook_active, no ticket, no CHECK pass.
Sandboxed: HOME and AGENT_WORK are temporary; the selftest proves the real evidence folder is never read."""
import json, os, shutil, subprocess, sys, tempfile

HOOK = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'subagent-stop-gate.py')
root = tempfile.mkdtemp(prefix='stop-gate-test-')
AW = f'{root}/aw'
ENV = dict(os.environ, HOME=root, AGENT_WORK=AW)
SESS = f'{root}/.claude/projects/-p/sess'
bad = 0


def check(name, ok):
    global bad
    print(('ok   ' if ok else 'FAIL ') + name)
    bad |= not ok


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w').write(text)


def brief(ticket, check=True):
    path = f'{AW}/briefs/{ticket}-fixture.md'
    write(path, f'# {ticket}\n' + ('CHECK: true\n' if check else 'no check line\n'))
    return path


def agent(aid, prompt, workflow=False):
    path = f"{SESS}/subagents/{'workflows/wf_1/' if workflow else ''}agent-{aid}.jsonl"
    rows = [{'type': 'user', 'message': {'role': 'user', 'content': prompt}},
            {'type': 'assistant', 'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': 'done'}]}}]
    write(path, ''.join(json.dumps(r) + '\n' for r in rows))
    return path


def evidence(ticket, ok):
    write(f'{AW}/evidence/{ticket}/check.json', json.dumps({'ticket': ticket, 'rc': 0 if ok else 1, 'ok': ok}))


def run(hook):
    p = subprocess.run([HOOK], input=json.dumps(hook), text=True, env=ENV, capture_output=True, timeout=10)
    return p.returncode, p.stderr


def stop(aid, path=None, active=False):
    h = {'hook_event_name': 'SubagentStop', 'session_id': 'sess', 'transcript_path': f'{SESS}.jsonl',
         'agent_id': aid, 'stop_hook_active': active}
    if path:
        h['agent_transcript_path'] = path
    return run(h)


# Selftest: a ticket green in the sandbox must be judged by the sandbox, not by the real ~/agent-work.
real = os.path.expanduser('~/agent-work')
check('selftest: sandbox AGENT_WORK is not the real one', os.path.realpath(AW) != os.path.realpath(real))
b = brief('T9001')
tp = agent('a1', f'Your brief: {b}. Read it and do it.')
rc, err = stop('a1', tp)
check('selftest: sandbox evidence read (missing there → 2)', rc == 2 and AW in err)

check('missing check.json → 2', rc == 2 and 'agent-verify' in err)

evidence('T9001', False)
rc, err = stop('a1', tp)
check('"ok": false → 2', rc == 2 and 'red' in err)

write(f'{AW}/evidence/T9001/check.json', '{not json')
check('corrupt check.json → 2', stop('a1', tp)[0] == 2)

evidence('T9001', True)
check('ok → 0', stop('a1', tp) == (0, ''))

evidence('T9001', False)
check('stop_hook_active → 0 (even when red)', stop('a1', tp, active=True)[0] == 0)

tp = agent('a2', 'Look at the screen and tell me what you see.')
check('brief with no ticket → 0', stop('a2', tp)[0] == 0)

b = brief('T9002', check=False)
tp = agent('a3', f'Your brief: {b}.')
check('brief with no CHECK line → 0', stop('a3', tp)[0] == 0)

check('brief file missing → 0', stop('a4', agent('a4', f'Your brief: {AW}/briefs/T9003-gone.md.'))[0] == 0)

b = brief('T9004')
agent('a5', [{'type': 'text', 'text': f'Brief `{b.replace(root, "~")}` — do it.'}], workflow=True)
rc, err = stop('a5')
check('no agent_transcript_path: found by agent_id under subagents/**, ~ and backticks parsed → 2', rc == 2 and 'T9004' in err)
evidence('T9004', True)
check('same, green → 0', stop('a5')[0] == 0)

check('bad stdin → 0 (fail open)', subprocess.run([HOOK], input='nope', text=True, env=ENV,
                                                 capture_output=True).returncode == 0)

shutil.rmtree(root)
sys.exit(1 if bad else 0)
