"""Run the length x seed grid against a model port, appending each trial to results.json (resumable)."""
import json
import random
import time
from pathlib import Path

from . import haystack, needles, score

QUESTION_OVERHEAD_TOKENS = 900


def _save(path: Path, trials: list) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(trials, indent=1))
    tmp.replace(path)


def calibrate(model, blocks: list[str], sample_chars: int = 80000) -> dict:
    """Measure chars per token of the filler with one tiny-answer call against a no-filler baseline."""
    base = model.ask("Reply with OK.").input_tokens
    text = "".join(haystack.build_filler(blocks, sample_chars, random.Random(0)))
    full = model.ask(f"<session>\n{text}\n</session>\nReply with OK.").input_tokens
    return {"chars_per_token": sample_chars / (full - base), "base_tokens": base, "sample_chars": sample_chars}


def mode_name(updates: int, variant: str = "control") -> str:
    """plain (0), hard (1) or stressN (N superseded values per fact), plus +variant for a non-control prompt."""
    base = "plain" if updates == 0 else "hard" if updates == 1 else f"stress{updates}"
    return base if variant == "control" else f"{base}+{variant}"


def trial(model, blocks, cal: dict, length: int, seed: int, updates: int = 0, variant: str = "control") -> dict:
    """Build one haystack, ask the model, grade the reply and return the trial record."""
    facts, join_q, join_a, _ = needles.generate(seed, updates)
    rng = random.Random(f"{seed}-{length}")
    chars = int((length - cal["base_tokens"] - QUESTION_OVERHEAD_TOKENS) * cal["chars_per_token"])
    filler = haystack.build_filler(blocks, chars, rng)
    session, depths = haystack.plant(filler, facts, haystack.slot_depths(len(facts), rng), rng, updates > 0)
    reply = model.ask(haystack.prompt(session, facts, join_q, variant))
    g = score.grade(reply.text.rsplit("</quotes>", 1)[-1], facts, join_a)
    return {"mode": mode_name(updates, variant), "variant": variant, "effort": getattr(model, "effort", None), "length": length, "seed": seed, "input_tokens": reply.input_tokens,
            "output_tokens": reply.output_tokens, "latency_s": round(reply.latency_s, 2),
            "api_s": round(reply.raw.get("duration_api_ms", 0) / 1000, 2),
            "api_calls": len(reply.raw.get("usage", {}).get("iterations", [])) or max(1, round(reply.input_tokens / length)),
            "cost_usd": reply.cost_usd,
            "facts_ok": g["facts_ok"],
            "join_ok": g["join_ok"], "parsed": g["parsed"],
            "facts": [{"key": f.key, "depth": round(d, 3), "gold": f.answer, "ok": g["per_fact"][f.key]}
                      for f, d in zip(facts, depths)],
            "join_gold": join_a, "reply": g["reply"], "raw_text": reply.text,
            "at": time.strftime("%Y-%m-%dT%H:%M:%S")}


def run(model, blocks, cal: dict, lengths: list[int], seeds: list[int], out: Path, updates: int = 0, log=print,
        variant: str = "control") -> list:
    """Run every missing (length, seed) trial, one retry on error, saving after each."""
    trials = json.loads(out.read_text()) if out.exists() else []
    mode = mode_name(updates, variant)
    done = {(t.get("mode", "plain"), t["length"], t["seed"]) for t in trials}
    for length in lengths:
        for seed in seeds:
            if (mode, length, seed) in done:
                continue
            for attempt in (1, 2):
                try:
                    t = trial(model, blocks, cal, length, seed, updates, variant)
                    break
                except Exception as e:  # noqa: BLE001 - a failed call is retried once, then recorded
                    log(f"{length}/{seed} attempt {attempt} failed: {e}")
                    t = {"length": length, "seed": seed, "error": str(e)[:400]}
            if "error" not in t:
                trials.append(t)
                _save(out, trials)
            log(f"{mode} {length}/{seed}: " + (f"facts {t['facts_ok']}/8 join {int(t['join_ok'])} "
                                        f"in={t['input_tokens']} {t['latency_s']}s" if "error" not in t else "ERROR"))
    return trials
