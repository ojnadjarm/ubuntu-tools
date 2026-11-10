"""Chat routes (tailnet only): GET /api/chat reads, POST /api/chat/post (then wakes), /seen and /upload act as the owner,
GET /api/chat/file/<id> serves an attachment to the owner; the lib does the work."""
import ipaddress, os, re, sys, urllib.parse
from dash.routes import route
from dash.services.sites import trusted

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "lib"))
import chat_dispatch  # noqa: E402
import chat_files  # noqa: E402
import chat_guard  # noqa: E402
import chat_store  # noqa: E402
import chat_thinking  # noqa: E402

OWNER = "owner"
BODY_LIMIT = 16384
PAGE = 50


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


def page(ch, recent, after, before):
    """(messages, more) of a channel, or of every channel when recent: PAGE newest (older than before), or what is newer
    than after; more is True while older messages exist. Neither: no messages (the badge tick)."""
    if not ch and not recent:
        return [], False
    if after is not None:
        return (chat_store.read(ch, after) if ch else chat_store.recent(OWNER, after=after, limit=200)), False
    rows = (chat_store.read(ch, before=before, limit=PAGE + 1) if ch
            else chat_store.recent(OWNER, before=before, limit=PAGE + 1))
    return rows[-PAGE:], len(rows) > PAGE


@route("GET", "/api/chat")
def read_route(h, path):
    if not tailnet(h):
        return h.json({"error": "tailnet only"}, 403)
    q = urllib.parse.parse_qs(urllib.parse.urlsplit(h.path).query)
    ch, after, before = q.get("ch", [""])[0], q.get("after", [None])[0], q.get("before", [None])[0]
    try:
        if before is not None:
            before = int(before)
        messages, more = page(ch, q.get("recent") == ["1"], after, before)
    except ValueError as e:
        return h.json({"error": str(e)}, 400)
    h.json({"messages": messages, "more": more, "channels": chat_store.channels(OWNER),
            "wakes": {"today": chat_dispatch.today()}, "thinking": chat_thinking.now()})


def attached(ids):
    """The stored metadata of the posted file ids; ValueError on a bad list or an unknown id."""
    if not isinstance(ids, list) or len(ids) > chat_files.MAX_FILES:
        raise ValueError(f"bad files: a list of at most {chat_files.MAX_FILES} ids")
    return [chat_files.meta(i) for i in ids]


@route("POST", "/api/chat/post")
def post_route(h, path):
    if not is_owner(h):
        return h.json({"error": "owner only"}, 403)
    body = h.body_json(BODY_LIMIT, {})
    ch, text = body.get("ch"), body.get("text")
    try:
        files = attached(body.get("files", []))
    except ValueError as e:
        return h.json({"error": str(e)}, 400)
    ok, reason = chat_guard.check(text, OWNER, ch if isinstance(ch, str) else None, (), [f["name"] for f in files])
    if not ok:
        if isinstance(ch, str) and chat_store.NAME.match(ch):
            chat_store.audit({"seat": OWNER, "ch": ch, "held": reason})
        return h.json({"held": reason}, 422)
    msg = {"ch": ch, "from": OWNER, "text": text, **({"files": files} if files else {})}
    try:
        mid = chat_store.post(msg)
    except ValueError as e:
        return h.json({"error": str(e)}, 400)
    woke = chat_dispatch.dispatch({**msg, "id": mid, "to": [], "kind": "msg", "re": None, "hop": 0})
    h.json({"id": mid, "wakes": [{"seat": seat, "outcome": out} for seat, out in woke]})


@route("POST", "/api/chat/upload")
def upload_route(h, path):
    """One file as the raw body, its name in X-File-Name (URL-encoded); {id, name, size, mime} for a later post."""
    if not is_owner(h):
        return h.json({"error": "owner only"}, 403)
    size = h.headers.get("Content-Length") or ""
    if not (size.isascii() and size.isdigit()):
        return h.json({"error": "bad Content-Length"}, 400)
    if int(size) > chat_files.MAX_BYTES:
        return h.json({"error": f"file over {chat_files.MAX_BYTES >> 20} MiB: {size} bytes"}, 413)
    name = chat_files.clean_name(urllib.parse.unquote(h.headers.get("X-File-Name") or ""))
    ok, reason = chat_guard.check("", OWNER, None, (), [name])
    if not ok:
        h.rfile.read(int(size))
        chat_store.audit({"seat": OWNER, "upload": True, "held": reason})
        return h.json({"held": reason}, 422)
    try:
        h.json(chat_files.save(h.rfile.read(int(size)), name))
    except ValueError as e:
        h.json({"error": str(e)}, 400)


@route("GET", "/api/chat/file/", prefix=True)
def file_route(h, path):
    """An attachment (thumb=1: an image's WebP thumbnail): images inline, anything else as a download; owner only."""
    if not is_owner(h):
        return h.json({"error": "owner only"}, 403)
    fid = path[len("/api/chat/file/"):]
    thumb = "thumb=1" in urllib.parse.urlsplit(h.path).query
    try:
        m = chat_files.meta(fid)
        with open(chat_files.path(fid, thumb), "rb") as f:
            data = f.read()
    except (ValueError, OSError):
        return h.send(404, b"not found\n", "text/plain")
    image = m["mime"].startswith("image/")
    h.send_response(200)
    h.send_header("Content-Type", "image/webp" if thumb else m["mime"])
    h.send_header("Content-Length", str(len(data)))
    h.send_header("X-Content-Type-Options", "nosniff")
    h.send_header("Cache-Control", "private, max-age=31536000, immutable")
    if image:
        h.send_header("Content-Disposition", "inline")
    else:
        ascii_name = re.sub(r"[^ -~]+", "_", m["name"].replace('"', "").replace("\\", ""))
        h.send_header("Content-Disposition", "attachment; filename=\"%s\"; filename*=UTF-8''%s"
                      % (ascii_name, urllib.parse.quote(m["name"], safe="")))
    h.end_headers()
    if not getattr(h, "head_only", False):
        h.wfile.write(data)


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
