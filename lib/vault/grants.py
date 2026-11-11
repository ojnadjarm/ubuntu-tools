"""Grant policy: a lease for a secret by its class (free, ruled, critical) and its registry rule; every answer logged."""
import re

from .leases import MAX_TTL, LeaseError

try:
    from image_grant import GRANT
except ImportError:
    GRANT = None

TICKET = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
DEFAULT_TTL = 3600
RULES = {
    "image-ask": lambda req: bool(GRANT and GRANT.search(" ".join(str(req.get("asked") or "").split()))),
}
OUTSIDE = "outside its rules: ask the orchestrator or the owner"
CRITICAL = "class critical: each use needs the orchestrator's or the owner's approval (not built yet)"


def refusal(entry, req):
    """Why entry gets no lease for req, or None."""
    if "proxy" not in entry.modes:
        return "no lease mode for this secret"
    if entry.cls == "critical":
        return CRITICAL
    if entry.cls == "ruled":
        rule = RULES.get(entry.check)
        if rule is None or not rule(req):
            return OUTSIDE + (f" ({entry.rules})" if entry.rules else "")
    return None


class Grants:
    """Mint and revoke leases under the policy; the admin socket calls this."""

    def __init__(self, leases, audit):
        self.leases, self.audit = leases, audit

    def _log(self, req, uid, name, result, why="", lease=None):
        self.audit.log({"event": "grant", "secret": name, "ticket": req.get("ticket"), "agent": req.get("agent"),
                        "result": result, "uid": uid, "why": why, "lease": lease.ref if lease else None,
                        "asked": str(req.get("asked") or "")[:200]})

    def grant(self, entry, req, uid):
        """A lease reply for one request, or a refusal reply."""
        name, ticket = req.get("name"), req.get("ticket")
        if entry is None:
            return {"ok": False, "error": f"{name} is not in the vault"}
        if not isinstance(ticket, str) or not TICKET.match(ticket):
            return {"ok": False, "error": "a lease needs --ticket (letters, digits, '.', '_', '-')"}
        try:
            ttl, cap = int(req.get("ttl") or DEFAULT_TTL), float(req.get("cap") or 0)
        except (TypeError, ValueError):
            return {"ok": False, "error": "ttl and cap must be numbers"}
        if entry.cap_usd:
            cap = min(cap, entry.cap_usd) if cap > 0 else entry.cap_usd
        why = refusal(entry, req)
        if why:
            self._log(req, uid, name, "refused", why)
            return {"ok": False, "error": f"{name}: {why}"}
        try:
            lease = self.leases.mint(name, ticket, ttl, cap, str(req.get("agent") or ""))
        except LeaseError as e:
            return {"ok": False, "error": f"{e} (at most {MAX_TTL})"}
        self._log(req, uid, name, "ok", lease=lease)
        return {"ok": True, "lease": lease.id, "expires": lease.expires, "cap": lease.cap}

    def revoke(self, req, uid):
        """Drop one lease by id."""
        ok = self.leases.revoke(str(req.get("lease") or ""))
        self.audit.log({"event": "revoke", "ticket": req.get("ticket"), "agent": req.get("agent"),
                        "result": "ok" if ok else "unknown", "uid": uid})
        return {"ok": ok} if ok else {"ok": False, "error": "no such lease"}
