"""GET /api/memory, /api/memory/page, /api/memory/net and /api/memory/net/try (tailnet only, read-only): the memory store's page index, one page's lines, the recall network and one dry recall, through lib/memory_store and lib/memory_view; PRIVATE pages by name only."""
import os, sys, urllib.parse
from dash.cache import cached
from dash.routes import route
from dash.services.sites import trusted

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "lib"))
import memory_store  # noqa: E402
import memory_view  # noqa: E402

INDEX_TTL, NET_TTL, Q_MAX = 30, 60, 2000


def store():
    """The store MEMORY_HOME names (env, else config.env, else ~/memory)."""
    return memory_store.Store(memory_store.home())


def served(s, page):
    """True when page is a card or topic file whose real path stays inside the store and no part of it is a dotfile."""
    root = os.path.realpath(s.root)
    real = os.path.realpath(s.path(page))
    return not any(p.startswith(".") for p in page.split("/")) and real.startswith(root + os.sep) \
        and not any(p.startswith(".") for p in os.path.relpath(real, root).split(os.sep))


def index(s):
    """Every served page with bytes and last change; a PRIVATE page as its name only."""
    rows = []
    for p in s.pages():
        if not served(s, p):
            continue
        if s.private_seats(p) is not None:
            rows.append({"page": p, "private": True})
            continue
        st = os.stat(s.path(p))
        rows.append({"page": p, "bytes": st.st_size, "mtime": st.st_mtime})
    return {"pages": rows, "count": len(rows), "private": sum(1 for r in rows if r.get("private"))}


@route("GET", "/api/memory")
def index_route(h, path):
    if not trusted(h.client_address[0], h.headers.get("X-Forwarded-For")):
        return h.json({"error": "tailnet only"}, 403)
    s = store()
    h.json(cached("memory:" + s.root, INDEX_TTL, lambda: index(s), empty={"pages": [], "count": 0, "private": 0}))


@route("GET", "/api/memory/page")
def page_route(h, path):
    if not trusted(h.client_address[0], h.headers.get("X-Forwarded-For")):
        return h.json({"error": "tailnet only"}, 403)
    s, p = store(), urllib.parse.parse_qs(h.path.partition("?")[2]).get("p", [""])[0]
    if p not in s.pages() or not served(s, p):
        return h.json({"error": "not a memory page"}, 400)
    if s.private_seats(p) is not None:
        return h.json({"page": p, "private": True, "error": "private page: read it in Obsidian on the PC"}, 403)
    st = os.stat(s.path(p))
    h.json({"page": p, "bytes": st.st_size, "mtime": st.st_mtime, "lines": memory_store.strip_ids(s.text(p)).rstrip("\n").split("\n")})


@route("GET", "/api/memory/net")
def net_route(h, path):
    if not trusted(h.client_address[0], h.headers.get("X-Forwarded-For")):
        return h.json({"error": "tailnet only"}, 403)
    s = store()
    h.json(cached("memory-net:" + s.root, NET_TTL, lambda: memory_view.export(s), empty={"memories": [], "places": [], "links": []}))


@route("GET", "/api/memory/net/try")
def try_route(h, path):
    """One dry recall of ?q= as the owner's own session (nothing written, the prompt never logged)."""
    if not trusted(h.client_address[0], h.headers.get("X-Forwarded-For")):
        return h.json({"error": "tailnet only"}, 403)
    q = urllib.parse.parse_qs(h.path.partition("?")[2]).get("q", [""])[0]
    if not q.strip() or len(q) > Q_MAX:
        return h.json({"error": f"type a prompt of 1 to {Q_MAX} characters"}, 400)
    h.json(memory_view.trial(store(), q))
