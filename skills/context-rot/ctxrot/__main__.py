"""ctxrot CLI: corpus | run | report — a context-rot curve for one Claude model."""
import argparse
import json
from pathlib import Path

from . import corpus, haystack, report, runner
from .model import ClaudeCLI


def main() -> None:
    ap = argparse.ArgumentParser(prog="ctxrot", description=__doc__)
    ap.add_argument("cmd", choices=["corpus", "run", "report"])
    ap.add_argument("out", type=Path, help="results folder (corpus.jsonl, calibration.json, results.json live here)")
    ap.add_argument("--lengths", default="32000,128000,200000,300000")
    ap.add_argument("--seeds", default="1,2,3")
    ap.add_argument("--model", default="claude-opus-5-5[1m]")
    ap.add_argument("--effort", default="medium")
    ap.add_argument("--hard", action="store_true", help="one superseded value and a twin entity per fact; facts buried in tool output")
    ap.add_argument("--updates", type=int, default=0, help="N superseded values per fact (implies --hard; mode stressN)")
    ap.add_argument("--variant", default="control", choices=list(haystack.VARIANTS),
                    help="prompt variant: rest line, quote-first, 1k blank lines or a restate checkpoint (mode +variant)")
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    cpath, calpath, rpath = a.out / "corpus.jsonl", a.out / "calibration.json", a.out / "results.json"
    if a.cmd == "corpus":
        print(json.dumps(corpus.build(cpath)))
    elif a.cmd == "run":
        if not cpath.exists():
            print(json.dumps(corpus.build(cpath)))
        blocks = corpus.load(cpath)
        model = ClaudeCLI(a.model, a.effort, haystack.SYSTEM)
        if not calpath.exists():
            calpath.write_text(json.dumps(runner.calibrate(model, blocks)))
        cal = json.loads(calpath.read_text())
        print(f"calibration: {cal}", flush=True)
        runner.run(model, blocks, cal, [int(x) for x in a.lengths.split(",")], [int(x) for x in a.seeds.split(",")],
                   rpath, a.updates or int(a.hard), log=lambda s: print(s, flush=True), variant=a.variant)
    else:
        report.write(a.out, json.loads(rpath.read_text()), a.model, a.effort)


if __name__ == "__main__":
    main()
