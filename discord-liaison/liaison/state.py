"""The liaison's JSON state: thread cursor, inbox of unanswered messages, thread -> project map, shown ids."""
import json
import os

from discordbot.store import save_json


def _load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


class State:
    def __init__(self, d):
        self.dir = d
        os.makedirs(d, exist_ok=True)
        self.cursor = _load(self._p('cursor.json'), {})
        self.inbox = _load(self._p('inbox.json'), [])
        self.threads = _load(self._p('threads.json'), {})
        self.shown = _load(self._p('shown.json'), [])

    def _p(self, name):
        return os.path.join(self.dir, name)

    def thread(self, tid):
        return self.threads.get(tid)

    def put_thread(self, tid, **fields):
        self.threads.setdefault(tid, {}).update(fields)
        save_json(self._p('threads.json'), self.threads)

    def save_cursor(self, cursor):
        self.cursor = cursor
        save_json(self._p('cursor.json'), cursor)

    def add(self, msgs):
        have = {m['id'] for m in self.inbox}
        self.inbox += [m for m in msgs if m['id'] not in have]
        save_json(self._p('inbox.json'), self.inbox)

    def mark_shown(self):
        self.shown = [m['id'] for m in self.inbox]
        save_json(self._p('shown.json'), self.shown)

    def drop_shown(self):
        seen = set(self.shown)
        self.inbox = [m for m in self.inbox if m['id'] not in seen]
        self.shown = []
        save_json(self._p('inbox.json'), self.inbox)
        save_json(self._p('shown.json'), self.shown)
