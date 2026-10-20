"""### creative gamedev: perf-cpp.csv GPU ms, cpp-ci stages and the newest non-scratch cpp-ci run."""
import csv, json, os, re

from .common import AG, age, epoch, short
from .creative import stack_rows

PASS_COL = re.compile(r'gpu_ms_p50_(\w+)|(post)_ms_p50')


def _gpu_ms():
    """Last row of state/gamedev-perf/perf-cpp.csv: gpu_ms_p50, per pass and status."""
    f = os.path.join(AG, 'state', 'gamedev-perf', 'perf-cpp.csv')
    if not os.path.isfile(f):
        return f'gpu_ms_p50 none: no {short(f)}'
    with open(f) as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        return f'gpu_ms_p50 none: no rows in {short(f)}'
    r = rows[-1]
    passes = ' '.join(f'{m.group(1) or m.group(2)}={v}' for k, v in r.items()
                      if k and v and (m := PASS_COL.fullmatch(k)))
    return (f'gpu_ms_p50 {r.get("gpu_ms_p50") or "?"} ({passes or "no passes"}) {r.get("status") or "?"}'
            f'  {short(f)}, {age(epoch(r.get("date"), f))}')


def _scratch(p):
    """True when p is under CI_SCRATCH_ROOTS (default $TMPDIR and /tmp) or a Claude scratchpad, as cpp-ci's ci_scratch."""
    p = os.path.realpath(p)
    roots = (os.environ.get('CI_SCRATCH_ROOTS') or f'{os.environ.get("TMPDIR") or "/tmp"} /tmp').split()
    return '/scratchpad/' in p or any(p.startswith(os.path.realpath(r) + '/') for r in roots)


def _cpp_ci(root):
    out = []
    try:
        with open(os.path.join(root, 'scripts', 'cpp-ci'), errors='replace') as fh:
            m = re.search(r'^stages="([^"]+)"', fh.read(), re.M)
        out.append(f'cpp-ci stages {m.group(1) if m else "?"}')
    except OSError:
        out.append('cpp-ci stages: no scripts/cpp-ci')
    led = os.path.join(AG, 'log', 'creative-ci.jsonl')
    try:
        with open(led, errors='replace') as fh:
            ledger = [json.loads(r) for r in fh if '"cpp-ci"' in r]
    except OSError:
        return out + [f'cpp-ci last none: no {short(led)}']
    for r in reversed(ledger):
        try:
            with open(r.get('summary') or '') as fh:
                d = json.load(fh)
        except (OSError, ValueError):
            continue
        if r.get('tool') != 'cpp-ci' or _scratch(d.get('project') or ''):
            continue
        st = d.get('stages') or {}
        return out + [f'cpp-ci last {r.get("project")} ' + ' '.join(f'{k}:{(v or {}).get("status", "?")}' for k, v in st.items())
                      + f'  {short(r["summary"])}, {age(epoch(r.get("ts"), led))}']
    return out + [f'cpp-ci last none non-scratch in {short(led)}']


def rows(ctx):
    return stack_rows('gamedev', lambda root: [_gpu_ms()] + _cpp_ci(root))
