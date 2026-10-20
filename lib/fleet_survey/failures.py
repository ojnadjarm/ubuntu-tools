"""### failures: `pc failures --since`."""
from .common import run


def rows(ctx):
    return run('pc', 'failures', '--since', ctx.since)
