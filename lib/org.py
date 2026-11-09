"""Agent org seats from org.json (T1515): load, validate, parent, may_assign."""
import json
import os

ROLES = ("owner", "ceo", "po", "manager")
WAKES = ("po-inbox", "channel", "pull")
KEYS = ("id", "name", "role", "parent", "wake", "match")


def path():
    """The org file: $ORG_FILE, else $HARNESS_HOME/org.json (default ~/agents)."""
    home = os.environ.get("HARNESS_HOME") or os.path.expanduser("~/agents")
    return os.environ.get("ORG_FILE") or os.path.join(home, "org.json")


def _validate(seats):
    """Raise ValueError on the first problem in a seat list."""
    ids = {}
    for s in seats:
        missing = [k for k in KEYS if k not in s]
        if missing:
            raise ValueError(f"seat {s.get('id')}: missing {', '.join(missing)}")
        if s["id"] in ids:
            raise ValueError(f"duplicate seat id {s['id']}")
        if s["role"] not in ROLES:
            raise ValueError(f"seat {s['id']}: role {s['role']} not in {ROLES}")
        if s["role"] != "owner" and s["wake"] not in WAKES:
            raise ValueError(f"seat {s['id']}: wake {s['wake']} not in {WAKES}")
        if s["match"] is not None and not (s["match"] == "~" or s["match"].startswith("~/")):
            raise ValueError(f"seat {s['id']}: match must be ~ or ~/<path> (no machine paths)")
        ids[s["id"]] = s
    for s in seats:
        if s["role"] == "manager" and ids.get(s["parent"], {}).get("role") != "po":
            raise ValueError(f"seat {s['id']}: a manager's parent must be a po")
    if [s["role"] for s in seats].count("owner") != 1:
        raise ValueError("exactly one owner seat")
    for s in seats:
        if s["role"] == "owner":
            continue
        seen, cur = set(), s["id"]
        while cur is not None:
            if cur in seen:
                raise ValueError(f"seat {s['id']}: parent cycle")
            seen.add(cur)
            if cur not in ids:
                raise ValueError(f"seat {s['id']}: unknown parent {cur}")
            cur = ids[cur]["parent"]


def seats(p=None):
    """The validated seats of the org file, in file order."""
    with open(p or path()) as f:
        out = json.load(f)["seats"]
    _validate(out)
    return out


def _seat(seat_id, p=None):
    return next((s for s in seats(p) if s["id"] == seat_id), None)


def parent(seat_id, p=None):
    """The parent seat id, or None for the owner and unknown seats."""
    s = _seat(seat_id, p)
    return s["parent"] if s else None


def may_assign(a, b, p=None):
    """True when seat a may assign work to seat b: the owner to anyone else, the ceo to a po, a po to its managers."""
    sa, sb = _seat(a, p), _seat(b, p)
    if not sa or not sb or a == b:
        return False
    return (sa["role"] == "owner" or (sa["role"] == "ceo" and sb["role"] == "po")
            or (sa["role"] == "po" and sb["role"] == "manager" and sb["parent"] == a))
