"""Staff teams from staff.json (T1601): load, validate, assign roster rows to teams."""
import json
import os


def path():
    """The staff file: $STAFF_FILE, else $HARNESS_HOME/staff.json (default ~/agents)."""
    home = os.environ.get("HARNESS_HOME") or os.path.expanduser("~/agents")
    return os.environ.get("STAFF_FILE") or os.path.join(home, "staff.json")


def _validate(data):
    """Raise ValueError on the first problem in a staff file."""
    seen, teams = {}, set()
    for t in data["teams"]:
        if not str(t.get("id") or "").strip() or not str(t.get("name") or "").strip():
            raise ValueError(f"team {t.get('id')}: empty id or name")
        if t["id"] in teams:
            raise ValueError(f"duplicate team id {t['id']}")
        teams.add(t["id"])
        for m in t["members"]:
            mid = m.get("id")
            if not str(mid or "").strip():
                raise ValueError(f"team {t['id']}: a member with an empty id")
            if mid in seen:
                if seen[mid] == t["id"]:
                    raise ValueError(f"duplicate member id {mid} in {t['id']}")
                raise ValueError(f"member {mid} in 2 teams: {seen[mid]}, {t['id']}")
            seen[mid] = t["id"]
            for k in ("name", "rank"):
                if not str(m.get(k) or "").strip():
                    raise ValueError(f"member {mid}: empty {k}")
            if "unit" in m and not str(m["unit"]).endswith((".timer", ".service")):
                raise ValueError(f"member {mid}: unit {m['unit']} is not a .timer or .service")
    if not isinstance(data.get("hidden", []), list):
        raise ValueError("hidden must be a list")


def load(p=None):
    """The validated staff file: {teams, hidden}."""
    with open(p or path()) as f:
        data = json.load(f)
    _validate(data)
    return data


def assign(teams, hidden, rows, seat_folders):
    """Teams with each member's roster row merged in, plus an Unassigned team for rows in no team, no seat folder and not hidden."""
    by = {r["name"]: r for r in rows}
    placed = {m["id"] for t in teams for m in t["members"]} | set(hidden) | set(seat_folders)
    out = [dict(t, members=[dict(by.get(m["id"], {}), **m) for m in t["members"]]) for t in teams]
    loose = [dict(r, id=r["name"], rank="Staff") for r in rows if r["name"] not in placed]
    return out + [{"id": "unassigned", "name": "Unassigned", "members": loose}] if loose else out
