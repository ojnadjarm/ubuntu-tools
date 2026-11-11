"""Per-UTC-day caps on LLM runs and PRs, every take or refusal logged."""
import fcntl
import time

from discordbot.store import RateLimiter, save_json

WHO = 'liaison'


class Caps:
    def __init__(self, path, log_path, limits, clock=time.time):
        self.rl, self.log_path, self.limits, self.clock = RateLimiter(path, clock), log_path, limits, clock

    def used(self, kind):
        return self.rl.data.get(f'{kind}:{WHO}', 0) if self.rl.data.get('day') == self.rl._day() else 0

    def take(self, kind):
        limit = self.limits[kind]
        with open(self.rl.path + '.lock', 'a') as lk:
            fcntl.flock(lk, fcntl.LOCK_EX)
            self.rl.data = RateLimiter(self.rl.path, self.clock).data
            ok = self.rl.take(kind, WHO, limit)
        self.log(kind, 'ok' if ok else 'cap')
        return ok

    def give(self, kind):
        """Hand back one use of `kind` taken today: it was refused before it cost anything."""
        with open(self.rl.path + '.lock', 'a') as lk:
            fcntl.flock(lk, fcntl.LOCK_EX)
            self.rl.data = RateLimiter(self.rl.path, self.clock).data
            if self.used(kind):
                self.rl.data[f'{kind}:{WHO}'] -= 1
                save_json(self.rl.path, self.rl.data)
        self.log(kind, 'back')

    def log(self, kind, what):
        """Append one take, refusal or give-back line to the caps log."""
        with open(self.log_path, 'a') as f:
            stamp = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(self.clock()))
            f.write(f'{stamp} {kind} {what} {self.used(kind)}/{self.limits[kind]}\n')
