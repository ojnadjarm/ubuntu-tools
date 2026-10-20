"""prep: the run id and args.json for swarm.js (areas, focus, lenses, policy, seen findings, open items, toolsmith lane)."""
import datetime as dt
import glob
import hashlib
import json
import os
import re

from .claims import claimed_by_others
from .common import AGENTS, AREAS, AUDIT, BACKUPS, DATE, FIXTURE, HOME, QUEUE, RULES, STATE, SWARM, rel, run_dir, test_exists
from .evidence import usage
from .policy import policy_rules
from .report import SKIP_VERDICTS
from .snapshot import SNAP_SKIP

TOOLSMITH_CAP = 3
SWEEP_EVERY = 4  # every 4th run reads whole areas; the others read changed files plus a rotation quarter
QUARTERS = 4
LENSES = [
    ('data', 'CODE VS REAL DATA (the T73 method): compare what the code assumes (timings, formats, paths, counts, '
             'ordering) with real logs, transcripts, `agents-log`, index.tsv rows and state files. Cite the log line or number.'),
    ('correctness', 'CORRECTNESS AND EDGE CASES: wrong results, races, unhandled errors that lose data, bad quoting, '
                    'wrong exit codes, missing files, empty input, clock and timezone, concurrency.'),
    ('perf', 'PERF AND IDLE COST: work done every call or every tick that could be cached or skipped, forks in hot '
             'paths, polling loops, large reads, resident processes. Measure before you claim (time, strace -c, counts).'),
    ('value', 'USEFULNESS AND DUPLICATION (judge by usefulness, never by how often it is used): tools, skills, '
              'functions or docs that are NOT USEFUL, and helpers copied between files that should be one. Usage counts and '
              'last-used dates are never a reason on their own; a rarely used restore script or runbook can be among the most '
              'valuable. kind not-useful needs retire_reason = broken (beyond a reasonable fix), duplicate (another item does '
              'the same job at least as well; name it in replacement), superseded (a better existing package, every caller '
              'migrated) or obsolete (the problem it solves no longer exists; show why), argued in evidence. A useful item '
              'that is rarely used because nobody finds it is kind discoverability (fix: guide INDEX line, trigger words, '
              'skill description), never not-useful. Check callers everywhere: `code-review refs`, units, timers, cron, docs.'),
    ('replace', 'REPLACE: an existing package, CLI, MCP server or skill on this machine that now does the job at least '
                'as well as the fleet-made item. Name it and where it is, run both side by side on the same inputs and cite '
                'the result (outputs, exit codes, timings); a replacement whose output differs or is worse is not a finding. '
                'List what every caller would change.'),
]


def load_seen():
    out = {}
    try:
        for line in open(os.path.join(STATE, 'seen.jsonl')):
            try:
                r = json.loads(line)
                out[r['key']] = r
            except (ValueError, KeyError):
                continue
    except OSError:
        pass
    return out


def open_items():
    titles = []
    for f in sorted(glob.glob(os.path.join(QUEUE, '*.md'))):
        try:
            text = open(f).read()
        except OSError:
            continue
        if re.search(r'^status:\s*(proposed|building|built|measuring)', text, re.M):
            titles.append(text.splitlines()[0].lstrip('# ').strip())
    bl = os.path.join(AGENTS, 'toolsmith', 'BACKLOG.md')
    if os.path.isfile(bl):
        for line in open(bl):
            c = [x.strip() for x in line.split('|')]
            if len(c) > 6 and re.fullmatch(r'TSP-\d+', c[2]) and c[5] in ('proposed', 'go', 'measuring'):
                titles.append(f'{c[2]} — {c[3]}')
    return titles


def toolsmith_backlog():
    """Open auto-ok toolsmith proposals for the toolsmith lane: status go then proposed, lowest rank first, at most TOOLSMITH_CAP."""
    rows = []
    try:
        lines = open(os.path.join(AGENTS, 'toolsmith', 'BACKLOG.md')).readlines()
    except OSError:
        return []
    for line in lines:
        c = [x.strip() for x in line.split('|')]
        if len(c) > 6 and c[1].isdigit() and re.fullmatch(r'TSP-\d+', c[2]) and c[4] == 'auto-ok' and c[5] in ('go', 'proposed'):
            p = os.path.join(AGENTS, 'toolsmith', 'proposals', c[2] + '.md')
            if os.path.isfile(p):
                accept = re.findall(r'^- measured by:\s*(.+)$', open(p, errors='replace').read(), re.M)
                rows.append({'id': c[2], 'rank': int(c[1]), 'status': c[5], 'title': c[3], 'path': p,
                             'accept': accept[-1] if accept else ''})
    return sorted(rows, key=lambda r: (r['status'] != 'go', r['rank']))[:TOOLSMITH_CAP]


