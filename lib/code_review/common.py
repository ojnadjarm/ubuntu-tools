"""Shared roots, run id and small helpers; read from the environment at import (CR_HOME, CR_DATE, CR_NOW, CR_RUN)."""
import datetime as dt
import fcntl
import os
import re
import sys
import time

from agent_work import agent_work

REAL_HOME = os.path.expanduser('~')
HOME = os.path.abspath(os.environ.get('CR_HOME') or REAL_HOME)
FIXTURE = HOME != REAL_HOME
AGENTS = os.path.join(HOME, 'agents')
AW_REL = os.path.relpath(agent_work(), REAL_HOME)
SKILLS = os.path.join(HOME, '.claude', 'skills')
ME = os.path.join(AGENTS, 'code-review')
STATE = os.path.join(ME, 'state')
BACKUPS = os.path.join(AGENTS, 'backups', 'code-review')
RETIRED = os.path.join(AGENTS, 'backups', 'retired')
CLAIMS = os.path.join(AGENTS, 'FILE-CLAIMS.md')
QUEUE = os.path.join(AGENTS, 'improve', 'queue')
AUDIT = os.path.join(AGENTS, 'log', 'actions.jsonl')
SWARM = os.path.join(REAL_HOME, 'agents', 'code-review', 'swarm.js')
RULES = os.path.join(REAL_HOME, 'agents', 'code-review', 'LANES.md')
DATE = os.environ.get('CR_DATE') or dt.date.today().isoformat()
NOW = float(os.environ.get('CR_NOW') or time.time())
UNUSED_DAYS = 28

AREAS = [  # key, paths under HOME, test commands (run from HOME)
    ('bin', ['agents/bin'], ['bash agents/bin/tests/run.sh']),
    ('dashboard', ['agents/dashboard'],
     ['cd agents/dashboard && python3 -m pytest tests -q', 'cd agents/dashboard && node tests/test_pronunciation_page.js']),
    ('plumbing', ['agents/hooks', 'agents/eye-relay', 'agents/adapters', 'agents/units'], ['bash agents/bin/tests/run.sh']),
    ('skills', ['.claude/skills'], ['code-review lint skills']),
    ('guides', ['agents/KB/guides'], ['code-review lint guides']),
]


def die(msg, rc=1):
    print(f'code-review: {msg}', file=sys.stderr)
    sys.exit(rc)


def rel(p):
    p = os.path.abspath(os.path.expanduser(p) if p.startswith('~') and not FIXTURE else p)
    return os.path.relpath(p, HOME)


def absp(p):
    if p.startswith('~/'):
        p = os.path.join(HOME, p[2:])
    return os.path.abspath(p if os.path.isabs(p) else os.path.join(HOME, p))


def locked(path, fn):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + '.lock', 'w') as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        return fn()


def current_run():
    """The run id prep chose (date-HHMMSS): backups and run dirs are keyed by it, so a same-day rerun never collides."""
    if os.environ.get('CR_RUN'):
        return os.environ['CR_RUN']
    try:
        return open(os.path.join(STATE, 'current-run')).read().strip() or DATE
    except OSError:
        return DATE


def run_dir(run=None):
    return os.path.join(STATE, 'runs', run or current_run())


def test_exists(t):
    m = re.search(r'(agents/[^\s&]+)', t)
    return not m or os.path.exists(os.path.join(HOME, m.group(1)))
