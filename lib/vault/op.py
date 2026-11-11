"""op mode for ntfy: the broker publishes the owner's pushes and reads his button taps; the topic never leaves it."""
import http.client
import json
import re
import ssl
import urllib.parse

from .mode import Mode, Response

PRIOS = {"min": 1, "low": 2, "default": 3, "high": 4, "urgent": 5}
REPLY, APPROVE = "-picks", "-vault"
TOPIC = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
SINCE = re.compile(r"^[A-Za-z0-9]{1,24}$")
TAGS = re.compile(r"^[A-Za-z0-9_+-]{1,40}(,[A-Za-z0-9_+-]{1,40}){0,4}$")
PART = re.compile(r"^[^,;\"'\n]{1,64}$")
MAX_MSG = 4096


class OpError(ValueError):
    """A request the op refuses; the message says why and never holds the topic."""


def _topic(value):
    t = value.decode(errors="replace").strip()
    if not TOPIC.match(t):
        raise OpError("the sealed ntfy value is not a topic name")
    return t


class Ntfy(Mode):
    """Ops `/notify` (one push, up to 3 buttons that post to the reply topic) and `/picks` (the reply topic's taps)."""

    def __init__(self, upstream="", timeout=15):
        self.upstream, self.timeout = upstream, timeout

    def _base(self, entry):
        if not entry.hosts:
            raise OpError("no pinned host for this secret")
        return self.upstream.rstrip("/") if self.upstream else f"https://{entry.hosts[0]}"

    def _call(self, entry, method, path, body=None):
        u = urllib.parse.urlsplit(self._base(entry))
        if u.scheme == "https":
            conn = http.client.HTTPSConnection(u.hostname, u.port or 443, context=ssl.create_default_context(),
                                               timeout=self.timeout)
        else:
            conn = http.client.HTTPConnection(u.hostname, u.port, timeout=self.timeout)
        try:
            conn.request(method, path, body=body, headers={"Content-Type": "application/json"} if body else {})
            r = conn.getresponse()
            return r.status, r.read()
        finally:
            conn.close()

    def publish(self, entry, value, message, title="", prio="default", tags="", buttons=(), suffix=REPLY):
        """Push message to the owner's topic; each button (label, body) posts body to topic+suffix. Returns the status."""
        topic = _topic(value)
        if not isinstance(message, str) or not message or len(message.encode()) > MAX_MSG:
            raise OpError(f"message must be 1 to {MAX_MSG} bytes")
        if prio not in PRIOS:
            raise OpError(f"priority must be one of {', '.join(PRIOS)}")
        if tags and not (isinstance(tags, str) and TAGS.match(tags)):
            raise OpError("tags: up to 5 comma-separated words")
        if not isinstance(title, str) or len(title) > 200:
            raise OpError("title: at most 200 characters")
        if len(buttons) > 3 or any(len(b) != 2 or not all(isinstance(x, str) and PART.match(x) for x in b)
                                   for b in buttons):
            raise OpError("buttons: at most 3 label=body pairs, no commas, semicolons or quotes")
        msg = {"topic": topic, "message": message, "priority": PRIOS[prio]}
        if title:
            msg["title"] = title
        if tags:
            msg["tags"] = tags.split(",")
        if buttons:
            url = f"{self._base(entry)}/{topic}{suffix}"
            msg["actions"] = [{"action": "http", "label": lb, "url": url, "method": "POST", "body": bd, "clear": True}
                              for lb, bd in buttons]
        status, _ = self._call(entry, "POST", "/", json.dumps(msg).encode())
        return status

    def poll(self, entry, value, since, suffix=REPLY):
        """The messages on topic+suffix after since (an id, a unix time or a duration), without the topic."""
        if not isinstance(since, str) or not SINCE.match(since):
            raise OpError("since: a message id, a unix time or a duration like 10m")
        status, body = self._call(entry, "GET", f"/{_topic(value)}{suffix}/json?poll=1&since={since}")
        if status != 200:
            raise OSError(f"ntfy answered {status}")
        out = []
        for line in body.decode(errors="replace").splitlines():
            try:
                m = json.loads(line)
            except ValueError:
                continue
            if isinstance(m, dict) and m.get("event") == "message":
                out.append({k: m[k] for k in ("id", "time", "event", "message") if k in m})
        return out

    def handle(self, request, entry, value, lease):
        try:
            args = json.loads(request.body or b"{}")
        except ValueError:
            raise OpError("body must be JSON")
        if not isinstance(args, dict):
            raise OpError("body must be a JSON object")
        if request.path == "/notify":
            status = self.publish(entry, value, args.get("message"), args.get("title") or "",
                                  args.get("priority") or "default", args.get("tags") or "",
                                  [tuple(b) for b in args.get("buttons") or [] if isinstance(b, (list, tuple))])
            return Response(status, {"Content-Type": "application/json"}, json.dumps({"sent": status == 200}).encode(),
                            f"notify {entry.hosts[0]}")
        if request.path == "/picks":
            msgs = self.poll(entry, value, args.get("since") or "10m")
            return Response(200, {"Content-Type": "application/x-ndjson"},
                            "".join(json.dumps(m) + "\n" for m in msgs).encode(), f"picks {entry.hosts[0]}")
        raise OpError("ops: /notify, /picks")
