"""Leases: random ids bound to one secret, one ticket, a time limit and an optional dollar cap; kept across broker restarts."""
import json
import os
import secrets
import threading
import time
from dataclasses import asdict, dataclass

MAX_TTL = 86400


class LeaseError(Exception):
    """A lease that does not let this call through; the message is the reason (never the id)."""


@dataclass
class Lease:
    """One grant; `cap` 0 means no dollar cap."""
    id: str
    secret: str
    ticket: str
    agent: str
    expires: float
    cap: float = 0.0
    spent: float = 0.0

    @property
    def ref(self):
        """A short reference for logs; the full id is never logged."""
        return self.id[:6]


class Leases:
    """Mint, check, charge and revoke leases; thread-safe; with a path, saved (mode 600) on every change."""

    def __init__(self, clock=time.time, path=None):
        self._l, self._clock, self._lock, self._path = {}, clock, threading.Lock(), path
        if path:
            try:
                with open(path) as f:
                    now = clock()
                    self._l = {r["id"]: Lease(**r) for r in json.load(f) if r.get("expires", 0) > now}
            except (OSError, ValueError, TypeError, KeyError, AttributeError):
                self._l = {}

    def _save(self):
        if not self._path:
            return
        tmp = self._path + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump([asdict(x) for x in self._l.values()], f)
        os.replace(tmp, self._path)

    def mint(self, secret, ticket, ttl, cap=0.0, agent=""):
        """A new lease for ttl seconds (1 to MAX_TTL)."""
        if not 0 < ttl <= MAX_TTL:
            raise LeaseError(f"ttl must be 1 to {MAX_TTL} seconds")
        with self._lock:
            now = self._clock()
            self._l = {k: v for k, v in self._l.items() if v.expires > now}
            lease = Lease(secrets.token_urlsafe(24), secret, ticket, agent, now + ttl, float(cap))
            self._l[lease.id] = lease
            self._save()
            return lease

    def check(self, lid, secret):
        """The lease if it may call secret now; LeaseError otherwise."""
        with self._lock:
            lease = self._l.get(lid)
            if lease is None:
                raise LeaseError("no such lease")
            if lease.expires <= self._clock():
                del self._l[lid]
                raise LeaseError("lease expired")
            if lease.secret != secret:
                raise LeaseError("lease is for another secret")
            if lease.cap and lease.spent >= lease.cap:
                raise LeaseError(f"lease cap reached ({lease.spent:.4f} of {lease.cap:.2f} USD)")
            return lease

    def charge(self, lid, usd):
        """Add a call's cost to the lease."""
        with self._lock:
            if lid in self._l:
                self._l[lid].spent += usd
                self._save()

    def revoke(self, lid):
        """Drop a lease; True when it existed."""
        with self._lock:
            gone = self._l.pop(lid, None) is not None
            if gone:
                self._save()
            return gone
