"""### red check.json: still-red, journal-window and superseded CHECKs in the window."""
import datetime, glob, json, os, re, subprocess, time

from .common import AG, AW, seconds, when

JOURNAL = re.compile(r'journalctl\b([^|]*?)--since\s+-(\d+[mhd])\b([^|]*)\|\s*grep\s+-c\s+("[^"]*"|\'[^\']*\'|\S+)')


def _last_fail(check):
    """(last matching journal line, window) of a `journalctl --since -N | grep -c PAT` CHECK, or None."""
    m = JOURNAL.search(check)
    if not m:
        return None
    pre, span, post, pat = m.groups()
    cmd = f'journalctl{pre}--since -{span}{post} -o short-iso | grep {pat} | tail -n 1'
    env = {**os.environ, 'PATH': os.path.join(AG, 'bin') + os.pathsep + os.environ.get('PATH', '')}
    try:
        out = subprocess.run(['bash', '-c', cmd], capture_output=True, text=True, timeout=10, env=env).stdout.split()
    except subprocess.TimeoutExpired:
        return None
    return (when(out[0]) if out else None), span


def _tag(d):
    """`superseded: x`, `window, heals HH:MM` (no failing event since the fix) or '' (still red)."""
    if d.get('superseded'):
        return f'superseded: {d["superseded"]}'
    fix = when(((d.get('runs') or [{}])[0]).get('started') or d.get('started'))
    lf = _last_fail(d.get('check', '')) if fix else None
    if not lf:
        return ''
    last, span = lf
    if last is None:
        return 'window, heals now'
    if last >= fix:
        return ''
    return f'window, heals {(last + datetime.timedelta(seconds=seconds(span))).strftime("%m-%d %H:%M")}'


def rows(ctx):
    """Red check.json in the window, newest verdict (agent-verify --recheck rewrites it); still-red first, then window, then superseded rows."""
    cutoff = time.time() - seconds(ctx.since)
    files = glob.glob(os.path.join(AW, 'evidence', '*', 'check.json'))
    red, window, sup, n = [], [], [], 0
    for f in sorted(files, key=os.path.getmtime, reverse=True):
        if os.path.getmtime(f) < cutoff:
            continue
        n += 1
        try:
            with open(f) as fh:
                d = json.load(fh)
        except (OSError, ValueError):
            red.append(f'unreadable {f}')
            continue
        if d.get('ok'):
            continue
        tag = _tag(d)
        row = f'{d.get("ticket", "?"):6} rc {d.get("rc", "?")}  {d.get("started", "")[:16]}  {d.get("check", "")[:90]}'
        verdict = d.get('verdict') or ((d.get('runs') or [{}])[-1]).get('verdict')
        full = row + (f'  [{tag}]' if tag else '') + (f'  [verdict {verdict}]' if verdict else '')
        (sup if tag.startswith('superseded') else window if tag else red).append(full)
    return [f'{len(red) + len(window) + len(sup)} red of {n} check.json in {ctx.since}: {len(red)} still-red, '
            f'{len(window)} window, {len(sup)} superseded'] + red + window + sup
