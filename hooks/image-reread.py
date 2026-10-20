#!/usr/bin/python3 -IS
"""Claude Code PreToolUse hook: deny the 4th Read of the same unchanged image in one session context (T495); PostCompact resets that context's counts (T513)."""
import sys

RAW = sys.stdin.buffer.read()
_low = RAW.lower()
COMPACT = b'"postcompact"' in _low
if not COMPACT and (b'"read"' not in _low or not any(e in _low for e in (b'.png', b'.jpg', b'.jpeg', b'.gif', b'.webp'))):
    sys.exit(0)

import json, os

LIMIT = 3
EXTS = ('.png', '.jpg', '.jpeg', '.gif', '.webp')
REASON = ('image-reread (T495): {path} unchanged, read {n}× already; use the earlier view, or crop '
          '(`ffmpeg -i in.png -vf crop=W:H:X:Y out.png`) and Read the crop.')

try:
    d = json.loads(RAW)
    path = str((d.get('tool_input') or {}).get('file_path', '')) if d.get('tool_name') == 'Read' else ''
    run = os.environ.get('XDG_RUNTIME_DIR', '')
    ctx = ''.join(c for c in f"{d.get('session_id', '')}-{d.get('agent_id', '')}" if c.isalnum() or c == '-')
    cdir = os.path.join(run, 'image-reread')
    if d.get('hook_event_name') == 'PostCompact' and run:
        try:
            os.remove(os.path.join(cdir, ctx + '.json'))
        except FileNotFoundError:
            pass
    elif path.lower().endswith(EXTS) and run and os.path.isfile(path):
        st = os.stat(path)
        key = f'{os.path.realpath(path)}|{st.st_mtime_ns}|{st.st_size}'
        os.makedirs(cdir, exist_ok=True)
        cfile = os.path.join(cdir, ctx + '.json')
        try:
            counts = json.load(open(cfile))
        except (OSError, ValueError):
            counts = {}
        n = counts.get(key, 0)
        if n >= LIMIT:
            print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny',
                                                     'permissionDecisionReason': REASON.format(path=path, n=n)}}))
        else:
            counts[key] = n + 1
            tmp = f'{cfile}.{os.getpid()}'
            with open(tmp, 'w') as f:
                json.dump(counts, f)
            os.replace(tmp, cfile)
except Exception:
    pass
sys.exit(0)
