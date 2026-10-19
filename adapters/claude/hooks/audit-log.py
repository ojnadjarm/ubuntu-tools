#!/usr/bin/python3 -IS
"""Claude Code PostToolUse/PostToolUseFailure hook: map its event fields onto the generic audit record."""
import importlib.util, json, os, sys

# Relative to this file (resolved through the ~/.claude/hooks symlink), never via HARNESS_HOME —
# that variable names the log directory and a test may point it elsewhere.
_p = os.path.join(os.path.dirname(os.path.realpath(__file__)), '..', '..', '..', 'hooks', 'audit-log.py')
_s = importlib.util.spec_from_file_location('audit_core', _p)
core = importlib.util.module_from_spec(_s)
_s.loader.exec_module(core)
try:
    _n = importlib.util.spec_from_file_location('wait_nudge', os.path.join(os.path.dirname(_p), 'wait_nudge.py'))
    nudge = importlib.util.module_from_spec(_n)
    _n.loader.exec_module(nudge)
except Exception:
    nudge = None

try:
    d = json.load(sys.stdin)
    agent = 'bench' if os.environ.get('PCBENCH_RUN') else os.environ.get('AGENT_NAME', '')
    failed = d.get('hook_event_name') == 'PostToolUseFailure'
    core.record(d.get('tool_name', '?'), d.get('tool_input') or {},
                d.get('cwd', ''), d.get('session_id', ''), agent,
                ok=not failed, error=d.get('error') if failed else '',
                agent_id=d.get('agent_id', ''), agent_type=d.get('agent_type', ''))
    # Async hook output lands in the main thread, so a subagent's nudge would reach the wrong agent.
    main = not d.get('agent_id')
    h = nudge.hint(str((d.get('tool_input') or {}).get('command', ''))) if nudge and main and d.get('tool_name') == 'Bash' else None
    if h:
        print(json.dumps({'hookSpecificOutput': {'hookEventName': d.get('hook_event_name', 'PostToolUse'),
                                                 'additionalContext': h}}))
    if d.get('tool_name') == 'TaskStop':
        import subprocess
        orbit = os.path.join(os.path.dirname(os.path.realpath(__file__)), '..', '..', '..', 'bin', 'orbit-hook')
        p = subprocess.Popen([orbit, 'taskstop'], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
        p.stdin.write(json.dumps(d).encode())
        p.stdin.close()
except Exception:
    pass
sys.exit(0)
