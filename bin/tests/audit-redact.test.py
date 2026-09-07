#!/usr/bin/env python3
"""Redaction cases for the audit core ~/agents/hooks/audit-log.py (D3, GH09).
Run: python3 audit-redact.test.py"""
import importlib.util, os, sys

_p = os.path.expanduser('~/agents/hooks/audit-log.py')
_s = importlib.util.spec_from_file_location('audit_core', _p)
m = importlib.util.module_from_spec(_s)
_s.loader.exec_module(m)

CASES = [
    ('curl -H "Authorization: Bearer sk-ant-SECRET123456789" x', 'sk-ant-SECRET123456789'),
    ('Bearer ghp_abcdefghijklmnopqrstuvwxyz0123', 'ghp_abcdefghijklmnopqrstuvwxyz0123'),
    ('{"token": "sk-live-9999999999999999"}', 'sk-live-9999999999999999'),
    ('{"password": "hunter2"}', 'hunter2'),
    ('{"secret": "s3cr3tvalue"}', 's3cr3tvalue'),
    ('{"api_key": "abc123def456"}', 'abc123def456'),
    ('PGPASSWORD=hunter2 psql -U moodle', 'hunter2'),
    ('export API_KEY=abc123', 'abc123'),
    ('mysql -psuperpw -u root', 'superpw'),
    ('mysqldump --password=topsecret db', 'topsecret'),
    ('echo sk-ant-api03-AAAAAAAAAAAAAAAAAAAA', 'sk-ant-api03-AAAAAAAAAAAAAAAAAAAA'),
]
KEEP = ['git status --porcelain', 'ls ~/agents/secrets', 'pc status --json']

# TSP-006: tools with no `command` field must not crash and must get a useful op.
SUMMARY_CASES = [
    ('Bash', {'command': 'pc status --json'}, 'pc status', 'pc status --json'),
    ('Read', {'file_path': '/home/x/agents/hooks/audit-log.py'},
     'Read audit-log.py', '/home/x/agents/hooks/audit-log.py'),
    ('Grep', {'pattern': 'matcher', 'path': '/home/x/agents'}, 'Grep matcher', 'matcher'),
    ('Glob', {'pattern': '**/*.py'}, 'Glob **/*.py', '**/*.py'),
    ('WebSearch', {'query': 'systemd timer OnCalendar syntax'},
     'WebSearch systemd timer OnCalendar syntax', 'systemd timer OnCalendar syntax'),
    ('WebFetch', {'url': 'https://code.claude.com/docs/en/hooks', 'prompt': 'p'},
     'WebFetch https://code.claude.com/docs/en/hooks',
     'https://code.claude.com/docs/en/hooks'),
    ('Task', {'description': 'check timers', 'prompt': 'go'}, 'Task check timers',
     'check timers'),
    ('TodoWrite', {}, 'TodoWrite', ''),
]

bad = 0
for text, leak in CASES:
    out = m.redact(text)
    ok = leak not in out and '<redacted>' in out
    bad += not ok
    print(('PASS ' if ok else 'FAIL ') + text + '  ->  ' + out)
for text in KEEP:
    ok = m.redact(text) == text
    bad += not ok
    print(('PASS ' if ok else 'FAIL ') + 'unchanged: ' + text)
for tool, ti, want_op, want_sum in SUMMARY_CASES:
    op, summary = m.summarise(tool, ti)
    ok = (op, summary) == (want_op, want_sum)
    bad += not ok
    print(('PASS ' if ok else 'FAIL ') + 'summarise %s -> %r / %r' % (tool, op, summary))
op, _ = m.summarise('Task', {'prompt': 'token=sk-live-1234567890123456'})
ok = 'sk-live' not in op
bad += not ok
print(('PASS ' if ok else 'FAIL ') + 'summarise redacts non-Bash args: %r' % op)
op, _ = m.summarise('Grep', {'pattern': 'x' * 200})
ok = len(op) <= 60
bad += not ok
print(('PASS ' if ok else 'FAIL ') + 'op truncated to %d chars' % len(op))

n = len(CASES) + len(KEEP) + len(SUMMARY_CASES) + 2
print(('all %d cases pass' % n) if not bad else ('%d FAILURES' % bad))
sys.exit(1 if bad else 0)
