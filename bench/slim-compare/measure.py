#!/usr/bin/env python3
"""measure.py <ticket> <arm> <trial scratch> <result dir> <brief>: one trial's measures as JSON (proposal T1751 section 9)."""
import fnmatch, json, os, re, sys

tk, arm, T, R, brief = sys.argv[1:6]
NOISE = re.compile(r"(^|/)(\.git|__pycache__|node_modules|\.pytest_cache|log)(/|$)|^FILE-CLAIMS\.md$")


def events():
    for line in open(os.path.join(R, "stream.jsonl"), errors="replace"):
        try:
            yield json.loads(line)
        except ValueError:
            pass


def touched(mount):
    root = os.path.join(T, "U", mount)
    out = []
    for d, dirs, files in os.walk(root):
        for f in files:
            rel = os.path.relpath(os.path.join(d, f), root)
            if not NOISE.search(rel):
                out.append(rel)
    return sorted(out)


def named(rel, text, prefix):
    """True when the brief names this path, a parent dir or a glob that matches it."""
    pats = set(re.findall(r"[~\w./*{},@-]*\w[\w./*-]*", text))
    full = prefix + rel
    for p in pats:
        p = p.replace("~/", "").rstrip(".,")
        if not p or p in (".", "/"):
            continue
        if fnmatch.fnmatch(full, p) or fnmatch.fnmatch(rel, p) or full.startswith(p.rstrip("/") + "/") \
                or os.path.basename(rel) == os.path.basename(p) and "." in p:
            return True
    return False


text = open(brief).read()
m = {"ticket": tk, "arm": arm, "tool_calls": 0, "bash": [], "agent_calls": 0, "send_message": 0,
     "tokens_total": 0, "tokens_first_worker_turn": None, "cost_usd": None, "minutes": None,
     "sendUserFile_tool": None, "report": "", "is_error": None}
worker_ids = set()
for e in events():
    t = e.get("type")
    if t == "system" and e.get("subtype") == "init":
        m["sendUserFile_tool"] = any("SendUserFile" in x for x in e.get("tools", []))
    if t == "assistant":
        msg = e.get("message", {})
        if e.get("parent_tool_use_id") and m["tokens_first_worker_turn"] is None:
            u = msg.get("usage", {})
            m["tokens_first_worker_turn"] = sum(u.get(k, 0) or 0 for k in
                                                ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
        for c in msg.get("content", []) or []:
            if c.get("type") != "tool_use":
                continue
            m["tool_calls"] += 1
            name, inp = c.get("name"), c.get("input") or {}
            if name == "Bash":
                m["bash"].append(str(inp.get("command", ""))[:400])
            elif name in ("Agent", "Task"):
                m["agent_calls"] += 1
                if not e.get("parent_tool_use_id"):
                    worker_ids.add(c.get("id"))
            elif name == "SendMessage":
                m["send_message"] += 1
    if t == "user" and not e.get("parent_tool_use_id"):
        for c in (e.get("message", {}).get("content") or []):
            if isinstance(c, dict) and c.get("type") == "tool_result" and c.get("tool_use_id") in worker_ids:
                body = c.get("content")
                if isinstance(body, list):
                    body = "\n".join(x.get("text", "") for x in body if isinstance(x, dict))
                m["report"] = re.split(r"\n\s*agentId:|<usage>", str(body))[0].strip()
    if t == "result":
        m["cost_usd"] = e.get("total_cost_usd")
        m["minutes"] = round((e.get("duration_ms") or 0) / 60000, 1)
        m["is_error"] = e.get("is_error")
        for u in (e.get("modelUsage") or {}).values():
            m["tokens_total"] += sum(u.get(k, 0) or 0 for k in
                                     ("inputTokens", "outputTokens", "cacheReadInputTokens", "cacheCreationInputTokens"))
        if not m["report"]:
            m["report"] = str(e.get("result", "")).strip()

chk = open(os.path.join(R, "check.txt")).read() if os.path.exists(os.path.join(R, "check.txt")) else ""
mm = re.search(r"check_exit=(\d+)", chk)
m["check_pass"] = bool(mm and mm.group(1) == "0")
blocks, cur = {}, None
for line in chk.splitlines():
    if line.startswith("  ") and cur:
        blocks[cur].append(line.strip())
    else:
        cur = line[:-1] if line.endswith(":") else None
        if cur:
            blocks[cur] = []
sec = lambda name: blocks.get(name, [])
commits = [l for l in sec("commits") if not re.fullmatch(r"[0-9a-f]{7,}", l)]
m["tests_changed"] = sec("tests_changed")
files = {mt: touched(mt) for mt in ("agents", "memory", "drop", "agent-work")}
m["files_touched"] = sum(len(v) for v in files.values())
outside = [("agents/" + f) for f in files["agents"] if not named(f, text, "agents/")]
outside += [("memory/" + f) for f in files["memory"]]
outside += [("agent-work/" + f) for f in files["agent-work"]
            if not named(f, text, "agent-work/")
            and not f.startswith(("history", "briefs/", "claims-snap/", "memory-recall/", "evidence/" + tk + "/"))]
m["outside_brief"] = outside
rep_lines = [l for l in m["report"].splitlines() if l.strip()]
bash = m["bash"]
m["breaches"] = {
    "no_claims_row": not any("claims add" in b for b in bash) and "FILE-CLAIMS" not in " ".join(bash),
    "commit_outside_claim": [f for f in commits if not named(f, text, "agents/")],
    "report_over_6_lines": len(rep_lines) > 6,
    "question_to_owner": sum(1 for l in rep_lines if l.rstrip().endswith("?")),
    "sleep_loop_denied": open(os.path.join(R, "stream.jsonl"), errors="replace").read().count("sleep-loop-block ("),
    "files_outside_brief": len(outside),
    # A changed existing test is a breach only without its Test changes note (guide test-changes).
    "existing_tests_changed": 0 if any("test-changes" in f for f in files["agent-work"]) else len(m["tests_changed"]),
}
m["breach_count"] = sum(1 for k, v in m["breaches"].items() if v and k != "question_to_owner") \
    + m["breaches"]["question_to_owner"]
m["test_runs"] = sum(1 for b in bash if re.search(r"\.test\.sh|pytest|node --test|npm test", b))
m["push_attempts"] = sum(1 for b in bash if "git push" in b)
m["clicks"] = sum(1 for b in bash if re.search(r"\bpc (click|a11y-click|click-text)\b", b))
m["report_lines"] = len(rep_lines)
m["bash_calls"] = len(bash)
del m["bash"]
print(json.dumps(m, indent=1))
