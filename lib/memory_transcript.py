"""The owner's own words in a session transcript: the human turns provenance quotes are checked against (T1629)."""
import glob
import json
import os
import re

SESSION = re.compile(r"^[0-9A-Za-z-]+$")


def _norm(s):
    return " ".join(s.lower().split())


def human_text(e):
    """The text a human typed in one transcript record: a user turn or a queued mid-turn prompt of origin human
    (a turn without an origin only outside headless runs); [] for tool output, peers, channels, meta and summaries."""
    if e.get("isSidechain"):
        return []
    if e.get("type") == "user" and not any(e.get(k) for k in ("isMeta", "isCompactSummary")):
        kind = (e.get("origin") or {}).get("kind")
        if kind != "human" and (kind or str(e.get("entrypoint", "")).startswith("sdk")):
            return []
        c = (e.get("message") or {}).get("content")
    elif e.get("type") == "attachment" and (e.get("attachment") or {}).get("type") == "queued_command" \
            and ((e["attachment"].get("origin") or {}).get("kind") == "human"):
        c = e["attachment"].get("prompt")
    else:
        return []
    parts = [c] if isinstance(c, str) else [b.get("text", "") for b in c or [] if isinstance(b, dict) and b.get("type") == "text"]
    parts = [re.sub(r"<system-reminder>.*?</system-reminder>", "", p, flags=re.S) for p in parts]
    return [p for p in parts if not p.lstrip().startswith("<task-notification>")]


def owner_words(session):
    """The owner's own turns in a transcript, normalised; None when no transcript has that session id."""
    if not SESSION.match(session or ""):
        return None
    hits = glob.glob(os.path.join(os.path.expanduser("~/.claude/projects"), "*", session + ".jsonl"))
    if not hits:
        return None
    said = []
    with open(hits[0], encoding="utf-8", errors="replace") as f:
        for raw in f:
            try:
                e = json.loads(raw)
            except ValueError:
                continue
            if isinstance(e, dict):
                said += human_text(e)
    return _norm(" ".join(said))
