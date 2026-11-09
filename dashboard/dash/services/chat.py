"""Chat routes (tailnet only): GET /api/chat reads, POST /api/chat/post (then wakes) and /seen act as the owner; the lib does the work."""
import ipaddress, os, sys, urllib.parse
from dash.routes import route
from dash.services.sites import trusted

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "lib"))
import chat_dispatch  # noqa: E402
import chat_guard  # noqa: E402
import chat_route  # noqa: E402
import chat_store  # noqa: E402

OWNER = "owner"
BODY_LIMIT = 16384


def is_owner(h):
    """True for a loopback caller (the tailnet front) whose Tailscale-User-Login is CHAT_OWNER_LOGIN; unset fails closed."""
    login = os.environ.get("CHAT_OWNER_LOGIN", "")
    if not login or h.headers.get("Tailscale-User-Login") != login or not tailnet(h):
        return False
    a = ipaddress.ip_address(h.client_address[0].split("%")[0])
    return (getattr(a, "ipv4_mapped", None) or a).is_loopback


def tailnet(h):
    """sites.trusted() for this request, X-Forwarded-For included."""
    return trusted(h.client_address[0], h.headers.get("X-Forwarded-For"))


@route("GET", "/api/chat")
def read_route(h, path):
    if not tailnet(h):
        return h.json({"error": "tailnet only"}, 403)
    q = urllib.parse.parse_qs(urllib.parse.urlsplit(h.path).query)
    ch, after = q.get("ch", [""])[0], q.get("after", [None])[0]
    try:
        messages = chat_store.read(ch, after) if ch else []
    except ValueError as e:
        return h.json({"error": str(e)}, 400)
    h.json({"messages": messages, "channels": chat_store.channels(OWNER),
            "wakes": {"cap": chat_route.CAP, "today": chat_dispatch.today()}})


@route("POST", "/api/chat/post")
def post_route(h, path):
    if not is_owner(h):
        return h.json({"error": "owner only"}, 403)
    body = h.body_json(BODY_LIMIT, {})
    ch, text = body.get("ch"), body.get("text")
    ok, reason = chat_guard.check(text, OWNER)
    if not ok:
        if isinstance(ch, str) and chat_store.NAME.match(ch):
            chat_store.audit({"seat": OWNER, "ch": ch, "held": reason})
        return h.json({"held": reason}, 422)
    msg = {"ch": ch, "from": OWNER, "text": text}
    try:
        mid = chat_store.post(msg)
    except ValueError as e:
        return h.json({"error": str(e)}, 400)
    woke = chat_dispatch.dispatch({**msg, "id": mid, "to": [], "kind": "msg", "re": None, "hop": 0})
    h.json({"id": mid, "wakes": [{"seat": seat, "outcome": out} for seat, out in woke]})


@route("POST", "/api/chat/seen")
def seen_route(h, path):
    if not is_owner(h):
        return h.json({"error": "owner only"}, 403)
    body = h.body_json(BODY_LIMIT, {})
    if type(body.get("id")) is not int:
        return h.json({"error": "bad id"}, 400)
    try:
        chat_store.mark(OWNER, body.get("ch"), body["id"])
    except ValueError as e:
        return h.json({"error": str(e)}, 400)
    h.json({"ok": True})
