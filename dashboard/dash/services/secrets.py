"""Agents › Vault: the broker's names, classes, ages and uses (never a value); Add and Replace live on the broker's own page."""
import os, sys
from urllib.parse import quote
from dash.env import HOME
from dash.routes import route

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "lib"))
from vault import wire  # noqa: E402

PAGE = "/vault"
WHO = 3


def sock():
    return os.environ.get("FLEET_VAULT_SOCKET", "/run/fleet-vault/admin.sock")


def secrets_dir():
    return os.path.join(os.environ.get("HARNESS_HOME", os.path.join(HOME, "agents")), "secrets")


def state(row):
    """(state, since): sealed with its sealed-at, file with the legacy file's mtime (stat only), else empty."""
    if row.get("sealed"):
        return "sealed", row.get("sealed_at")
    if row.get("legacy"):
        try:
            return "file", os.stat(os.path.join(secrets_dir(), row["legacy"])).st_mtime
        except OSError:
            pass
    return "empty", None


def who(events, name):
    """The last WHO distinct callers (ticket, agent, result) of name's grants and uses, newest first."""
    out, seen = [], set()
    for ev in reversed(events):
        if ev.get("secret") != name or ev.get("event") not in ("use", "grant"):
            continue
        k = (ev.get("ticket") or "", ev.get("agent") or "", ev.get("result") or "")
        if k in seen:
            continue
        seen.add(k)
        out.append({"ticket": k[0], "agent": k[1], "result": k[2], "ts": ev.get("ts")})
        if len(out) == WHO:
            break
    return out


def summary():
    """{secrets, add, error}: one row per name from the broker's list and log ops."""
    try:
        rows = wire.call(sock(), {"op": "list"}, timeout=5)
        events = wire.call(sock(), {"op": "log", "n": 2000}, timeout=5)
    except (OSError, ValueError) as e:
        return {"secrets": [], "add": PAGE + "/add", "error": "broker unreachable (%s)" % type(e).__name__}
    if not rows.get("ok") or not events.get("ok"):
        return {"secrets": [], "add": PAGE + "/add", "error": rows.get("error") or events.get("error") or "refused"}
    out = []
    for r in rows["secrets"]:
        st, since = state(r)
        out.append({"name": r["name"], "class": r["class"], "used_in": r["used_in"], "added": r["added"], "state": st,
                    "since": since, "last_used": r["last_used"], "uses_7d": r["uses_7d"],
                    "refusals_7d": r["refusals_7d"], "reissue": r["reissue"], "who": who(events["events"], r["name"]),
                    "replace": PAGE + "/replace?name=" + quote(r["name"])})
    return {"secrets": out, "add": PAGE + "/add", "error": ""}


@route("GET", "/api/secrets")
def list_route(h, path):
    s = summary()
    h.json(s, 503 if s["error"] else 200)
