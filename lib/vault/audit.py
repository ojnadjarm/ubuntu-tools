"""Append-only log of every vault event and the per-secret summary the list and the dashboard read."""
import json
import os
import time

WEEK = 7 * 86400
FIELDS = ("event", "secret", "ticket", "agent", "target", "result", "uid", "lease", "status", "cost", "asked", "why")


class Audit:
    """One JSON line per event in a 600 file; never a value."""

    def __init__(self, path, clock=time.time):
        self.path, self._clock = path, clock

    def log(self, event):
        """Append one event; only the known fields are kept."""
        row = {"ts": round(self._clock(), 3)}
        row.update({k: event[k] for k in FIELDS if event.get(k) not in (None, "")})
        fd = os.open(self.path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        with os.fdopen(fd, "a") as f:
            f.write(json.dumps(row, separators=(",", ":")) + "\n")

    def _rows(self):
        try:
            with open(self.path) as f:
                for line in f:
                    try:
                        yield json.loads(line)
                    except ValueError:
                        continue
        except FileNotFoundError:
            return

    def tail(self, n=20, name=None):
        """The last n events, oldest first, optionally for one secret."""
        rows = [r for r in self._rows() if name is None or r.get("secret") == name]
        return rows[-n:] if n > 0 else []

    def summary(self):
        """{secret: {last_used, uses_7d, refusals_7d}} built from `use` events and refusals."""
        out, since = {}, self._clock() - WEEK
        for r in self._rows():
            s = r.get("secret")
            if not s:
                continue
            row = out.setdefault(s, {"last_used": None, "uses_7d": 0, "refusals_7d": 0})
            recent = r.get("ts", 0) >= since
            if r.get("result") == "refused":
                row["refusals_7d"] += recent
            elif r.get("event") == "use" and r.get("result") == "ok":
                row["last_used"] = r.get("ts")
                row["uses_7d"] += recent
        return out

    def month_spend(self, name):
        """Dollars logged on name's `use` events in this calendar month (local time)."""
        start = time.mktime(time.localtime(self._clock())[:2] + (1, 0, 0, 0, 0, 0, -1))
        return sum(float(r.get("cost") or 0) for r in self._rows()
                   if r.get("secret") == name and r.get("event") == "use" and r.get("ts", 0) >= start)
