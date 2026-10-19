#!/usr/bin/env python3
"""claims CLI: add/done/list/check/expire on a fixture board (CLAIMS_FILE), never the real one."""
import os, subprocess, sys, tempfile
from datetime import datetime, timedelta

CLI = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "claims")
REAL = os.path.expanduser("~/agents/FILE-CLAIMS.md")
fail = 0


def check(name, cond, got=""):
    global fail
    print(f'{"claims: " + name:64}' + ("OK" if cond else f"FAIL — {got}"))
    fail |= not cond


def run(*a):
    r = subprocess.run([sys.executable, CLI, *a], capture_output=True, text=True, env=ENV)
    return r.returncode, r.stdout, r.stderr


tmp = tempfile.mkdtemp()
BOARD = os.path.join(tmp, "FILE-CLAIMS.md")
ENV = dict(os.environ, CLAIMS_FILE=BOARD)
before = os.path.getmtime(REAL) if os.path.exists(REAL) else None
now = datetime.now()
d = lambda h: (now - timedelta(hours=h)).strftime("%Y-%m-%d %H:%M")
day = lambda n: (now - timedelta(days=n)).strftime("%Y-%m-%d")
with open(BOARD, "w") as f:
    f.write("# header stays\n"
            f"- OLD · a/** · {day(25)}\n"
            f"- OWNER · ~/drop/x/ · do not move · {day(7)}\n"
            f"- H30 · b · {d(30)}\n"
            f"- H50 · c · {d(50)}\n"
            f"- YDAY · e · {day(1)}\n"
            f"- NODATE · f · someday\n")

rc, out, _ = run("check")
check("check counts 6 rows, 2 stale, exits 2", rc == 2 and out.startswith("6 claims, 2 stale (OLD H50), 1 pinned"), out)
rc, out, _ = run("list")
check("list marks the owner row PIN", "PIN" in out.splitlines()[1], out)
rc, out, _ = run("expire")
check("expire without --apply only says would", rc == 0 and out.count("would drop:") == 2 and "OLD" in open(BOARD).read(), out)
rc, out, _ = run("expire", "--apply")
text = open(BOARD).read()
check("expire --apply drops the 25 d and 50 h rows", "- OLD" not in text and "- H50" not in text, text)
check("the pinned owner row stays", "- OWNER" in text, text)
check("rows under 48 h stay (30 h, yesterday's date)", "- H30" in text and "- YDAY" in text, text)
check("an undatable row stays", "- NODATE" in text, text)
check("the header line stays", text.startswith("# header stays\n"), text)

ENV["CLAIMS_STALE_H"] = "1"
rc, out, _ = run("expire")
check("CLAIMS_STALE_H=1 cannot go under the 24 h floor", "H30" in out and "YDAY" not in out, out)
del ENV["CLAIMS_STALE_H"]

rc, out, _ = run("add", "T900", "x/y.py, z/")
check("add appends a timestamped row", rc == 0 and out.startswith("- T900 · x/y.py, z/ · ") and "- T900" in open(BOARD).read(), out)
rc, _, err = run("add", "T900", "other")
check("a second add for the same ticket is refused", rc == 1 and "already holds" in err, err)
rc, out, _ = run("add", "T901", "p/", "--pin")
check("--pin rows are pinned", "· pin ·" in out, out)
rc, _, err = run("add", "T902", "x/y.py")
check("an equal path of another ticket is an overlap, exit 3", rc == 3 and "overlap: T900 x/y.py" in err and "- T902" not in open(BOARD).read(), err)
rc, _, err = run("add", "T902", "z/w.txt")
check("a path inside another ticket's dir is an overlap", rc == 3 and "overlap: T900 z" in err, err)
rc, _, err = run("add", "T902", "~/drop")
check("a parent of another ticket's path is an overlap", rc == 3 and "overlap: OWNER " + os.path.expanduser("~/drop/x") in err, err)
rc, _, err = run("add", "T902", "{q,b}/k, x/yz.py")
check("braces expand; a shared-prefix sibling is no overlap", rc == 3 and err.strip() == "overlap: H30 b", err)
rc, out, err = run("add", "T902", "x/y.py", "--force")
check("--force adds despite the overlap", rc == 0 and "overlap: T900" in err and "- T902" in open(BOARD).read(), out + err)
run("done", "T902")
rc, out, _ = run("done", "T900")
check("done releases the ticket's row", rc == 0 and "- T900" not in open(BOARD).read(), out)
rc, _, err = run("done", "T900")
check("done on a missing ticket exits 1", rc == 1 and "no row" in err, err)
rc, out, _ = run("check")
check("check is 0 when nothing is stale", rc == 0 and ", 0 stale," in out, out)
check("the real board was not touched", (os.path.getmtime(REAL) if os.path.exists(REAL) else None) == before)

print("PASS claims" if not fail else "FAIL claims")
sys.exit(fail)
