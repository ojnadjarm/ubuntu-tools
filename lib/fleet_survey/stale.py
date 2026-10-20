"""### stale guides: `guide --stale 14`, count + top 20."""
from .common import run

STALE_DAYS = 14


def rows(ctx):
    out = [r for r in run('guide', '--stale', str(STALE_DAYS)) if r.strip()]
    return [f'{len(out)} guides verified >= {STALE_DAYS} d ago or never'] + out[:20]
