"""Shared reader for logrotated jsonl logs (live file plus moodle-keep's .N.gz rotations)."""
import gzip, json, os, re, time


def row_stamp(row):
    """Epoch of a row's local 'ts' stamp, or None when it has none."""
    try:
        return time.mktime(time.strptime(row['ts'][:19], '%Y-%m-%dT%H:%M:%S'))
    except (ValueError, KeyError, TypeError):
        return None


def _rows(p):
    """Parsed rows of one plain or gzipped jsonl file; bad lines skipped."""
    rows = []
    with (gzip.open(p, 'rt') if p.endswith('.gz') else open(p)) as f:
        for line in f:
            try:
                rows.append(json.loads(line))
            except ValueError:
                continue
    return rows


def rotated_rows(path, cut):
    """Rows oldest first: live file, then each .N.gz until one starts before cut (cut 0 = live only)."""
    chunks, p, n = [], path, 1
    while os.path.exists(p):
        rows = _rows(p)
        chunks.append(rows)
        start = next((t for t in map(row_stamp, rows) if t is not None), None)
        if not cut or (start is not None and start < cut):
            break
        p, n = f'{path}.{n}.gz', n + 1
    return [r for c in reversed(chunks) for r in c]


# (raw tool, subcommand) -> (class, pc verb); '*' is any other subcommand of that tool.
# covered: a pc verb does it; by-design: raw is correct (pc refuses it); gap: no verb yet.
RAW_MAP = {
    ('tailscale', 'status'): ('covered', 'pc net tailscale'),
    ('tailscale', 'serve'): ('by-design', None),
    ('tailscale', '*'): ('gap', None),
    ('systemctl', 'restart'): ('covered', 'pc units restart'),
    ('systemctl', 'stop'): ('covered', 'pc units stop'),
    ('docker', 'restart'): ('covered', 'pc docker restart'),
    ('pactl', '*'): ('covered', 'pc audio'),
    ('wpctl', '*'): ('covered', 'pc audio'),
    ('powerprofilesctl', '*'): ('covered', 'pc power profile'),
    ('nmcli', '*'): ('gap', None),
    ('brightnessctl', '*'): ('gap', None),
}
RAW_TOOLS = {t for t, _ in RAW_MAP}
SEGMENT = re.compile(r'&&|\|\||;|\|')


def raw_call(row):
    """(label, class, pc verb) when a Bash row's op starts with a raw tool, else None."""
    op = (row.get('op') or '').split() if row.get('tool') == 'Bash' else []
    if not op or op[0] not in RAW_TOOLS:
        return None
    words = op[1:]
    for seg in SEGMENT.split(row.get('summary') or ''):
        w = seg.split()
        if w and os.path.basename(w[0]) == op[0]:
            words = w[1:]
            break
    sub = next((w for w in words if not w.startswith('-')), '')
    if (op[0], sub) in RAW_MAP:
        return (f'{op[0]} {sub}',) + RAW_MAP[(op[0], sub)]
    if (op[0], '*') in RAW_MAP:
        return (op[0],) + RAW_MAP[(op[0], '*')]
    return None


def row_kind(row):
    """'bench' for pcbench trials, 'agent' for rostered agent runs, else 'interactive'."""
    agent = row.get('agent') or ''
    if agent == 'bench' or '/bench/runs/' in (row.get('cwd') or ''):
        return 'bench'
    return 'agent' if agent else 'interactive'
