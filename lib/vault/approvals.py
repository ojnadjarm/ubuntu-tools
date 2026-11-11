"""Critical leases wait for one approval: the owner's tap on a push only his phone gets, or the orchestrator's
`secret approve` from outside an agent; a refused self-grant is pushed to the owner by the broker itself."""
import dataclasses
import hmac
import re
import secrets
import threading
import time
from dataclasses import dataclass

from .grants import TICKET, Grants, refusal
from .op import APPROVE

TAP = re.compile(r"^vault:([0-9a-f]{6}):([A-Za-z0-9_-]{16,64}):(yes|no)$")
WAIT = 3600
EVERY = 5


@dataclass
class Pending:
    """One request waiting for a yes or a no; `nonce` travels only in the push to the owner's phone."""
    ref: str
    nonce: str
    name: str
    ticket: str
    agent: str
    created: float
    state: str = "pending"
    by: str = ""


class Approvals:
    """Pending requests by (secret, ticket); settled by taps read from the approval topic, at most every few seconds."""

    def __init__(self, push, audit, clock=time.time, wait=WAIT, every=EVERY):
        self.push, self.audit, self._clock, self.wait, self.every = push, audit, clock, wait, every
        self._p, self._lock, self._polled = {}, threading.Lock(), 0.0

    def _log(self, p, event, result, by):
        self.audit.log({"event": event, "secret": p.name, "ticket": p.ticket, "agent": p.agent, "result": result,
                        "target": by})

    def _drop_old(self):
        now = self._clock()
        self._p = {k: p for k, p in self._p.items() if p.created + self.wait > now}

    def find(self, name, ticket):
        """The live request for (name, ticket), or None."""
        with self._lock:
            self._drop_old()
            return self._p.get((name, ticket))

    def ask(self, name, ticket, agent, asked=""):
        """A pending request (reused when one is live) and whether its push reached ntfy."""
        with self._lock:
            self._drop_old()
            p = self._p.get((name, ticket))
            if p is not None:
                return p, None
            p = Pending(secrets.token_hex(3), secrets.token_urlsafe(18), name, ticket, agent, self._clock())
            self._p[(name, ticket)] = p
        words = f" asked: {' '.join(str(asked).split())}" if asked else ""
        sent = self.push.send(f"Approve {name} for {ticket} ({agent or 'a launcher'})? ref {p.ref}.{words}",
                              "vault approval", "high",
                              (("Approve", f"vault:{p.ref}:{p.nonce}:yes"), ("Deny", f"vault:{p.ref}:{p.nonce}:no")),
                              APPROVE)
        self._log(p, "approval", "asked" if sent else "push failed", "owner push")
        return p, sent

    def decide(self, ref, yes, by):
        """Settle a pending request by its ref; the request, or None when no pending one has that ref."""
        with self._lock:
            self._drop_old()
            p = next((x for x in self._p.values() if x.ref == ref and x.state == "pending"), None)
            if p is None:
                return None
            p.state, p.by = ("approved" if yes else "denied"), by
        self._log(p, "approve" if yes else "deny", "ok", by)
        return p

    def settle(self):
        """Read the owner's taps since the oldest pending request (throttled) and apply the ones whose nonce matches."""
        with self._lock:
            self._drop_old()
            waiting = [p for p in self._p.values() if p.state == "pending"]
            now = self._clock()
            if not waiting or now - self._polled < self.every:
                return
            self._polled = now
            since = str(int(min(p.created for p in waiting)) - 5)
        for m in self.push.taps(since, APPROVE):
            t = TAP.match(str(m.get("message", "")))
            if not t:
                continue
            with self._lock:
                p = next((x for x in self._p.values() if x.ref == t[1] and x.state == "pending"), None)
                ok = p is not None and hmac.compare_digest(p.nonce, t[2])
            if ok:
                self.decide(t[1], t[3] == "yes", "owner tap")

    def take(self, name, ticket):
        """Consume an approved request: one approval, one lease."""
        with self._lock:
            p = self._p.get((name, ticket))
            if p and p.state == "approved":
                del self._p[(name, ticket)]
                return p
            return None

    def pending(self):
        """Live requests, without their nonces."""
        with self._lock:
            self._drop_old()
            return [{"ref": p.ref, "name": p.name, "ticket": p.ticket, "agent": p.agent, "created": p.created,
                     "state": p.state, "by": p.by} for p in self._p.values()]


