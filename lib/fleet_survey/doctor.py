"""### doctor: `pc doctor --quick --brief` (rc 1 still read)."""
from .common import run


def rows(ctx):
    return run('pc', 'doctor', '--quick', '--brief', ok=(0, 1))