def area_files(paths):
    """Every reviewable file under an area's paths with its mtime, sorted by path."""
    skip = re.compile(SNAP_SKIP.pattern + r'|/\.git(/|$)')
    out = []
    for root in paths:
        for d, ds, fs in os.walk(root):
            ds[:] = [x for x in ds if not skip.search(os.path.join(d, x) + '/')]
            for f in fs:
                p = os.path.join(d, f)
                if skip.search(p) or os.path.islink(p):
                    continue
                try:
                    out.append((p, os.path.getmtime(p)))
                except OSError:
                    continue
    return sorted(out)


def completed_runs():
    """Earlier runs whose swarm returned, oldest first: (prep time = args.json mtime, was it a full sweep)."""
    out = []
    for d in glob.glob(os.path.join(STATE, 'runs', '*')):
        try:
            res = json.load(open(os.path.join(d, 'result.json')))
            args = json.load(open(os.path.join(d, 'args.json')))
            t = os.path.getmtime(os.path.join(d, 'args.json'))
        except (OSError, ValueError):
            continue
        if isinstance(res, dict) and not res.get('error'):
            out.append((t, any(x.get('sweep', True) for x in args.get('areas', []))))
    return sorted(out)


def focus_plan(runs):
    """(sweep, since, quarter): a full sweep after SWEEP_EVERY - 1 focused runs; focused run k reads rotation quarter k."""
    if not runs:
        return True, 0.0, 0
    k = 0
    for _, sweep in reversed(runs):
        if sweep:
            break
        k += 1
    return k >= SWEEP_EVERY - 1, runs[-1][0], k % QUARTERS


def quarter_of(path):
    return int(hashlib.sha1(rel(path).encode()).hexdigest(), 16) % QUARTERS


def area_focus(paths, sweep, since, quarter):
    """focus = files changed since the last finished run, then (focused runs only) this run's quarter of the rest."""
    files = area_files(paths)
    changed = [p for p, m in files if m > since]
    rest = [] if sweep else [p for p, m in files if m <= since and quarter_of(p) == quarter]
    return {'sweep': sweep, 'focus': changed + rest, 'changed': len(changed), 'files': len(files)}


def cmd_prep(a):
    run = base = f'{DATE}-{dt.datetime.now().strftime("%H%M%S")}'
    n = 1
    while os.path.exists(run_dir(run)) or os.path.exists(os.path.join(BACKUPS, run)):
        n += 1
        run = f'{base}-{n}'
    os.makedirs(STATE, exist_ok=True)
    open(os.path.join(STATE, 'current-run'), 'w').write(run + '\n')
    rdir = run_dir(run)
    os.makedirs(rdir, exist_ok=True)
    sweep, since, quarter = focus_plan(completed_runs())
    areas = []
    for key, paths, tests in AREAS:
        ps = [os.path.join(HOME, p) for p in paths if os.path.exists(os.path.join(HOME, p))]
        if ps:
            areas.append({'key': key, 'paths': ps, 'tests': [t for t in tests if test_exists(t)],
                          **area_focus(ps, sweep, since, quarter)})
    seen = load_seen()
    args = {
        'date': DATE, 'run': run, 'mode': 'fixture' if FIXTURE else 'real', 'home': HOME, 'run_dir': rdir,
        'focus': {'sweep': sweep, 'since': dt.datetime.fromtimestamp(since).isoformat(timespec='seconds'), 'quarter': quarter},
        'rules': RULES, 'swarm': SWARM, 'cli': 'code-review', 'areas': areas,
        'lenses': [{'key': k, 'ask': q} for k, q in LENSES],
        'policy': policy_rules(),
        'skip_verdicts': list(SKIP_VERDICTS),
        'seen': [{'key': k, 'verdict': v.get('verdict'), 'date': v.get('date'), 'title': v.get('title'),
                  'file': v.get('file')} for k, v in seen.items()],
        'claimed': [p for _, p in claimed_by_others('')],
        'open_items': open_items(),
        'toolsmith_backlog': toolsmith_backlog(),
        'audit': {'coverage_days': usage([])['coverage_days'], 'logs': sorted(glob.glob(AUDIT + '*'))},
        'fix_cap_per_area': int(os.environ.get('CR_FIX_CAP', '8')),
    }
    p = os.path.join(rdir, 'args.json')
    with open(p, 'w') as fh:
        json.dump(args, fh, indent=1)
    print(p)
