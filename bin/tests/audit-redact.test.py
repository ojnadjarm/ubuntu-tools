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
    ('docker exec db mariadb -u root -prootpw moodle', 'rootpw'),
    ('sshpass -phunter2 ssh host', 'hunter2'),
    ('sshpass -p hunter2 ssh host', 'hunter2'),
    ('curl -u admin:hunter2 https://x', 'hunter2'),
    ('curl -s --user admin:hunter2 https://x', 'hunter2'),
    ('mysqldump --password=topsecret db', 'topsecret'),
    ('echo sk-ant-api03-AAAAAAAAAAAAAAAAAAAA', 'sk-ant-api03-AAAAAAAAAAAAAAAAAAAA'),
    ('S=0123456789abcdef0123456789abcdef0123456789abcdef; curl -H "x-dark-eye-key: $S" x', '0123456789abcdef0123456789abcdef0123456789abcdef'),
    ('EYE_KEY=0123456789abcdef0123456789abcdef0123456789abcdef eye health', '0123456789abcdef0123456789abcdef0123456789abcdef'),
    ('EYE_KEY="0123456789abcdef0123456789abcdef0123456789abcdef" eye health', '0123456789abcdef0123456789abcdef0123456789abcdef'),
    ('curl -H "x-dark-eye-key: 0123456789abcdef0123456789abcdef0123456789abcdef" x', '0123456789abcdef0123456789abcdef0123456789abcdef'),
    ('curl -H "x-dark-eye-key: notHexValue" x', 'notHexValue'),
]
KEEP = ['git status --porcelain', 'ls ~/agents/secrets', 'pc status --json',
        "find . -path ./a -prune -print", "find . -type f -not -path './.git/*'",
        'grep -Pn foo x', 'mkdir -p /tmp/x', 'mysql -u root db; mkdir -p /tmp/x', 'mysql -P3306 -h db',
        'mysql -p moodle', 'curl -u admin https://x',
        'git show 0123456789abcdef0123456789abcdef01234567',
        'docker pull php@sha256:' + '0123456789abcdef' * 4]

# TSP-006: tools with no `command` field must not crash and must get a useful op.
SUMMARY_CASES = [
    ('Bash', {'command': 'pc status --json'}, 'pc status', 'pc status --json'),
    ('Read', {'file_path': '/srv/x/agents/hooks/audit-log.py'},
     'Read audit-log.py', '/srv/x/agents/hooks/audit-log.py'),
    ('Grep', {'pattern': 'matcher', 'path': '/srv/x/agents'}, 'Grep matcher', 'matcher'),
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

# TSP-017: op skips `cd ... &&` prefixes and never keeps a trailing `;`.
OP_CASES = [
    ('cd /x && pc status', 'pc status'),
    ('eye health; pgrep -f eye', 'eye health'),
    ('export A=1; docker ps', 'docker ps'),
    ('cd /x', 'cd /x'),
    ('H=/x/home; ls -la', 'ls -la'),
    ('H=/x/home; cd $H && ls', 'ls'),
    ('FOO=1 make test', 'make test'),
    ('T=$(mktemp -d); cd $T && git status', 'git status'),
    ('A="x y" B=2 pc status', 'pc status'),
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
for cmd, want_op in OP_CASES:
    op, _ = m.summarise('Bash', {'command': cmd})
    ok = op == want_op
    bad += not ok
    print(('PASS ' if ok else 'FAIL ') + 'op %r -> %r' % (cmd, op))
op, _ = m.summarise('Task', {'prompt': 'token=sk-live-1234567890123456'})
ok = 'sk-live' not in op
bad += not ok
print(('PASS ' if ok else 'FAIL ') + 'summarise redacts non-Bash args: %r' % op)
_, summary = m.summarise('mcp__x__y', {'body': '{"api_key": "abcdef"}', 'l': [{'t': 'token=zz9'}]})
ok = 'abcdef' not in summary and 'zz9' not in summary
bad += not ok
print(('PASS ' if ok else 'FAIL ') + 'mcp nested JSON values redacted: %r' % summary)
op, _ = m.summarise('Grep', {'pattern': 'x' * 200})
ok = len(op) <= 60
bad += not ok
print(('PASS ' if ok else 'FAIL ') + 'op truncated to %d chars' % len(op))

n = len(CASES) + len(KEEP) + len(SUMMARY_CASES) + len(OP_CASES) + 3
print(('all %d cases pass' % n) if not bad else ('%d FAILURES' % bad))
sys.exit(1 if bad else 0)
