# Context-rot test: where a Claude model's long-context recall drops, and the compaction limit

Ticket: T129, T142, T144 · Last verified: 2026-09-29 by a 28-trial run (T144: 41 calls) (`claude-opus-5-5[1m]`, 32k-970k) plus `selftest.py`

## When to use
Choosing `autoCompactWindow`, checking a new model or effort level for long-context recall, or answering "where does
quality drop". Not for general benchmark scores (use public leaderboards) or for multi-step reasoning quality.

## The path we took
- Exists: Chroma `context-rot` (MIT, haystack build + needle at depth), NVIDIA RULER (multi-key NIAH), OpenAI MRCR.
  Chosen: Chroma's build/insert logic plus RULER's multi-needle idea over our own agent-session filler; neither ships
  session-like filler or a join question. No API key here, so the model port is headless `claude -p`.
- Modules in `~/.claude/skills/context-rot/ctxrot/`: `corpus` (filler snapshot), `needles` (seeded 8 facts + join; hard =
  superseded value + `-legacy` twin; `--updates N` = N superseded values), `haystack` (target size, 8 spread depths,
  hard buries facts mid-block in tool output), `model` (the `ask()` port), `score`, `runner` (resumable grid), `report`.

## Exact commands
```bash
OUT=~/agent-work/research/$(date +%F)/TNNN
python3 ~/.claude/skills/context-rot/selftest.py ~/agent-work/research/2026-09-27/T129/corpus.jsonl   # offline oracle, 0.1 s
~/agents/bin/ctxrot run $OUT --lengths 32000,128000,200000,300000            # plain, seeds 1,2,3 (builds corpus + calibration)
~/agents/bin/ctxrot run $OUT --lengths 32000,128000,200000,300000 --hard
~/agents/bin/ctxrot run $OUT --lengths 32000,128000,300000,500000,800000,970000 --updates 6
~/agents/bin/ctxrot report $OUT                                              # results.md auto block + page/data.json
mkdir -p "$OUT/drop" && cp -rT "$OUT/page" "$OUT/drop/context-rot" && ~/agents/bin/drop-link "$OUT/drop/context-rot" tNNN
```

## Pitfalls (measured)
- `~/agents/bin` may not be on PATH in agent shells: call `~/agents/bin/ctxrot` and `~/agents/bin/drop-link` by full path.
- 1M is not a usable target: token targeting overshoots by about +1.5 % (800k → 810-814k), so 970k (→ 978-985k) is the
  largest that fits the 1M window.
- A trial can take 2 API calls and double its input count (T129: 800k hard seed 2 = 1.63M tokens); the row records
  `api_calls` (the CLI sends no `usage.iterations`, so it is round(input / target); rows before 2026-10-03 always say 1:
  19 of 355 T129-T146 rows are > 2x). `report` leaves rows ≥ 1.5x target out of the input-tokens mean.
- The runner resumes by (mode, length, seed); changing `haystack.py` does not invalidate old rows. T129's first stress6
  ran on prefix-bury code: its 800k joins were 1/3 while the same seeds on current code were 3/3. Keep a changed variant
  under its own mode name (`stress6-prefix` in T129) instead of mixing it into the new one.
- Opus 5.5 saturates this test: 63/63 perfect at 32k-970k on current code; the only misses (4 of 78 trials) were in the
  old variant at 32k and 800k. A flat curve means "no retrieval drop", not "no reasoning drop".
- T144 prompt arms (`--variant rest|quote|pad`, stress16 at effort low, the first condition under 85 %: control 74 %): rest +5.5,
  blank lines +11, quote-first +15 points, all within noise (1 SE ≈ 9.5); quote-first at 800k trips a `reasoning_extraction` classifier (6/7 calls).
- T145: 6 parallel 500k/800k runs hit the plan's session limit (429, "resets 10:10pm") after 10 calls on a day that had
  already spent ~55; a 429 is not a model call, so keep it out of a call cap. Quote-first tripped the classifier at 500k too (1 of 2).
- T146 Sonnet 5.5 `[1m]` (window 1M) at effort medium, stress16: control 76 % at 500k and 72 % at 800k, 13 points under Opus 5.5 low on the same seeds
  ([-21, -5]). Plain 128k/300k are 100 %. Quote +2.2 and checkpoint +2.1 are within noise. The classifier blocks quote on 13 of 23 seeds (7/8 at 800k).
  A driver bug: a bare `"429" in err` matches `duration_ms`, so match `api_error_status":429` instead.
- Latency and cost, per call: plain 3.3 s at 32k, 6.1 s at 300k, 14.4 s at 970k; stress6 up to 66 s; about $0.8 per 100k
  input tokens uncached. 28 trials took 10 min wall and $130 list price.
- Node for the chart validator and headless shots is not on PATH: `~/.nvm/versions/node/v24.20.0/bin/node`; playwright-core
  lives in `.../lib/node_modules/@playwright/mcp/node_modules/playwright-core`.

## Links
- Code: `~/.claude/skills/context-rot/` (skill `/context-rot`), CLI `~/agents/bin/ctxrot`, page template `page.html`
- Tests: `python3 ~/.claude/skills/context-rot/selftest.py <corpus.jsonl>`
- Design / results: `~/agent-work/research/2026-09-27/T129/results.md`, page `https://$HARNESS_TAILNET_FQDN:8470/t129/context-rot/` (deleted T271)
