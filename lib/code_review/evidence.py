"""Evidence for lanes: audit-log usage per name and references to an item."""
import datetime as dt
import glob
import json
import os
import re

from auditlib import rotated_rows, row_stamp

from .common import AGENTS, AUDIT, AW_REL, HOME, NOW, UNUSED_DAYS, absp, rel

REF_DIRS = [f'{AW_REL}/briefs', 'agents/KB', 'agents/units', 'agents/bin', 'agents/hooks', 'agents/adapters',
            'agents/eye-relay', 'agents/dashboard', 'agents/README.md', 'agents/RUNNER.md', 'agents/Makefile',
            'agents/install.sh', 'CLAUDE.md', 'agents/ORCHESTRATOR.md', '.claude/skills', '.claude/settings.json', '.config/systemd/user']
REF_SKIP = re.compile(r'/(state|logs|__pycache__|node_modules|\.git|plans|mockups)/')


def usage(names, days=UNUSED_DAYS):
    """Uses of each name in the audit log inside the window, last use, and how many days the log covers."""
    cut = NOW - days * 86400
    pats = {n: re.compile(r'(?<![\w.-])' + re.escape(n) + r'(?![\w-])') for n in names}
    res = {n: {'uses': 0, 'last': None} for n in names}
    oldest = None
    for row in rotated_rows(AUDIT, cut):
        t = row_stamp(row)
        if t is None:
            continue
        line = json.dumps(row)
        oldest = t if oldest is None else min(oldest, t)
        for n, rx in pats.items():
            if rx.search(line):
                if t >= cut:
                    res[n]['uses'] += 1
                if not res[n]['last'] or t > res[n]['last']:
                    res[n]['last'] = t
    cover = 0 if oldest is None else round((NOW - oldest) / 86400, 1)
    for n in res:
        if res[n]['last']:
            res[n]['last'] = dt.datetime.fromtimestamp(res[n]['last']).isoformat(timespec='seconds')
    return {'window_days': days, 'coverage_days': cover, 'names': res}


def refs(path):
    """Files outside the item that mention its name (briefs, KB, units, tests, bin, skills, dashboard, settings)."""
    target = absp(path)
    name = os.path.basename(target.rstrip('/'))
    rx = re.compile(r'(?<![\w.-])' + re.escape(name) + r'(?![\w-])')
    hits = []
    extra = [os.path.relpath(f, HOME) for f in glob.glob(os.path.join(AGENTS, '*', 'BRIEF.md'))
             + glob.glob(os.path.join(AGENTS, '*', 'agent.env')) + glob.glob(os.path.join(AGENTS, '*.md'))]
    for d in REF_DIRS + extra:
        root = os.path.join(HOME, d)
        files = [root] if os.path.isfile(root) else \
            [os.path.join(a, f) for a, _, fs in os.walk(root) for f in fs] if os.path.isdir(root) else []
        for f in files:
            if f == target or f.startswith(target.rstrip('/') + '/') or REF_SKIP.search('/' + os.path.relpath(f, HOME)):
                continue
            try:
                if not os.path.isfile(f) or os.path.getsize(f) > 2_000_000:
                    continue
                with open(f, errors='replace') as fh:
                    for i, line in enumerate(fh, 1):
                        if rx.search(line):
                            hits.append(f'{rel(f)}:{i}')
                            break
            except (OSError, UnicodeDecodeError):
                continue
    return sorted(set(hits))
