"""The broker's own pushes to the owner and its reads of his taps, through the sealed ntfy topic; never a value out."""
from .op import APPROVE, OpError

NAME = "ntfy"


class Push:
    """Depends on the entries, a Sealer and an Ntfy op; a missing or unsealed `ntfy` makes every call a no-op."""

    def __init__(self, entries, sealer, ntfy, name=NAME):
        self.entries, self.sealer, self.ntfy, self.name = entries, sealer, ntfy, name

    def _parts(self):
        e = self.entries().get(self.name)
        v = self.sealer.get(self.name) if e else None
        return (e, v) if e and v else (None, None)

    def send(self, message, title="vault", prio="high", buttons=(), suffix=APPROVE):
        """True when ntfy took the push."""
        e, v = self._parts()
        if e is None:
            return False
        try:
            return self.ntfy.publish(e, v, message[:200], title, prio, "lock", buttons, suffix) == 200
        except (OpError, OSError):
            return False

    def taps(self, since, suffix=APPROVE):
        """Messages on the approval topic after since; [] when ntfy is out of reach."""
        e, v = self._parts()
        if e is None:
            return []
        try:
            return self.ntfy.poll(e, v, since, suffix)
        except (OpError, OSError):
            return []
