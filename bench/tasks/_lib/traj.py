#!/usr/bin/env python3
"""Count tool calls in a stream-json transcript and whether a regex matched a command that succeeded."""
import json, re, sys

path = sys.argv[1]
pat = re.compile(sys.argv[2], re.I) if len(sys.argv) > 2 and sys.argv[2] else None
out = {"stream": False, "tool_calls": 0, "bash_calls": 0, "matched": 0, "matched_ok": 0,
       "guard_hits": 0, "errors": 0}
try:
    recs = [json.loads(l) for l in open(path) if l.strip()]
except Exception:
    print(json.dumps(out)); sys.exit(0)
if not recs:
    print(json.dumps(out)); sys.exit(0)
out["stream"] = True
results = {}
for r in recs:
    if r.get("type") != "user":
        continue
    c = r.get("message", {}).get("content")
    for b in (c if isinstance(c, list) else []):
        if isinstance(b, dict) and b.get("type") == "tool_result":
            body = b.get("content")
            if not isinstance(body, str):
                body = json.dumps(body)
            results[b.get("tool_use_id")] = (bool(b.get("is_error")), body)
for r in recs:
    if r.get("type") != "assistant":
        continue
    for b in r.get("message", {}).get("content", []):
        if b.get("type") != "tool_use":
            continue
        out["tool_calls"] += 1
        err, body = results.get(b.get("id"), (False, ""))
        if err:
            out["errors"] += 1
        if "pc: refused" in body:
            out["guard_hits"] += 1
        if b.get("name") != "Bash":
            continue
        cmd = b.get("input", {}).get("command", "")
        out["bash_calls"] += 1
        if pat and pat.search(cmd):
            out["matched"] += 1
            if not err:
                out["matched_ok"] += 1
print(json.dumps(out))
