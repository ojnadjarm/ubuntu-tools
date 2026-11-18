#!/usr/bin/env python3
"""Build the two instruction arms (old = before T1754, slim = now minus the 33 test rows) as files in the scratch dir."""
import csv, json, os, re, shutil, subprocess, sys

H = os.path.expanduser("~")
HERE = os.path.dirname(os.path.realpath(__file__))
OUT = os.environ.get("T1773_OUT", os.path.join(H, "agent-work", "research", "2026-11-18", "T1773"))
SCR = os.environ.get("T1773_SCRATCH", os.path.join(H, ".cache", "t1773"))
OLD_AGENTS, OLD_MEMORY = "0d9a757", "b55e214"
AGENTS_FILES = ["AGENTS.md", "ORCHESTRATOR.md", "AGENT-PREAMBLE.md", "KB/toolbox.md", "KB/quirks.md",
                "KB/brief.template.md", "KB/guides/INDEX.md", "KB/guides/brief-check.md",
                "KB/guides/decisions-ledger.md", "KB/guides/file-claims.md", "KB/guides/test-changes.md",
                "bin/harness", "adapters/claude/hooks/spawn-context", "adapters/claude/hooks/agent-spawn-gate",
                "adapters/claude/hooks/send-message-guard", "adapters/claude/hooks/memory-recall",
                "adapters/claude/memory-carrier", "po-template/BRIEF.tmpl.md", "po-template/MANAGER.tmpl.md",
                "po-template/COMMON.md", "bench/TRIAL-PREAMBLE.md"]
CLAUDE_OLD = {"CLAUDE.md": "CLAUDE.md.bak-20261117", "settings.json": "settings.json.bak-T1754-C",
              "skills/i-have-adhd/SKILL.md": "skills/i-have-adhd/SKILL.md.bak-T1754"}
for f in ("moodle-guidelines.md", "moodle-tips.md", "moodle-coding-style.md", "moodleapp-instructions.md"):
    CLAUDE_OLD[f] = f + ".bak-T1754"


def git_show(repo, rev, path):
    p = subprocess.run(["git", "-C", repo, "show", "%s:%s" % (rev, path)], capture_output=True)
    return p.stdout if p.returncode == 0 else None


def put(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(data)


def build(arm):
    a = os.path.join(SCR, "arms", arm)
    shutil.rmtree(a, ignore_errors=True)
    rev = OLD_AGENTS if arm == "old" else "HEAD"
    mem = OLD_MEMORY if arm == "old" else subprocess.check_output(
        ["git", "-C", os.path.join(H, "memory"), "rev-parse", "--short", "HEAD"], text=True).strip()
    absent = []
    for f in AGENTS_FILES:
        data = git_show(os.path.join(H, "agents"), rev, f)
        if data is None:
            absent.append(f)
        else:
            put(os.path.join(a, "agents", f), data)
    for f, bak in CLAUDE_OLD.items():
        src = os.path.join(H, ".claude", bak if arm == "old" else f)
        put(os.path.join(a, "claude", f), open(src, "rb").read())
    put(os.path.join(a, "agents.absent"), "".join(x + "\n" for x in absent).encode())
    put(os.path.join(a, "memory.commit"), (mem + "\n").encode())
    if arm == "slim":
        drop(a, mem)
    return a


def drop(a, mem):
    """Delete each of the 33 rows from the slim arm's copies; drop-report.tsv says which were found."""
    rows = list(csv.DictReader(open(os.path.join(OUT, "drop33.tsv")), delimiter="\t", quoting=csv.QUOTE_NONE))
    out = ["id\tfile\tremoved"]
    for r in rows:
        f = os.path.join(a, r["file"])
        if not os.path.exists(f) and r["file"].startswith("memory/"):
            data = git_show(os.path.join(H, "memory"), mem, r["file"][len("memory/"):])
            if data is not None:
                put(f, data)
        n = 0
        if os.path.exists(f):
            t = open(f).read()
            t, n = re.subn(r["regex"], "", t, count=1, flags=re.M)
            open(f, "w").write(t)
        out.append("%s\t%s\t%d" % (r["id"], r["file"], n))
    s = os.path.join(a, "claude", "settings.json")
    json.load(open(s))
    open(os.path.join(a, "drop-report.tsv"), "w").write("\n".join(out) + "\n")


if __name__ == "__main__":
    for arm in sys.argv[1:] or ["old", "slim"]:
        print("built", build(arm))
