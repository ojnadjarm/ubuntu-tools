"""### tokens by ticket: `agents-log --tokens --by ticket`, top 25 rows."""
from .common import run


def rows(ctx):
    return run('agents-log', '--tokens', '--by', 'ticket', '--since', ctx.since)[:25]
