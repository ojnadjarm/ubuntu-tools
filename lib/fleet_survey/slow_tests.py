"""### slow tests: top 5 by p50 wall, outliers and a top CPU block."""
import os, re, statistics

from .common import AG, NA, TIMINGS

MIN_RUNS = 3


def _last_run_only():
    f = os.path.join(AG, 'state', 'test-timings.tsv')
    if not os.path.isfile(f):
        raise NA(f'no {f}')
    with open(f) as fh:
        out = [r.rstrip('\n').split('\t') for r in fh if r.strip()]
    out = [r for r in out if len(r) >= 2 and re.fullmatch(r'[\d.]+', r[1])]
    out.sort(key=lambda r: float(r[1]), reverse=True)
    return [f'{float(r[1]):7.1f} s  last run  {r[0]}' for r in out[:5]]


def rows(ctx):
    """Top 5 by p50 wall of each file's last 5 runs (state/test-timings-history.tsv), rows under MIN_RUNS tagged `noisy
    (n=, max load)` below the measured ones, `outlier` rows (> 5x p50 and > 30 s),
    then a `top CPU` block: top 5 by p50 cpu_s (column 6) of the last 5 runs that have one."""
    if not os.path.isfile(TIMINGS):
        return _last_run_only()
    runs, cpus = {}, {}
    with open(TIMINGS) as fh:
        for r in fh:
            r = r.rstrip('\n').split('\t')
            if len(r) >= 5 and re.fullmatch(r'[\d.]+', r[2]):
                runs.setdefault(r[1], []).append((float(r[2]), r[0][:16], r[4]))
                if len(r) >= 6 and re.fullmatch(r'[\d.]+', r[5]):
                    cpus.setdefault(r[1], []).append(float(r[5]))
    last = {k: v[-5:] for k, v in runs.items()}
    p50 = {k: statistics.median(s for s, _, _ in v) for k, v in last.items()}
    measured = lambda k: len(last[k]) >= MIN_RUNS
    order = sorted(p50, key=lambda k: (measured(k), p50[k]), reverse=True)[:5]
    out = [f'{p50[k]:7.1f} s  p50 of {len(last[k])}  {k}' + ('' if measured(k) else
           f'  noisy (n={len(last[k])}, load {max(float(l) for _, _, l in last[k]):.0f})') for k in order]
    for k, v in sorted(last.items()):
        out += [f'outlier {s:7.1f} s  {s / p50[k]:.1f}x p50 {p50[k]:.1f} s  {when} load {load}  {k}'
                for s, when, load in v if s > 5 * p50[k] and s > 30]
    cpu = {k: statistics.median(v[-5:]) for k, v in cpus.items()}
    if cpu:
        out += ['top CPU'] + [f'{cpu[k]:7.1f} cpu s  p50 of {len(cpus[k][-5:])}  {k}'
                              for k in sorted(cpu, key=cpu.get, reverse=True)[:5]]
    return out
