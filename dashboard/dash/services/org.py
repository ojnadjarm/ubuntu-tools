"""GET /api/org (tailnet only): the org seats, the live Claude sessions with their seat, and how many registry rows are hidden."""
import glob, os, sys
from dash.cache import cached
from dash.env import HOME
from dash.routes import route
from dash.services.sites import trusted

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "lib"))
import org  # noqa: E402
import sessions  # noqa: E402

ORG_TTL = 5


def tilde(p):
    """A home path as ~/…, anything else unchanged."""
    return "~" + p[len(HOME):] if p == HOME or p.startswith(HOME + "/") else p


def org_payload():
    """{seats, sessions, hidden}: hidden = registry files that are not a live session (ended, unreadable)."""
    live = sessions.live()
    for s in live:
        if "cwd" in s:
            s["cwd"] = tilde(s["cwd"])
    total = len(glob.glob(os.path.join(sessions.registry_dir(), "*.json")))
    return {"seats": org.seats(), "sessions": live, "hidden": max(0, total - len(live))}


@route("GET", "/api/org")
def org_route(h, path):
    if not trusted(h.client_address[0], h.headers.get("X-Forwarded-For")):
        return h.json({"error": "tailnet only"}, 403)
    h.json(cached("org", ORG_TTL, org_payload, empty={"seats": [], "sessions": [], "hidden": 0}))
