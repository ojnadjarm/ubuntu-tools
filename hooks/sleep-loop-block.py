#!/usr/bin/python3 -IS
"""Claude Code PreToolUse hook: deny a hand-written Bash wait loop and name its `wait-for` line (TSP-040)."""
import sys

RAW = sys.stdin.buffer.read()
if b'sleep' not in RAW or not (b'until' in RAW or b'while' in RAW or b'for' in RAW):
    sys.exit(0)

import json, os

REASON = ('sleep-loop-block (AGENTS.md §3, TSP-040): hand-written wait loop denied. Run instead, as a '
          'run_in_background Bash call: `{}` (add --job <pid> when a job writes the file; '
          'guide: wait-for-and-stuck-loops).')

try:
    d = json.loads(RAW)
    cmd = str((d.get('tool_input') or {}).get('command', '')) if d.get('tool_name') == 'Bash' else ''
    if 'sleep' in cmd:
        import importlib.util
        _s = importlib.util.spec_from_file_location(
            'wait_nudge', os.path.join(os.path.dirname(os.path.realpath(__file__)), 'wait_nudge.py'))
        nudge = importlib.util.module_from_spec(_s)
        _s.loader.exec_module(nudge)
        line = nudge.loop_wait(cmd)
        if line:
            print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny',
                                                     'permissionDecisionReason': REASON.format(line)}}))
except Exception:
    pass
sys.exit(0)
