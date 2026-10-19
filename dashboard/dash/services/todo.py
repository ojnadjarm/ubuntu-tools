"""Owner to-do: the open "waiting on you" items from the owner-todo ledger, and the dashboard's Done button."""
import os, sys
from dash.env import HOME
from dash.routes import route

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "lib"))
import owner_todo  # noqa: E402


def open_items():
    return owner_todo.items(HOME)


def checked():
    """(open items, error text): a broken ledger never raises; its skipped lines or the exception become the text."""
    try:
        got, bad = owner_todo.read(HOME)
        return got, "; ".join(bad)
    except Exception as e:
        return [], "%s: %s" % (type(e).__name__, e)


@route("GET", "/api/owner-todo")
def list_route(h, path):
    h.json(open_items())


@route("POST", "/api/owner-todo/done")
def done_route(h, path):
    body = h.body_json(4096, {})
    tid = body.get("id") if isinstance(body, dict) else None
    try:
        owner_todo.done(str(tid), "tapped Done on the dashboard", "dashboard", HOME)
    except (KeyError, ValueError) as e:
        return h.json({"error": e.args[0] if e.args else "bad id"}, 400)
    h.json({"ok": True, "id": str(tid)})
