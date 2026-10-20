"""### cli p50 (--measure): read-only CLIs x3, wall ms."""
import os, time

from .common import AG, p50, short

MEASURE_BUDGET = 80
CLIS = [('harness', 'context', '--worker'), ('guide', 'wait-for'), ('claims', 'list'), ('pc', 'status'),
        ('agents-log', '--errors', '--cluster', '--since', '24h'), ('pc', 'failures', '--since', '24h'),
        ('pc', 'explain', 'quiet-gate'), ('quiet-gate',), ('owner-todo', 'list')]


def rows(ctx):
    """CLIS x3 each, read-only verbs, wall ms; rows past MEASURE_BUDGET are skipped."""
    out = []
    for argv in CLIS:
        exe = os.path.join(AG, 'bin', argv[0])
        if ctx.t0 + MEASURE_BUDGET - time.time() < 3:
            out.append(f'skipped: budget {MEASURE_BUDGET} s  {" ".join(argv)}')
            continue
        if not os.access(exe, os.X_OK):
            out.append(f'n/a: not in {short(AG)}/bin  {" ".join(argv)}')
            continue
        mid, ms, rc = p50([exe, *argv[1:]], 3)
        out.append(f'{mid:6.0f} ms p50  {"/".join(map(str, ms))}  rc {rc}  {" ".join(argv)}')
    return [f'{len(CLIS)} CLIs x3, load1 {os.getloadavg()[0]:.1f}'] + out
