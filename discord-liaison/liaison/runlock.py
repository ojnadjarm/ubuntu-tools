"""One tick at a time: a second tick while a run is in flight must not take a cap or delete the run's files."""
import contextlib
import fcntl
import os


@contextlib.contextmanager
def run_lock(path):
    """Yield True when this process holds the lock, False when another tick does."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'a') as f:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            yield False
            return
        try:
            yield True
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)
