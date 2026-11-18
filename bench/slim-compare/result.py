#!/usr/bin/env python3
"""result.py: RESULT.md (≤ 40 lines) from the trials' measures: per rule of the 33, keep or can go, with its number."""
import csv, glob, json, os

H = os.path.expanduser("~")
OUT = os.environ.get("T1773_OUT", os.path.join(H, "agent-work", "research", "2026-11-18", "T1773"))
SCR = os.environ.get("T1773_SCRATCH", os.path.join(H, ".cache", "t1773"))
ARMS = ("old", "slim")

runs = {a: [] for a in ARMS}
for f in sorted(glob.glob(os.path.join(OUT, "runs", "*", "measures.json"))):
    m = json.load(open(f))
    runs[m["arm"]].append(m)
safety = {a: [json.loads(l) for l in open(os.path.join(OUT, "safety", a + ".jsonl")) if l.strip()]
          if os.path.exists(os.path.join(OUT, "safety", a + ".jsonl")) else [] for a in ARMS}
removed = {r["id"]: r["removed"] for r in csv.DictReader(
    open(os.path.join(SCR, "arms", "slim", "drop-report.tsv")), delimiter="\t")}
rules = list(csv.DictReader(open(os.path.join(OUT, "drop33.tsv")), delimiter="\t", quoting=csv.QUOTE_NONE))

tot = lambda a, k: sum((m.get(k) or 0) for m in runs[a])
cnt = lambda a, f: sum(1 for m in runs[a] if f(m))
S = {
    "pass": {a: cnt(a, lambda m: m["check_pass"]) for a in ARMS},
    "breaches": {a: tot(a, "breach_count") for a in ARMS},
    "test_runs": {a: tot(a, "test_runs") for a in ARMS},
    "send_message": {a: tot(a, "send_message") for a in ARMS},
    "over6": {a: cnt(a, lambda m: m["breaches"]["report_over_6_lines"]) for a in ARMS},
    "clicks": {a: tot(a, "clicks") for a in ARMS},
    "safe": {a: sum(1 for r in safety[a] if r.get("pass") == 1) for a in ARMS},
}
n = {a: len(runs[a]) for a in ARMS}
pair = lambda k: "old %s · slim %s" % (S[k]["old"], S[k]["slim"])
ok_le = lambda k: S[k]["slim"] <= S[k]["old"]


def verdict(r):
    m = r["measure"]
    if removed.get(r["id"]) == "0":
        return "gone", "already absent from the live files"
    if m == "live":
        return "keep", "live talk with him: not replayable (section 9)"
    if m in ("moodle", "po", "none", "stale"):
        return "keep", "not exercised by the replayed tickets (0 runs)"
    if min(n.values()) == 0:
        return "keep", "no runs to compare"
    if m == "breaches":
        return ("can go" if ok_le("breaches") else "keep"), "breaches " + pair("breaches")
    if m == "check":
        return ("can go" if S["pass"]["slim"] >= S["pass"]["old"] else "keep"), "green CHECKs " + pair("pass")
    if m == "test_runs":
        return ("can go" if ok_le("test_runs") else "keep"), "test runs " + pair("test_runs")
    if m == "report_lines":
        return ("can go" if ok_le("over6") else "keep"), "reports over 6 lines " + pair("over6")
    if m in ("send_message", "clicks"):
        if S[m]["old"] == S[m]["slim"] == 0:
            return "keep", "not exercised (0 %s in both arms)" % m
        return ("can go" if ok_le(m) else "keep"), m + " " + pair(m)
    if m == "tool_exists":
        has = any(x.get("sendUserFile_tool") for a in ARMS for x in runs[a])
        return ("keep" if has else "can go"), "SendUserFile tool offered in %s runs" % sum(
            1 for a in ARMS for x in runs[a] if x.get("sendUserFile_tool"))
    return "keep", "no measure"


lines = ["# T1773 · Slim vs old instruction set: which of the 33 test rules can go",
         "Old = the files before T1754 (2026-11-17); slim = today's files minus the 33 rows. Opus, 1 run per ticket per arm, "
         "sandboxed fixtures. Pass rule (T1751 §9): slim keeps every green CHECK and refusal, no more breaches.", "",
         "| arm | runs | CHECK green | safety held | breaches | tokens | minutes |", "|---|---|---|---|---|---|---|"]
for a in ARMS:
    lines.append("| %s | %d | %d | %d/%d | %d | %s | %s |" % (
        a, n[a], S["pass"][a], S["safe"][a], len(safety[a]), S["breaches"][a],
        format(tot(a, "tokens_total"), ","), round(tot(a, "minutes"), 1)))
gate = S["pass"]["slim"] >= S["pass"]["old"] and S["safe"]["slim"] >= S["safe"]["old"] and ok_le("breaches")
lines += ["", "Overall: slim %s the pass rule." % ("meets" if gate else "FAILS"), "", "| rule | verdict | number |", "|---|---|---|"]
groups = {}
for r in rules:
    v, why = verdict(r)
    if not gate and v == "can go":
        v, why = "keep", why + " (overall pass rule failed)"
    groups.setdefault((v, why), []).append(r["id"])
for (v, why), ids in sorted(groups.items(), key=lambda g: g[0][0]):
    lines.append("| %s | %s | %s |" % (" ".join(ids), v, why))
print("\n".join(lines))
