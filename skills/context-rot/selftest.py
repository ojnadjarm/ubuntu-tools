"""Offline selftest: a fake model that reads the planted facts must score 8/8 + join at every length."""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import random  # noqa: E402
from ctxrot import corpus, haystack, needles, report, runner  # noqa: E402
from ctxrot.model import Reply  # noqa: E402


class Oracle:
    """Answers from the planted facts in the prompt, the way a perfect reader would."""

    def ask(self, prompt):
        found = [(s, u) for u in (0, 1, 3) for s in range(1, 50)
                 if all(f.text in prompt for f in needles.generate(s, u)[0])
                 and all(t in prompt for f in needles.generate(s, u)[0] for _, t in f.distractors)]
        seed, hard = found[-1] if found else (0, 0)
        ans = {}
        if seed:
            facts, _, room, _ = needles.generate(seed, hard)
            ans = {f"q{i + 1}": f.answer for i, f in enumerate(facts)} | {"join": room}
        return Reply(str(ans).replace("'", '"'), 0.01, len(prompt) // 4, 10, 0.0, {})


class Billed2x(Oracle):
    """Bills the prompt twice with no usage.iterations, as the CLI does on a doubled call."""

    def ask(self, prompt):
        r = super().ask(prompt)
        return Reply(r.text, r.latency_s, 2 * r.input_tokens, r.output_tokens, r.cost_usd, {"usage": {}})


blocks = corpus.load(Path(sys.argv[1]))
with tempfile.TemporaryDirectory() as d:
    cal = runner.calibrate(Oracle(), blocks)
    trials = runner.run(Oracle(), blocks, cal, [32000, 128000], [1, 2], Path(d) / "results.json", log=lambda s: None)
    trials = runner.run(Oracle(), blocks, cal, [32000], [1], Path(d) / "results.json", 1, log=lambda s: None)
    trials = runner.run(Oracle(), blocks, cal, [32000], [1], Path(d) / "results.json", 3, log=lambda s: None)
    for v in ("rest", "quote", "pad", "checkpoint"):
        trials = runner.run(Oracle(), blocks, cal, [32000], [1], Path(d) / "results.json", 3, lambda s: None, v)
    agg = report.write(Path(d), trials, "oracle", "-")
    assert all(r["score"] == 100.0 for r in agg["lengths"]), agg
    assert all(abs(t["input_tokens"] - t["length"]) / t["length"] < 0.05 for t in trials), trials
    assert all(abs(a["depth"] - b["depth"]) > 0.05 for t in trials for a, b in zip(t["facts"], t["facts"][1:]))
    doubled = runner.trial(Billed2x(), blocks, cal, 32000, 1)
    assert doubled["api_calls"] == 2, doubled["api_calls"]
    assert report.aggregate(trials + [doubled])["lengths"][0]["input_tokens"] == agg["lengths"][0]["input_tokens"]
for seed in (1, 2, 3):
    facts = needles.generate(seed, 6)[0]
    rng = random.Random(seed)
    text, _ = haystack.plant(haystack.build_filler(blocks, 80000, rng), facts, haystack.slot_depths(8, rng), rng, True)
    assert all(text.find(t) < text.find(f.text) for f in facts for w, t in f.distractors if w == "before"), seed
print("selftest ok")
