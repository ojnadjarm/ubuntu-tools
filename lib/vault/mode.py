"""The delivery-mode contract: every mode answers one request for one secret the same way."""
from abc import ABC, abstractmethod
from dataclasses import dataclass, field


@dataclass
class Request:
    """A call an agent sent to the broker, without the lease and service prefix."""
    method: str
    path: str
    query: str = ""
    headers: dict = field(default_factory=dict)
    body: bytes = b""


@dataclass
class Response:
    """What goes back to the agent; `cost` is the call's dollar cost when the mode can read it."""
    status: int
    headers: dict = field(default_factory=dict)
    body: bytes = b""
    target: str = ""
    cost: float = 0.0


class Mode(ABC):
    """One way to use a secret for an agent without handing it the value."""

    @abstractmethod
    def handle(self, request, entry, value, lease):
        """Answer request for entry with value; returns a Response, never the value."""
