"""### perf cv: avg_fps spread of state/gamedev-perf/perf.csv."""
import csv, os, statistics

from .common import AG, NA


def rows(ctx):
    f = os.path.join(AG, 'state', 'gamedev-perf', 'perf.csv')
    if not os.path.isfile(f):
        raise NA(f'no {f}')
    with open(f) as fh:
        vals = [float(r['avg_fps']) for r in csv.DictReader(fh) if (r.get('avg_fps') or '').strip()]
    if len(vals) < 2:
        raise NA(f'{len(vals)} avg_fps rows')
    mean, sd = statistics.mean(vals), statistics.stdev(vals)
    return [f'n={len(vals)} mean={mean:.1f} sd={sd:.1f} cv={100 * sd / mean:.1f}% min={min(vals)} max={max(vals)}']
