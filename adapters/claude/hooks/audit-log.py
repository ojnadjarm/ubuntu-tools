#!/usr/bin/env python3
"""Claude Code PostToolUse hook: map its event fields onto the generic audit record."""
import importlib.util, json, os, sys

# Relative to this file (resolved through the ~/.claude/hooks symlink), never via HARNESS_HOME —
# that variable names the log directory and a test may point it elsewhere.
_p = os.path.join(os.path.dirname(os.path.realpath(__file__)), '..', '..', '..', 'hooks', 'audit-log.py')
_s = importlib.util.spec_from_file_location('audit_core', _p)
core = importlib.util.module_from_spec(_s)
_s.loader.exec_module(core)

try:
    d = json.load(sys.stdin)
    core.record(d.get('tool_name', '?'), d.get('tool_input') or {},
                d.get('cwd', ''), d.get('session_id', ''))
except Exception:
    pass
sys.exit(0)
