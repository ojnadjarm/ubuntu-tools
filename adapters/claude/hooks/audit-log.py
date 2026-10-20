#!/usr/bin/python3 -SI
"""Claude Code PostToolUse/PostToolUseFailure hook: map its event fields onto the generic audit record."""
import posix, sys
from _frozen_importlib_external import SourceFileLoader  # importlib.machinery's loader, without importing importlib


def here():
    """This file's directory, through a symlink to it (__file__ is absolute)."""
    f = __file__
    try:
        while True:
            t = posix.readlink(f)
            f = t if t.startswith('/') else f.rpartition('/')[0] + '/' + t
    except OSError:
        return f.rpartition('/')[0]


def load(name, path):
    """The module at path, through its bytecode cache."""
    m = type(sys)(name)
    SourceFileLoader(name, path).exec_module(m)
    return m


# Relative to this file, never via HARNESS_HOME: that variable names the log directory and a test may point it elsewhere.
HOOKS = here() + '/../../../hooks'
core = load('audit_core', HOOKS + '/audit-log.py')


def load_nudge():
    """The wait_nudge module beside the audit core, or None."""
    try:
        return load('wait_nudge', HOOKS + '/wait_nudge.py')
    except Exception:
        return None

try:
    d = core.loads(sys.stdin.read())
    env = posix.environ
    agent = 'bench' if env.get(b'PCBENCH_RUN') else env.get(b'AGENT_NAME', b'').decode('utf-8', 'surrogateescape')
    failed = d.get('hook_event_name') == 'PostToolUseFailure'
    core.record(d.get('tool_name', '?'), d.get('tool_input') or {},
                d.get('cwd', ''), d.get('session_id', ''), agent,
                ok=not failed, error=d.get('error') if failed else '',
                agent_id=d.get('agent_id', ''), agent_type=d.get('agent_type', ''))
    # Async hook output lands in the main thread, so a subagent's nudge would reach the wrong agent.
    main = not d.get('agent_id')
    cmd = str((d.get('tool_input') or {}).get('command', ''))
    # wait_nudge.hint() is None without `sleep` or with `wait-for`; its re import is skipped then.
    nudge = load_nudge() if main and d.get('tool_name') == 'Bash' and 'sleep' in cmd and 'wait-for' not in cmd else None
    h = nudge.hint(cmd) if nudge else None
    if h:
        print(core.dumps({'hookSpecificOutput': {'hookEventName': d.get('hook_event_name', 'PostToolUse'),
                                                 'additionalContext': h}}))
    if d.get('tool_name') == 'TaskStop':
        import subprocess
        p = subprocess.Popen([here() + '/../../../bin/orbit-hook', 'taskstop'], stdin=subprocess.PIPE,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        p.stdin.write(core.dumps(d).encode())
        p.stdin.close()
except Exception:
    pass
sys.exit(0)
