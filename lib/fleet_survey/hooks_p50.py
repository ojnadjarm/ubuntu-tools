"""### hooks p50 (--measure): per-call settings.json hooks x5 on a fixture event in a mktemp sandbox."""
import json, os, shutil, tempfile

from .common import p50, short

HOOK_EVENTS = ('PreToolUse', 'PostToolUse', 'PostToolUseFailure')


def rows(ctx):
    """The settings.json PreToolUse/PostToolUse/PostToolUseFailure hooks x5 on a fixture event, all state in a mktemp dir."""
    with open(os.path.expanduser('~/.claude/settings.json')) as fh:
        hooks = json.load(fh).get('hooks') or {}
    box = tempfile.mkdtemp(prefix='fleet-survey-hooks.')
    try:
        png = os.path.join(box, 'x.png')
        open(png, 'wb').close()
        env = {**os.environ, 'HARNESS_HOME': box, 'HOME': box, 'XDG_RUNTIME_DIR': box, 'AGENT_NAME': 'fleet-survey'}
        out = []
        for ev in HOOK_EVENTS:
            for grp in hooks.get(ev) or []:
                tool = grp.get('matcher') if grp.get('matcher') not in (None, '', '*') else 'Bash'
                event = json.dumps({'session_id': 'fleet-survey', 'hook_event_name': ev, 'tool_name': tool, 'cwd': box,
                                    'tool_input': {'command': 'ls', 'file_path': png}, 'tool_response': {}, 'error': 'x'})
                for h in grp.get('hooks') or []:
                    cmd = os.path.expandvars(h.get('command', ''))
                    mid, ms, rc = p50(['bash', '-c', cmd], 5, env=env, stdin=event, timeout=h.get('timeout') or 5)
                    out.append(f'{mid:6.0f} ms p50  {"/".join(map(str, ms))}  rc {rc}  {ev}:{tool}  {short(cmd)}')
        log = os.path.join(box, 'log', 'actions.jsonl')
        n = sum(1 for _ in open(log)) if os.path.isfile(log) else 0
        return [f'{len(out)} hooks x5, load1 {os.getloadavg()[0]:.1f}; {n} audit rows landed in the sandbox'] + out
    finally:
        shutil.rmtree(box, ignore_errors=True)
