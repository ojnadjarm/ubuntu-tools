"""Small JSON state under state/: the seen badges and the pronunciation path's progress."""
import json, os
from datetime import datetime
from dash.cache import lock
from dash.env import HERE
from dash.routes import route
from dash.services import voice

SEEN_FILE = os.path.join(HERE, "state", "seen.json")


def seen_get():
    try:
        return json.load(open(SEEN_FILE))
    except (OSError, ValueError):
        return {}


def seen_add(keys):
    """Merge keys into state/seen.json; returns the full set."""
    with lock:
        seen = seen_get()
        seen.update({k: 1 for k in keys if isinstance(k, str)})
        os.makedirs(os.path.dirname(SEEN_FILE), exist_ok=True)
        tmp = SEEN_FILE + ".tmp"
        json.dump(seen, open(tmp, "w"))
        os.replace(tmp, SEEN_FILE)
    return seen


PROGRESS_FILE = os.path.join(HERE, "state", "pronunciation.json")


def progress_get():
    """The pronunciation path's cleared steps: {prompt_id: iso time}."""
    try:
        got = json.load(open(PROGRESS_FILE))
    except (OSError, ValueError):
        got = {}
    return {"cleared": got if isinstance(got, dict) else {}}


def progress_add(pid):
    """Mark one step cleared; returns the full set."""
    if not isinstance(pid, str) or not any(p["id"] == pid for p in voice.prompts()):
        return 400, {"error": "unknown prompt"}
    with lock:
        cleared = progress_get()["cleared"]
        cleared[pid] = datetime.now().astimezone().isoformat(timespec="seconds")
        os.makedirs(os.path.dirname(PROGRESS_FILE), exist_ok=True)
        tmp = PROGRESS_FILE + ".tmp"
        json.dump(cleared, open(tmp, "w"))
        os.replace(tmp, PROGRESS_FILE)
    return 200, {"cleared": cleared}


@route("GET", "/api/seen")
def seen_route(h, path):
    h.json(seen_get())


@route("POST", "/api/seen")
def seen_post_route(h, path):
    keys = h.body_json(1 << 20, [])
    h.json(seen_add(keys if isinstance(keys, list) else []))


@route("GET", "/api/voice/progress")
def progress_route(h, path):
    h.json(progress_get())


@route("POST", "/api/voice/progress")
def progress_post_route(h, path):
    body = h.body_json(4096, {})
    code, out = progress_add(body.get("cleared") if isinstance(body, dict) else None)
    h.json(out, code)
