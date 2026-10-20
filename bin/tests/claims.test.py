#!/usr/bin/env python3
"""claims CLI: add/done/list/check/expire/diff on a fixture board (CLAIMS_FILE) and snapshot dir (CLAIMS_SNAP), never the real ones."""
import os, subprocess, sys, tempfile, time
from datetime import datetime, timedelta

CLI = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "claims")
REAL = os.path.expanduser("~/agents/FILE-CLAIMS.md")
fail = 0


def check(name, cond, got=""):
    global fail
    print(f'{"claims: " + name:64}' + ("OK" if cond else f"FAIL — {got}"))
    fail |= not cond


def run(*a, cwd=None):
    r = subprocess.run([sys.executable, CLI, *a], capture_output=True, text=True, env=ENV, cwd=cwd)
    return r.returncode, r.stdout, r.stderr


tmp = tempfile.mkdtemp()
BOARD = os.path.join(tmp, "FILE-CLAIMS.md")
SNAP = os.path.join(tmp, "snap")
ENV = dict(os.environ, CLAIMS_FILE=BOARD, CLAIMS_SNAP=SNAP)
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
rc, out, _ = run("add", "T900", "other", "x/y.py", "./z")
row = [l for l in open(BOARD).read().splitlines() if l.startswith("- T900 ")]
check("a second add appends new paths to the row, deduped", rc == 0 and out.splitlines()[0] == "T900: +1 paths" and len(row) == 1 and row[0].startswith("- T900 · x/y.py, z/, other · "), out + str(row))
rc, out, _ = run("add", "T900", "z/")
check("an add of held paths only is +0", rc == 0 and out.splitlines()[0] == "T900: +0 paths", out)
rc, _, err = run("add", "T900", "b")
check("an append still overlap-checks other tickets", rc == 3 and err.strip() == "overlap: H30 b" and "other, b" not in open(BOARD).read(), err)
rc, out, _ = run("add", "T901", "p/", "--pin")
check("--pin rows are pinned", "· pin ·" in out, out)
rc, out, _ = run("add", "T901", "p2/")
check("an append keeps the pin and since fields", rc == 0 and "- T901 · p/, p2/ · pin · " in open(BOARD).read(), out)
rc, out, _ = run("add", "T905", "a1", "b1", "./b1", "b1/")
rc, out, _ = run("add", "T905", "c1", "./c1", "c1/", "a1/k", "a1")
row = [l for l in open(BOARD).read().splitlines() if l.startswith("- T905 ")]
check("an append dedupes inside the batch and under held dirs", rc == 0 and out.splitlines()[0] == "T905: +1 paths" and row[0].startswith("- T905 · a1 b1 ./b1 b1/, c1 · "), out + str(row))
rc, out, _ = run("add", "T905", "d1", "--pin")
check("--pin on an append pins the row", rc == 0 and "pinned" in out and "- T905 · a1 b1 ./b1 b1/, c1, d1 · pin · " in open(BOARD).read(), out)
run("done", "T905")
with open(BOARD, "a") as f:
    f.write(f"- T906 · s1 · {d(50)}\n")
rc, out, _ = run("add", "T906", "s2")
row = [l for l in open(BOARD).read().splitlines() if l.startswith("- T906 ")]
check("an append to a stale row refreshes its since", rc == 0 and "since refreshed" in out and row[0].startswith("- T906 · s1, s2 · ") and row[0][-16:] > d(1), out + str(row))
run("done", "T906")
with open(BOARD, "a") as f:
    f.write(f"- T907 · b · {d(50)}\n")
rc, _, err = run("add", "T907", "s3")
check("a stale row's old paths are overlap-checked on revival", rc == 3 and err.strip() == "overlap: H30 b", err)
run("done", "T907")
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
rc, out, _ = run("add", "T903", "m/a.txt", "m/b.txt", "--pin")
check("add takes several path args as one row", rc == 0 and out.startswith("- T903 · m/a.txt m/b.txt · pin · "), out)
rc, _, err = run("add", "T904", "m/b.txt")
check("each separate path arg is overlap-checked", rc == 3 and "overlap: T903 m/b.txt" in err, err)
rc, out, _ = run("release", "T903")
check("release is an alias of done", rc == 0 and out.strip() == "released T903" and "- T903" not in open(BOARD).read(), out)
rc, out, _ = run("check", "z/w.txt", "free/one", "x")
check("check with paths reports each path, exit 1 when held", rc == 1 and out.splitlines() == ["held: z/w.txt by T900", "free: free/one", "held: x by T900"], out)
rc, out, _ = run("check", "free/one", "free/two")
check("check with only free paths exits 0", rc == 0 and out.splitlines() == ["free: free/one", "free: free/two"], out)
rc, out, _ = run("-h")
check("-h epilog shows one add and one check example", out.count("claims add T42") == 1 and out.count("claims check ") == 1, out)
rc, out, _ = run("add", "-h")
check("add -h shows one example line", out.count("example: claims add") == 1, out)
rc, out, _ = run("done", "T900")
check("done releases the ticket's row", rc == 0 and "- T900" not in open(BOARD).read(), out)
rc, _, err = run("done", "T900")
check("done on a missing ticket exits 1", rc == 1 and "no row" in err, err)
rc, out, _ = run("check")
check("check is 0 when nothing is stale", rc == 0 and ", 0 stale," in out, out)
W = os.path.join(tmp, "work")
os.makedirs(os.path.join(W, "d", "secrets"))
for name, text in (("f.txt", "one\ntwo\n"), ("d/a.txt", "a\n"), ("d/secrets/key", "TOKEN\n")):
    open(os.path.join(W, name), "w").write(text)
