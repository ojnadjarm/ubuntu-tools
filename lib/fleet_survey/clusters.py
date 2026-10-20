"""### clusters: `agents-log --errors --cluster`, header + top 20 + TOTAL/hidden."""
from .common import run


def rows(ctx):
    out = run('agents-log', '--errors', '--cluster', '--since', ctx.since)
    tail = [r for r in out if r.startswith(('TOTAL', 'hidden'))]
    return out[:21] + tail
