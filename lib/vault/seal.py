"""Keep secret values at rest: the Sealer interface, the systemd-creds store and an in-memory one for tests."""
import base64
import os
import time
from abc import ABC, abstractmethod

from . import wire

PREFIX = "fleet."


class SealError(RuntimeError):
    """The store refused or failed an operation (never carries a value)."""


class Sealer(ABC):
    """Where values rest; the broker depends on this, never on systemd."""

    @abstractmethod
    def put(self, name, value):
        """Seal value (bytes) under name, replacing any old one."""

    @abstractmethod
    def get(self, name):
        """The value of name as bytes, or None."""

    @abstractmethod
    def sealed(self):
        """{name: sealed-at epoch seconds} for every sealed name."""

    @abstractmethod
    def remove(self, name):
        """Drop name from the store."""


class MemorySealer(Sealer):
    """A dict store for tests."""

    def __init__(self, clock=time.time):
        self._v, self._t, self._clock = {}, {}, clock

    def put(self, name, value):
        self._v[name], self._t[name] = bytes(value), self._clock()

    def get(self, name):
        return self._v.get(name)

    def sealed(self):
        return dict(self._t)

    def remove(self, name):
        if name not in self._v:
            raise SealError("not sealed")
        del self._v[name], self._t[name]


class SystemdCreds(Sealer):
    """Values unsealed once at start (systemd's ImportCredential); puts and removes go through the root seal helper."""

    def __init__(self, cred_dir, seal_socket):
        self._sock, self._v = seal_socket, {}
        if cred_dir and os.path.isdir(cred_dir):
            for f in os.listdir(cred_dir):
                if f.startswith(PREFIX):
                    with open(os.path.join(cred_dir, f), "rb") as fh:
                        self._v[f[len(PREFIX):]] = fh.read()

    def _call(self, req):
        try:
            r = wire.call(self._sock, req)
        except (OSError, ValueError) as e:
            raise SealError(f"seal helper unreachable ({type(e).__name__})") from None
        if not r.get("ok"):
            raise SealError(str(r.get("error", "seal helper refused")))
        return r

    def put(self, name, value):
        self._call({"op": "put", "name": name, "value_b64": base64.b64encode(value).decode()})
        self._v[name] = bytes(value)

    def get(self, name):
        return self._v.get(name)

    def sealed(self):
        return {n: float(t) for n, t in self._call({"op": "list"})["sealed"].items()}

    def remove(self, name):
        self._call({"op": "remove", "name": name})
        self._v.pop(name, None)
