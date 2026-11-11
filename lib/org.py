"""Agent org seats from org.json (T1515): load, validate, parent, may_assign, seat_at, rank, proper_name, abouts."""
import json
import os
import zlib

import section_status

ROLES = ("owner", "ceo", "po", "manager")
WAKES = ("po-inbox", "channel", "pull")
KEYS = ("id", "name", "role", "parent", "wake", "match")
RANKS = {"owner": "Owner", "ceo": "CEO", "po": "Product Owner", "manager": "Manager", "worker": "Worker", "crew": "Crew"}
NAMES = ("Bramble", "Cinder", "Gloam", "Thistle", "Murmur", "Speckle", "Mossfang", "Cobalt", "Wick", "Ember", "Nettle",
         "Flint", "Hollow", "Quill", "Sable", "Tansy", "Umber", "Vesper", "Wren", "Yarrow", "Fennel", "Briar", "Lumen",
         "Pebble", "Soot", "Moth", "Dusk", "Rune", "Sorrel", "Tarn")


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
        section_status.check(f"seat {s['id']}", s.get("status"))
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


def seat_at(cwd, seat_list):
    """The seat whose folder holds cwd (deepest wins; the ~ catch-all never), by string only: nothing is stat'd."""
    cwd = os.path.normpath(cwd)
    held = [(len(f), s["id"]) for s in seat_list if s["match"] and s["match"] != "~"
            for f in [os.path.normpath(os.path.expanduser(s["match"]))] if cwd == f or cwd.startswith(f + "/")]
    return max(held)[1] if held else None


def rank(role):
    """The rank label of a role (CEO, Product Owner, Manager, Worker, Crew); an unknown role is a Worker."""
    return RANKS.get(role, "Worker")


def proper_name(seat_id, taken):
    """A one-word proper name for a new seat: the same for the same id, never one of taken."""
    free = [n for n in NAMES if n not in set(taken)]
    if not free:
        return seat_id.split("-")[0].capitalize()
    return free[zlib.crc32(seat_id.encode()) % len(free)]


def abouts(seat_list, projects=None):
    """Each seat's project about: its own org.json `about`, else the projects.json entry with its id (Discord projects)."""
    home = os.environ.get("HARNESS_HOME") or os.path.expanduser("~/agents")
    try:
        with open(projects or os.environ.get("LIAISON_REGISTRY") or os.path.join(home, "discord-liaison", "projects.json")) as f:
            ents = {e["id"]: e.get("about") for e in json.load(f)["projects"]}
    except (OSError, ValueError, KeyError):
        ents = {}
    return {s["id"]: a for s in seat_list for a in [s.get("about") or ents.get(s["id"])] if a}


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
