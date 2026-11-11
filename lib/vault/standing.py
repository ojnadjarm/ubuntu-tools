"""Standing grants: a class-free secret in op mode is used with no lease (notify for every caller), each use logged."""
import json

from .mode import Response
from .op import OpError

QUIET = ("/picks",)


class Standing:
    """Depends on the entries, a Sealer, the Audit and the op modes by secret name."""

    def __init__(self, entries, sealer, audit, ops):
        self.entries, self.sealer, self.audit, self.ops = entries, sealer, audit, ops

    def _log(self, name, who, result, why="", resp=None):
        self.audit.log({"event": "use", "secret": name, "agent": who, "result": result, "why": why,
                        "target": resp.target if resp else None, "status": resp.status if resp else None})

    def use(self, name, request, who):
        """Answer one lease-free op call; an empty `/picks` poll is not logged (po-picks polls every few seconds)."""
        e, op = self.entries().get(name), self.ops.get(name)
        if e is None or op is None or "op" not in e.modes:
            return Response(404, body=b'{"error":"no standing op for this secret"}')
        if e.cls != "free":
            self._log(name, who, "refused", f"class {e.cls}: a standing op needs class free")
            return Response(403, body=b'{"error":"refused: only a free secret has a standing op"}')
        value = self.sealer.get(name)
        if value is None:
            self._log(name, who, "error", "not sealed")
            return Response(503, body=b'{"error":"the vault holds no value for this secret"}')
        try:
            resp = op.handle(request, e, value, None)
        except OpError as err:
            self._log(name, who, "refused", str(err)[:120])
            return Response(400, body=json.dumps({"error": str(err)}).encode())
        except OSError as err:
            self._log(name, who, "error", f"upstream {type(err).__name__}")
            return Response(502, body=b'{"error":"upstream unreachable"}')
        finally:
            del value
        if not (request.path in QUIET and resp.status == 200 and not resp.body):
            self._log(name, who, "ok" if resp.status == 200 else "error", resp=resp)
        return resp
