"""pytest beside discord-bot/tests: free the `tests` package name and put the liaison and the bot's venv on the path."""
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BOT = os.path.join(os.path.dirname(HERE), 'discord-bot')
sys.path[:0] = [HERE, BOT] + glob.glob(os.path.join(BOT, '.venv/lib/python3*/site-packages'))


def pytest_collectstart(collector):
    """Drop another package's cached `tests` modules before this folder's tests are imported."""
    if str(collector.path).startswith(os.path.join(HERE, 'tests')):
        for name in [m for m in sys.modules if (m == 'tests' or m.startswith('tests.'))
                     and not (getattr(sys.modules[m], '__file__', '') or '').startswith(HERE)]:
            del sys.modules[name]
