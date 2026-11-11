"""The status of an office section (an org.json seat or a staff.json team): the one list of statuses, check on load, view for the page."""
import datetime

STATUSES = {"active": "Active", "paused": "Paused", "vacation": "On vacation"}
KEYS = ("id", "since", "note")


def check(where, raw):
    """Raise ValueError naming `where` when raw is not absent or {id, since?, note?} with a known id and a YYYY-MM-DD since."""
    if raw is None:
        return
    if not isinstance(raw, dict) or set(raw) - set(KEYS):
        raise ValueError(f"{where}: status must be an object with keys {', '.join(KEYS)}")
    if raw.get("id") not in STATUSES:
        raise ValueError(f"{where}: status id {raw.get('id')!r} not in {tuple(STATUSES)}")
    if "since" in raw:
        try:
            datetime.date.fromisoformat(str(raw["since"]))
        except ValueError:
            raise ValueError(f"{where}: status since {raw['since']!r} is not YYYY-MM-DD") from None
    if "note" in raw and not isinstance(raw["note"], str):
        raise ValueError(f"{where}: status note must be text")


def view(raw):
    """None when absent or active, else {id, label, since?, note?}."""
    if not raw or raw["id"] == "active":
        return None
    return {"id": raw["id"], "label": STATUSES[raw["id"]], **{k: raw[k] for k in ("since", "note") if raw.get(k)}}
