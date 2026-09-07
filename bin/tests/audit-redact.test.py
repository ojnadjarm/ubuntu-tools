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
print(('all %d cases pass' % (len(CASES) + len(KEEP))) if not bad else ('%d FAILURES' % bad))
sys.exit(1 if bad else 0)
