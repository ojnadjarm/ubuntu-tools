"""Aggregate trials into the auto section of results.md and page/data.json."""
import json
import shutil
import statistics as st
from pathlib import Path

START, END = "<!-- ctxrot:auto:start -->", "<!-- ctxrot:auto:end -->"


def aggregate(trials: list) -> dict:
    """Return per-(mode, length) and per-depth-quartile summaries."""
    keys = sorted({(t.get("mode", "plain"), t["length"]) for t in trials}, key=lambda k: (k[0] != "plain", k))
    rows = []
    for mode, L in keys:
        ts = [t for t in trials if t.get("mode", "plain") == mode and t["length"] == L]
        single = [t for t in ts if t["input_tokens"] < 1.5 * L] or ts
        rows.append({"mode": mode, "length": L, "n": len(ts),
                     "input_tokens": round(st.mean(t["input_tokens"] for t in single)),
                     "recall": round(100 * st.mean(t["facts_ok"] for t in ts) / 8, 1),
                     "recall_min": round(100 * min(t["facts_ok"] for t in ts) / 8, 1),
                     "join": round(100 * st.mean(float(t["join_ok"]) for t in ts), 1),
                     "score": round(100 * st.mean((t["facts_ok"] + int(t["join_ok"])) / 9 for t in ts), 1),
                     "latency_s": round(st.mean(t["latency_s"] for t in ts), 1),
                     "minutes": round(sum(t["latency_s"] for t in ts) / 60, 1),
                     "cost_usd": round(sum(t.get("cost_usd", 0) for t in ts), 2),
                     "trials": [{"seed": t["seed"], "facts_ok": t["facts_ok"], "join_ok": t["join_ok"],
                                 "input_tokens": t["input_tokens"], "latency_s": t["latency_s"]} for t in ts]})
    depth = []
    for mode, L in keys:
        qs = [[], [], [], []]
        for t in trials:
            if t.get("mode", "plain") == mode and t["length"] == L:
                for f in t["facts"]:
                    qs[min(3, int(f["depth"] * 4))].append(f["ok"])
        depth.append({"mode": mode, "length": L, "quartiles": [round(100 * st.mean(q), 1) if q else None for q in qs]})
    return {"lengths": rows, "depth": depth}


def _md(agg: dict, model: str, effort: str) -> str:
    out = [f"Model `{model}`, effort `{effort}`. Score = (facts + join) / 9.", "",
           "| mode | target | input tokens | facts recall | worst trial | join | score | latency | minutes | cost |",
           "|---|---|---|---|---|---|---|---|---|---|"]
    for r in agg["lengths"]:
        out.append(f"| {r['mode']} | {r['length'] // 1000}k | {r['input_tokens']:,} | {r['recall']}% | {r['recall_min']}% | "
                   f"{r['join']}% | {r['score']}% | {r['latency_s']} s | {r['minutes']} | ${r['cost_usd']} |")
    out += ["", "Facts recall by depth quartile (0-25 / 25-50 / 50-75 / 75-100 % of the session):", "",
            "| mode | target | Q1 | Q2 | Q3 | Q4 |", "|---|---|---|---|---|---|"]
    for d in agg["depth"]:
        out.append(f"| {d['mode']} | {d['length'] // 1000}k | " + " | ".join(f"{q}%" if q is not None else "-"
                                                          for q in d["quartiles"]) + " |")
    return "\n".join(out)


def write(out: Path, trials: list, model: str, effort: str) -> dict:
    """Refresh the auto block of results.md and page/data.json; hand-written text and page edits are kept."""
    agg = aggregate(trials)
    md = out / "results.md"
    body = f"{START}\n{_md(agg, model, effort)}\n{END}"
    text = md.read_text() if md.exists() else f"# Context-rot curve\n\n{START}\n{END}\n"
    md.write_text(text.split(START)[0] + body + text.split(END, 1)[1])
    (out / "page").mkdir(exist_ok=True)
    if not (out / "page" / "index.html").exists():
        shutil.copy(Path(__file__).parent.parent / "page.html", out / "page" / "index.html")
    (out / "page" / "data.json").write_text(json.dumps({"model": model, "effort": effort, **agg}, indent=1))
    print(_md(agg, model, effort))
    return agg
