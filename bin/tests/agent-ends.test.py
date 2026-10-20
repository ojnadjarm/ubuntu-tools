#!/usr/bin/env python3
"""lib/agent_ends.py on fixture transcripts: note states, truncated lines, repeats, TaskStop, launches, incremental scans, journals."""
import os, shutil, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "lib"))
sys.path.insert(0, os.path.join(HERE, "lib"))
import agent_ends as ae  # noqa: E402
from budget import budget  # noqa: E402

FX = os.path.join(HERE, "fixtures", "agent-ends")
T0 = ae.iso_s("2026-10-19T10:00:00Z")
bad = 0
t_start = time.monotonic()


def check(name, cond):
    global bad
    print(("PASS " if cond else "FAIL ") + name)
    bad += not cond


def states(name):
    return {k: v[1] for k, v in ae.scan(os.path.join(FX, name), ae.memo())[1].items()}


check("completed/failed/killed/stopped notes map to done/error/stale/stale",
      states("notes.jsonl") == {"a1": "done", "a2": "error", "a3": "stale", "a4": "stale"})
check("a truncated JSONL line is skipped", "a5" not in states("notes.jsonl"))
check("no notes: empty state", ae.scan(os.path.join(FX, "plain.jsonl"), ae.memo())[1:] == [{}, {}, {}])
m = ae.scan(os.path.join(FX, "twice.jsonl"), ae.memo())
check("a task id seen twice keeps the latest status", m[1]["b1"] == (T0 + 300, "error"))
check("an older note later in the file does not override a newer one", m[1]["b2"] == (T0 + 300, "error"))

m = ae.scan(os.path.join(FX, "stops.jsonl"), ae.memo())
check("TaskStop with no note marks the task stale", m[1]["c1"] == (T0 + 120, "stale"))
check("TaskStop after a completed note keeps done", m[1]["c2"] == (T0 + 180, "done"))
check("a workflow launch maps run id and task id both ways",
      m[2] == {"wf_57ef": ("wcq1", "cleanup")} and m[3] == {"wcq1": "wf_57ef"})
check("a missing transcript leaves the state as is", ae.scan(os.path.join(FX, "nope.jsonl"), ae.memo()) == ae.memo())

tmp = tempfile.mkdtemp(prefix="agent-ends-test-")
try:
    tp = os.path.join(tmp, "t.jsonl")
    shutil.copy(os.path.join(FX, "partial.jsonl"), tp)
    first = open(tp, "rb").read().index(b"\n") + 1
    m = ae.scan(tp, ae.memo())
    check("an unfinished last line is not read yet", m[0] == first and set(m[1]) == {"d1"})
    open(tp, "a").write("\n")
    ae.scan(tp, m)
    check("the next scan reads the line once it ends", m[0] == os.path.getsize(tp) and m[1]["d2"][1] == "error")
    shutil.copy(os.path.join(FX, "plain.jsonl"), tp)
    ae.scan(tp, m)
    check("a shrunk transcript resets the state", m[1] == {} and m[0] == os.path.getsize(tp))
finally:
    shutil.rmtree(tmp)

wf = os.path.join(FX, "wf")
done, starts = ae.journal(wf)
check("journal: result is done, failed is error, a bad row is skipped", done == {"e1": "done", "e2": "error"})
check("journal: started rows in order", starts == [("lane A", "e1"), ("lane B", "e2"), ("lane A", "e3")])
check("journal: no folder gives nothing", ae.journal(os.path.join(FX, "nope")) == ({}, []))
began = lambda a: ae.began(os.path.join(wf, f"agent-{a}.jsonl"))
check("began: first line's timestamp, 0 when missing", began("e3") == T0 + 3600 and began("e9") == 0)
check("resumed: a later start with the same label after the silence",
      ae.resumed("e1", starts, began, T0 + 3600) and not ae.resumed("e1", starts, began, T0 + 3601))
check("resumed: no later start with the label", not ae.resumed("e2", starts, began, 0))
check("iso_s: junk is 0", ae.iso_s("not a time") == 0 and ae.iso_s(None) == 0)

wall = time.monotonic() - t_start
check(f"wall {wall:.2f} s <= {budget(2):.2f} s", wall <= budget(2))
sys.exit(bad)
