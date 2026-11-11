"""The gate: one leased call checked (lease, mode, path, month cap), handed to its mode, charged and logged."""
import json

from .leases import LeaseError
from .mode import Response
from .proxy import PathError


def _refuse(status, why):
    return Response(status, {"Content-Type": "application/json"}, json.dumps({"error": why}).encode())


class Gate:
    """Depends on the entries, a Sealer, the Leases, the Audit and the modes by name; nothing else."""

    def __init__(self, entries, sealer, leases, audit, modes):
        self.entries, self.sealer, self.leases, self.audit, self.modes = entries, sealer, leases, audit, modes

    def _log(self, name, lease, result, why="", resp=None):
        self.audit.log({"event": "use", "secret": name, "ticket": lease.ticket if lease else None,
                        "agent": lease.agent if lease else None, "lease": lease.ref if lease else None,
                        "result": result, "why": why, "target": resp.target if resp else None,
                        "status": resp.status if resp else None, "cost": round(resp.cost, 6) if resp else None})

    def forward(self, lease_id, name, request):
        """Answer one call to /<lease>/<name>/<path>."""
        entry = self.entries().get(name)
        if entry is None:
            return _refuse(404, "unknown secret")
        try:
            lease = self.leases.check(lease_id, name)
        except LeaseError as e:
            self._log(name, None, "refused", str(e))
            return _refuse(403, f"refused: {e}")
        mode = next((self.modes[m] for m in entry.modes if m in self.modes), None)
        if mode is None:
            self._log(name, lease, "refused", "no call mode")
            return _refuse(403, "refused: this secret has no call mode")
        if entry.month_cap_usd and self.audit.month_spend(name) >= entry.month_cap_usd:
            self._log(name, lease, "refused", "month cap")
            return _refuse(403, f"refused: month cap of {entry.month_cap_usd:.2f} USD reached")
        value = self.sealer.get(name)
        if value is None:
            self._log(name, lease, "error", "not sealed")
            return _refuse(503, "the vault holds no value for this secret")
        try:
            resp = mode.handle(request, entry, value, lease)
        except PathError:
            self._log(name, lease, "refused", "path not allowed")
            return _refuse(403, "refused: path not allowed for this secret")
        except OSError as e:
            self._log(name, lease, "error", f"upstream {type(e).__name__}")
            return _refuse(502, f"upstream unreachable ({type(e).__name__})")
        finally:
            del value
        self.leases.charge(lease_id, resp.cost)
        self._log(name, lease, "ok", resp=resp)
        return resp