class Approving(Grants):
    """The grant policy plus approvals for class critical and a broker push for a self-grant refused inside an agent."""

    def __init__(self, leases, audit, callers, approvals, push):
        super().__init__(leases, audit, callers)
        self.approvals, self.push = approvals, push

    def _inside(self, uid, pid):
        return self.callers.agent_unit(pid, uid) if self.callers else None

    def _raised(self, reply, req):
        """Push a refused self-grant from the broker; the client then has nothing left to raise."""
        if not reply.get("raise"):
            return reply
        who = str(req.get("agent") or "an agent")[:40]
        msg = (f"vault: {who} asked {str(req.get('op', 'grant'))[:10]} on {str(req.get('name') or req.get('ref'))[:40]} "
               f"({str(req.get('ticket') or '-')[:40]}) from inside an agent; refused.")
        if self.push.send(msg, "vault", "high"):
            return {**reply, "raise": False, "raised": True}
        return reply

    def grant(self, entry, req, uid, pid=None):
        name, ticket = req.get("name"), req.get("ticket")
        if entry is None or entry.cls != "critical" or self._inside(uid, pid):
            return self._raised(super().grant(entry, req, uid, pid), req)
        if not isinstance(ticket, str) or not TICKET.match(ticket):
            return {"ok": False, "error": "a lease needs --ticket (letters, digits, '.', '_', '-')"}
        why = refusal(dataclasses.replace(entry, cls="free"), req)
        if why:
            self._log(req, uid, name, "refused", why)
            return {"ok": False, "error": f"{name}: {why}"}
        self.approvals.settle()
        p = self.approvals.find(name, ticket)
        if p and p.state == "denied":
            self.approvals.take(name, ticket)
            self._log(req, uid, name, "refused", f"denied by {p.by}")
            return {"ok": False, "error": f"{name}: denied by {p.by} (ref {p.ref})"}
        if p and p.state == "approved":
            self.approvals.take(name, ticket)
            self._log(req, uid, name, "approved", f"approved by {p.by}")
            return super().grant(dataclasses.replace(entry, cls="free"), req, uid, pid)
        p, sent = self.approvals.ask(name, ticket, str(req.get("agent") or ""), req.get("asked") or "")
        how = "the owner's tap on the push" if sent is not False else "the push failed"
        if sent is not None:
            self._log(req, uid, name, "pending", f"ref {p.ref}")
        return {"ok": False, "pending": p.ref,
                "error": f"{name}: class critical: waiting for approval, ref {p.ref} ({how}, or "
                         f"`secret approve {p.ref}` by the orchestrator)"}

    def decide(self, req, uid, pid, yes):
        """The orchestrator's (or the owner's terminal) yes or no; refused and pushed when asked from inside an agent."""
        ref = str(req.get("ref") or "")
        unit = self._inside(uid, pid)
        if unit:
            self.audit.log({"event": "approve" if yes else "deny", "agent": req.get("agent"), "result": "refused",
                            "uid": uid, "target": unit, "why": "asked from inside an agent"})
            return self._raised({"ok": False, "raise": True,
                                 "error": f"refused: an approval never comes from inside an agent ({unit})"}, req)
        p = self.approvals.decide(ref, yes, f"uid {uid} outside an agent")
        if p is None:
            return {"ok": False, "error": f"no pending request with ref {ref!r}"}
        return {"ok": True, "ref": p.ref, "name": p.name, "ticket": p.ticket, "state": p.state}
