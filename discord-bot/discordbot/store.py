"""Small JSON state files: known threads, per-member daily counters, status."""
import json
import os
import time


def _load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save_json(path, data):
    tmp = f'{path}.tmp'
    with open(tmp, 'w') as f:
        json.dump(data, f, indent=1, sort_keys=True)
    os.replace(tmp, path)


class Store:
    def __init__(self, state_dir):
        self.dir = state_dir
        os.makedirs(state_dir, exist_ok=True)
        self.threads = _load(self._p('threads.json'), {})
        self.status = _load(self._p('status.json'), {})

    def _p(self, name):
        return os.path.join(self.dir, name)

    def thread(self, tid):
        return self.threads.get(tid)

    def put_thread(self, tid, **fields):
        self.threads.setdefault(tid, {}).update(fields)
        save_json(self._p('threads.json'), self.threads)

    def set_status(self, **fields):
        self.status.update(fields)
        save_json(self._p('status.json'), self.status)


class RateLimiter:
    """Per-member counters per UTC day, persisted to a JSON file."""

    def __init__(self, path, clock=time.time):
        self.path, self.clock = path, clock
        self.data = _load(path, {})

    def _day(self):
        return time.strftime('%Y-%m-%d', time.gmtime(self.clock()))

    def take(self, kind, member, limit):
        """Count one `kind` use for `member`; False when today's limit is already reached."""
        day = self._day()
        if self.data.get('day') != day:
            self.data = {'day': day}
        key = f'{kind}:{member}'
        n = self.data.get(key, 0)
        if n >= limit:
            return False
        self.data[key] = n + 1
        save_json(self.path, self.data)
        return True
