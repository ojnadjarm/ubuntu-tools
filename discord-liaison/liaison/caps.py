"""Per-UTC-day caps on LLM runs and PRs, every take or refusal logged."""
import time

from discordbot.store import RateLimiter

WHO = 'liaison'


class Caps:
    def __init__(self, path, log_path, limits, clock=time.time):
        self.rl, self.log_path, self.limits, self.clock = RateLimiter(path, clock), log_path, limits, clock

    def used(self, kind):
        return self.rl.data.get(f'{kind}:{WHO}', 0) if self.rl.data.get('day') == self.rl._day() else 0

    def take(self, kind):
        limit = self.limits[kind]
        ok = self.rl.take(kind, WHO, limit)
        with open(self.log_path, 'a') as f:
            stamp = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(self.clock()))
            f.write(f'{stamp} {kind} {"ok" if ok else "cap"} {self.used(kind)}/{limit}\n')
        return ok
