"""### shipped: per-wave backlog counts and the open/unticketed (or every) item with its T-number."""
import glob, os, re

from .common import AW, NA, run, short


def _history():
    with open(os.path.join(AW, 'history.md'), errors='replace') as fh:
        return {m.group(1) for r in fh if 'brief written' not in r
                for m in [re.match(r'(?:[-*]\s+|(?=\d{4}-\d\d-\d\d\s))(?:\d{4}-\d\d-\d\d\s+)?(?:\d\d:\d\d\s+)?\**(T\d+)', r)] if m}


def _wave_tags():
    """{(wave, item): [T-id]} from history `T<n> (wave N #k)` / `(w18 #13)` tags."""
    tags = {}
    with open(os.path.join(AW, 'history.md'), errors='replace') as fh:
        for t, w, k in re.findall(r'\b(T\d+)\**\s*\((?:wave|w)\s*(\d+) #(\d+)\)', fh.read()):
            tags.setdefault((w, int(k)), []).append(t)
    return tags


def _double_used():
    try:
        return {r.split()[0] for r in run('ticket-id', 'dups') if r.strip()}
    except NA:
        return set()


def rows(ctx):
    """Every wave backlog item: planner#item, T-number(s) from a brief, its heading or a history wave tag, shipped / open / unticketed."""
    has_hist = os.path.isfile(os.path.join(AW, 'history.md'))
    done, tags = (_history(), _wave_tags()) if has_hist else (set(), {})
    dups = _double_used()
    owner = {}
    for f in glob.glob(os.path.join(AW, 'briefs', 'T*.md')):
        with open(f, errors='replace') as fh:
            m = re.match(r'# (T\d+) — .*?#(\d+) \(from \S*/(T\d+)/BACKLOG\.md\)', fh.readline())
        if m:
            owner.setdefault((m.group(3), int(m.group(2))), []).append(m.group(1))
    backlogs = glob.glob(os.path.join(AW, 'research', '*', 'T*', 'BACKLOG.md'))
    if not backlogs:
        raise NA(f'no {short(AW)}/research/*/T*/BACKLOG.md')
    out = []
    for f in sorted(backlogs, key=lambda p: int(os.path.basename(os.path.dirname(p))[1:])):
        planner = os.path.basename(os.path.dirname(f))
        with open(f, errors='replace') as fh:
            text = fh.read()
        first = text.split('\n', 1)[0]
        wave = re.search(r'wave[- ](\d+)', first)
        moodle = re.search(r'moodle harness wave', first, re.I)
        label = ('moodle wave' if moodle else 'wave') + ' ' + (f'{wave.group(1)} {planner}' if wave else planner)
        wave = None if moodle else wave
        items, n = [], {'shipped': 0, 'open': 0, 'unticketed': 0}
        heads = re.findall(r'^## (?:(\d+)\.\s+(.+)|(T\d+)\s+(?:·\s+)?(.+))$', text, re.M)
        for k, (num, title, tid, ttitle) in enumerate(heads, 1):
            num, title = int(num or k), title or f'{tid} {ttitle}'
            head = re.match(r'(T\d+)\s+(.*)', title)
            if head:
                title = head.group(2)
            ts = owner.get((planner, num)) or ([head.group(1)] if head else
                                               tags.get((wave.group(1), num), []) if wave else [])
            ts = sorted(set(ts), key=lambda t: int(t[1:]))
            state = 'unticketed' if not ts else 'shipped' if any(t in done for t in ts) else 'open'
            n[state] += 1
            ids = ','.join(t + '*' * (t in dups) for t in ts) or '-'
            if ctx.shipped == 'all' or state != 'shipped':
                items.append(f'{planner}#{num:<2} {ids:5} {state:10} {title[:110]}')
        out.append(f'{label}: {sum(n.values())} items, '
                   + ', '.join(f'{v} {k}' for k, v in n.items()))
        out += items
    return out
