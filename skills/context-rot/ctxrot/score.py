"""Score a JSON reply against the gold answers."""
import json
import re


def _norm(s) -> str:
    return re.sub(r"[^a-z0-9:]+", "", str(s).lower()) if s is not None else ""


def parse(text: str) -> dict:
    """Return the first JSON object in the reply, or {} when there is none."""
    m = re.search(r"\{.*\}", text, re.S)
    try:
        return json.loads(m.group(0)) if m else {}
    except json.JSONDecodeError:
        pass
    for flat in reversed(re.findall(r"\{[^{}]*\}", text)):  # a draft object, notes, then the final object
        try:
            return json.loads(flat)
        except json.JSONDecodeError:
            continue
    return {}


def grade(text: str, facts, join_answer: str) -> dict:
    """Return per-fact correctness keyed by fact kind, join correctness and the parsed reply."""
    got = parse(text)
    per = {f.key: _norm(f.answer) == _norm(got.get(f"q{i + 1}")) for i, f in enumerate(facts)}
    join = _norm(join_answer) == _norm(got.get("join"))
    return {"per_fact": per, "facts_ok": sum(per.values()), "join_ok": join, "parsed": bool(got), "reply": got}
