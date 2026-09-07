#!/usr/bin/env python3
"""Read a stream-json trial transcript, print the trajectory metrics PB02 will report."""
import json, re, sys
from collections import Counter

path = sys.argv[1]
recs = [json.loads(l) for l in open(path) if l.strip()]
tools, bash, pcverbs, raw = [], [], Counter(), Counter()
shots = 0
RAW = {"top": r"\btop -b", "ps": r"\bps +(aux|-e)", "journalctl": r"\bjournalctl\b",
       "dmesg": r"\bdmesg\b", "docker ps": r"\bdocker (ps|inspect|stats)\b",
       "systemctl": r"\bsystemctl\b", "pactl/wpctl": r"\b(pactl|wpctl)\b",
       "/proc": r"/proc/(stat|loadavg|[0-9]+)", "pidstat/mpstat": r"\b(pidstat|mpstat|vmstat|iostat)\b"}
for r in recs:
    if r.get("type") != "assistant":
        continue
    for b in r["message"].get("content", []):
        if b.get("type") != "tool_use":
            continue
        tools.append(b["name"])
        if b["name"] == "Bash":
            cmd = b["input"].get("command", "")
            bash.append(cmd)
            for m in re.finditer(r"(?:^|[|;&(]\s*|\bsudo\s+|\btimeout \S+\s+)pc\s+([a-z0-9-]+)", cmd):
                pcverbs[m.group(1)] += 1
            for name, pat in RAW.items():
                if re.search(pat, cmd):
                    raw[name] += 1
            if re.search(r"\bpc (shot|wait|find|click-text)\b", cmd):
                shots += 1
        if b["name"] == "Read" and str(b["input"].get("file_path", "")).endswith(".png"):
            shots += 1
res = next((r for r in recs if r.get("type") == "result"), {})
u = res.get("usage", {})
out = {
    "session_id": res.get("session_id"), "subtype": res.get("subtype"),
    "wall_s": round(res.get("duration_ms", 0) / 1000, 1),
    "api_s": round(res.get("duration_api_ms", 0) / 1000, 1),
    "turns": res.get("num_turns"), "cost_usd": round(res.get("total_cost_usd", 0), 4),
    "tokens_in": u.get("input_tokens"), "tokens_out": u.get("output_tokens"),
    "cache_read": u.get("cache_read_input_tokens"), "cache_write": u.get("cache_creation_input_tokens"),
    "tool_calls": len(tools), "tool_histogram": dict(Counter(tools)),
    "bash_calls": len(bash), "pc_calls": sum(pcverbs.values()), "pc_verbs": dict(pcverbs),
    "raw_recipes": dict(raw), "screenshots": shots,
    "permission_denials": len(res.get("permission_denials", [])),
    "guard_hits": sum(1 for c in bash if "exit 3" in c),
    "structured_output": res.get("structured_output"),
}
print(json.dumps(out, indent=2))
