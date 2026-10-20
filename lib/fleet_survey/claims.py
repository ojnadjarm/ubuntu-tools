"""### claims: `claims list`."""
from .common import run


def rows(ctx):
    return run('claims', 'list')
