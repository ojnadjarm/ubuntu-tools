"""The broker's admin operations (list, put, remove, log): registry + sealer + audit, never a value out."""
import base64
import binascii
import json
import os

from . import registry
from .seal import SealError

MAX_VALUE = 64 * 1024


class Admin:
    """Answers one admin request; the socket and the peer check live in the daemon."""

    def __init__(self, registry_path, added_path, sealer, audit):
        self.registry_path, self.added_path = registry_path, added_path
        self.sealer, self.audit = sealer, audit
        self.added = self._read_added()
        self.entries = registry.load(registry_path, self.added)

    def _read_added(self):
        try:
            with open(self.added_path) as f:
                return json.load(f)
        except FileNotFoundError:
            return {}

    def _save_added(self, added):
        tmp = self.added_path + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump(added, f, indent=1, sort_keys=True)
        os.replace(tmp, self.added_path)
        self.added = added
        self.entries = registry.load(self.registry_path, added)

    def handle(self, req, uid):
        """Dispatch one request dict; returns the reply dict."""
        op = req.get("op")
        fn = {"list": self.op_list, "put": self.op_put, "remove": self.op_remove, "log": self.op_log}.get(op)
        if fn is None:
            return {"ok": False, "error": "unknown op"}
        return fn(req, uid)

    def _event(self, req, uid, event, name, result):
        self.audit.log({"event": event, "secret": name, "ticket": req.get("ticket"), "agent": req.get("agent"),
                        "result": result, "uid": uid})

    def op_list(self, req, uid):
        """Every registry row and sealed name with class, state, sealed-at and use counts."""
        sealed, use = self.sealer.sealed(), self.audit.summary()
        rows = []
        for n in sorted(set(self.entries) | set(sealed)):
            e, u = self.entries.get(n), use.get(n, {})
            rows.append({"name": n, "class": e.cls if e else "?", "modes": list(e.modes) if e else [],
                         "used_in": e.used_in if e else "", "legacy": e.legacy if e else "",
                         "reissue": e.reissue if e else "", "max_age_days": e.max_age_days if e else 0,
                         "added": bool(e and e.added), "sealed": n in sealed, "sealed_at": sealed.get(n),
                         "loaded": self.sealer.get(n) is not None, "last_used": u.get("last_used"),
                         "uses_7d": u.get("uses_7d", 0), "refusals_7d": u.get("refusals_7d", 0)})
        return {"ok": True, "secrets": rows}

    def op_put(self, req, uid):
        """Add (refused when already sealed) or replace (a known name) one value."""
        name, replace = req.get("name"), bool(req.get("replace"))
        event = "replace" if replace else "add"
        if not isinstance(name, str) or not registry.NAME.match(name):
            return {"ok": False, "error": "bad name: lowercase letters, digits, '-'"}
        meta = {k: req[k] for k in ("class", "used_in") if req.get(k) not in (None, "")}
        e = self.entries.get(name)
        if e is None and replace:
            return {"ok": False, "error": f"{name} is not in the vault; add it with a class"}
        if e is not None and meta:
            return {"ok": False, "error": f"{name} is known: its class and use stay as they are"}
        if e is None:
            try:
                registry.entry(name, meta, added=True)
            except registry.RegistryError as err:
                return {"ok": False, "error": str(err)}
        if not replace and name in self.sealer.sealed():
            self._event(req, uid, event, name, "refused")
            return {"ok": False, "error": f"{name} is already sealed; use replace"}
        try:
            value = base64.b64decode(req.get("value_b64") or "", validate=True)
        except (binascii.Error, ValueError):
            return {"ok": False, "error": "bad value encoding"}
        if not value or len(value) > MAX_VALUE:
            return {"ok": False, "error": f"value must be 1 to {MAX_VALUE} bytes"}
        try:
            self.sealer.put(name, value)
        except SealError as err:
            self._event(req, uid, event, name, "error")
            return {"ok": False, "error": str(err)}
        finally:
            del value
        if e is None:
            self._save_added({**self.added, name: meta})
        self._event(req, uid, event, name, "ok")
        return {"ok": True, "name": name, "event": event}

    def op_remove(self, req, uid):
        """Unseal nothing: drop a sealed value and, for a hand-added name, its row."""
        name = req.get("name")
        sealed = self.sealer.sealed()
        if name not in sealed and name not in self.added:
            return {"ok": False, "error": f"{name} is neither sealed nor added by hand"}
        if name in sealed:
            try:
                self.sealer.remove(name)
            except SealError as err:
                self._event(req, uid, "remove", name, "error")
                return {"ok": False, "error": str(err)}
        if name in self.added:
            self._save_added({k: v for k, v in self.added.items() if k != name})
        self._event(req, uid, "remove", name, "ok")
        return {"ok": True, "name": name, "event": "remove"}

    def op_log(self, req, uid):
        """The last n events (default 20), optionally for one name."""
        n = req.get("n", 20)
        if not isinstance(n, int):
            return {"ok": False, "error": "n must be a number"}
        return {"ok": True, "events": self.audit.tail(n, req.get("name"))}