rc, out, _ = run("add", "T910", os.path.join(W, "f.txt"), os.path.join(W, "new.txt"), os.path.join(W, "d"))
held = [l.split("\t")[1] for l in open(os.path.join(SNAP, "T910", "manifest.tsv")).read().splitlines()]
check("add snapshots a file and a dir's files", rc == 0 and "snapshot: +2 files" in out, out)
check("secrets/ under a claimed dir is never copied", not any("secrets" in h for h in held) and not os.path.exists(os.path.join(SNAP, "T910", "files", W.lstrip("/"), "d", "secrets")), str(held))
rc, out, _ = run("diff", "T910")
check("diff with no change prints untouched", rc == 0 and out.strip() == "untouched", out)
open(os.path.join(W, "f.txt"), "w").write("one\nTWO\n")
open(os.path.join(W, "new.txt"), "w").write("fresh\n")
open(os.path.join(W, "d", "b.txt"), "w").write("b\n")
rc, out, _ = run("diff", "T910")
check("an edit shows as a unified diff", "-two\n+TWO\n" in out and "--- a" + os.path.join(W, "f.txt") in out, out)
check("a new file diffs against /dev/null", out.count("--- /dev/null") == 2 and "+fresh\n" in out and "+b\n" in out, out)
check("unchanged files are not in the diff", "a.txt" not in out, out)
run("done", "T910")
rc, out, _ = run("add", "T910", os.path.join(W, "f.txt"), os.path.join(W, "d", "b.txt"))
rc, out, _ = run("diff", "T910", "--stat")
check("a re-add after done keeps the first baseline", rc == 0 and out.splitlines()[-1] == "3 files changed, +3 -1", out)
rc, out, _ = run("done", "T910")
rc, out, _ = run("diff", "T910")
check("diff still works after done", rc == 0 and "+TWO" in out and os.path.exists(os.path.join(SNAP, "T910", "done")), out)
big = os.path.join(W, "big.bin")
open(big, "wb").write(b"x" * ((1 << 20) + 1))
rc, out, err = run("add", "T911", big)
check("a file over 1 MB is skipped with a cap message", rc == 0 and "snapshot skipped %s (> 1 MB)" % big in err and "+0 files" in out, out + err)
run("done", "T911")
rc, _, err = run("diff", "T999")
check("diff of an unknown ticket exits 1", rc == 1 and "no snapshot for T999" in err, err)
old_t = time.time() - 8 * 86400
os.utime(os.path.join(SNAP, "T910", "done"), (old_t, old_t))
run("add", "T912", os.path.join(W, "f.txt"))
check("a snapshot released > 7 days ago is pruned on the next add", not os.path.exists(os.path.join(SNAP, "T910")) and os.path.isdir(os.path.join(SNAP, "T911")), str(os.listdir(SNAP)))
run("done", "T912")
os.makedirs(os.path.join(tmp, "rel"))
open(os.path.join(tmp, "rel", "x.txt"), "w").write("old\n")
rc, out, err = run("add", "T913", "rel/x.txt, rel/gone.txt", cwd=W)
open(os.path.join(tmp, "rel", "x.txt"), "w").write("new\n")
rc, out, _ = run("diff", "T913", "--stat", cwd=W)
check("a relative path resolves under the board's dir, not the cwd", rc == 0 and out.splitlines() == [os.path.join(tmp, "rel", "x.txt") + " | +1 -1", "1 file changed, +1 -1"], out)
check("an absent relative path warns where it was looked for", "claims: %s is absent; relative paths are under %s" % (os.path.join(tmp, "rel", "gone.txt"), tmp) in err, err)
run("done", "T913")
if os.geteuid():
    os.makedirs(os.path.join(W, "locked"))
    for name in ("a.txt", "z.txt"):
        open(os.path.join(W, "locked", name), "w").write(name + "\n")
    os.chmod(os.path.join(W, "locked", "a.txt"), 0)
    rc, out, err = run("add", "T914", os.path.join(W, "locked"))
    check("an unreadable file is skipped, not a crash after the board write", rc == 0 and "snapshot skipped %s (Permission denied)" % os.path.join(W, "locked", "a.txt") in err and "+1 files" in out, out + err)
    rc, out, _ = run("diff", "T914")
    check("diff after an unreadable file names it and still diffs", rc == 0 and out.splitlines() == ["skipped at claim: " + os.path.join(W, "locked", "a.txt"), "untouched"], out)
    os.chmod(os.path.join(W, "locked", "a.txt"), 0o600)
    run("done", "T914")
with open(BOARD, "a") as f:
    f.write(f"- T915 · {os.path.join(W, 'f.txt')} · {d(1)}\n")
run("add", "T915", os.path.join(W, "new.txt"))
rc, out, _ = run("diff", "T915", "--stat")
check("diff names claimed paths with no baseline", rc == 0 and out.splitlines() == ["no baseline: %s (claimed before its snapshot; not in this diff)" % os.path.join(W, "f.txt"), "untouched"], out)
run("done", "T915")
real = open(REAL).read() if os.path.exists(REAL) else ""
check("no fixture ticket reached the real board", not any("- %s ·" % t in real for t in ("T900", "T901", "T902", "T903", "T904", "T910", "T911", "T912", "T913", "T914", "T915", "H30", "NODATE")))
check("no fixture snapshot reached the real snapshot dir", not any(os.path.exists(os.path.expanduser("~/agents/state/claims-snap/" + t)) for t in ("T900", "T910", "T911", "T912", "T913", "T914", "T915")))

print("PASS claims" if not fail else "FAIL claims")
sys.exit(fail)
