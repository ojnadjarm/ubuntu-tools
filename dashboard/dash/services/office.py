"""GET /api/office (tailnet only): seats without the owner, live sessions, staff teams from staff.json with their runner rows, the orchestrator's agents and claims, and error when a source failed."""
import os, sys
from dash.cache import cache_meta, cached
from dash.routes import route
from dash.services import agents, runners, system
from dash.services import org as org_svc
from dash.services.sites import trusted

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "lib"))
import staff  # noqa: E402

OFFICE_TTL = 3
SEAT_KEYS = ("id", "name", "rank", "role", "parent", "area", "about", "wake")
LIVE = ("active", "activating", "reloading", "deactivating")
EMPTY = {"seats": [], "sessions": [], "staff": [], "agents": {"orchestrator": {}, "subagents": [], "claims": []}}


def timer_rows(units):
    """Roster-shaped rows for {member id: unit} members that have no agent folder, read through runners.facts + runners.view."""
    specs = [{"kind": "bash-timer" if u.endswith(".timer") else "service", "unit": u, "tmux": ""} for u in units.values()]
    F = runners.facts(specs, system.unit_props)
    out = []
    for name, s in zip(units, specs):
        r = runners.view(s, F, {"name": name, "last": {}, "report": ""}, system.human_cal)
        r.pop("fallback", None)
        work = F["units"].get(r["runner"].get("service") or s["unit"], {}).get("ActiveState")
        out.append(dict(r, state="running" if work in LIVE else "idle" if r["on"] else "off"))
    return out


def folder(seat):
    """The ~/agents/<name> folder name a seat's match names, None otherwise."""
    m = seat.get("match") or ""
    name = m[len("~/agents/"):] if m.startswith("~/agents/") else ""
    return name if name and "/" not in name else None


def compose(org, ags, cfg):
    """The office payload from the org payload, the agents payload (roster rows include the unit members) and the staff file."""
    rows = {r["name"]: r for r in ags.get("roster", [])}
    seats = [{k: s[k] for k in SEAT_KEYS if k in s} | ({"runner": rows[folder(s)]} if folder(s) in rows else {})
             for s in org.get("seats", []) if s["role"] != "owner"]
    folders = [f for s in org.get("seats", []) for f in [folder(s)] if f]
    out = {"seats": seats, "sessions": org.get("sessions", []),
           "staff": staff.assign(cfg["teams"], cfg.get("hidden", []), ags.get("roster", []), folders),
           "agents": {"orchestrator": ags.get("orchestrator", {}), "subagents": ags.get("subagents", []), "claims": ags.get("claims", [])}}
    err = "; ".join(e for e in (org.get("error"), ags.get("error")) if e)
    return {**out, "error": err} if err else out


def office_payload():
    """compose() over the cached org and agents reads, staff.json and the unit members' rows."""
    org = cached("org", org_svc.ORG_TTL, org_svc.org_payload, empty={"seats": [], "sessions": [], "hidden": 0})
    oerr = cache_meta({"org": (org_svc.org_payload, None, org_svc.ORG_TTL)})[1].get("org")
    ags = agents.payload()
    aerr = cache_meta({"agents_view": (agents.collect, None, 3)})[1].get("agents_view")
    cfg = staff.load()
    units = {m["id"]: m["unit"] for t in cfg["teams"] for m in t["members"] if m.get("unit")}
    roster = ags.get("roster", []) + (timer_rows(units) if units else [])
    return compose({**org, "error": oerr} if oerr else org, {**ags, "roster": roster} | ({"error": aerr} if aerr else {}), cfg)


@route("GET", "/api/office")
def office_route(h, path):
    if not trusted(h.client_address[0], h.headers.get("X-Forwarded-For")):
        return h.json({"error": "tailnet only"}, 403)
    body = cached("office", OFFICE_TTL, office_payload, empty=EMPTY)
    err = cache_meta({"office": (office_payload, None, OFFICE_TTL)})[1].get("office")
    h.json({**body, "error": err} if err else body)
