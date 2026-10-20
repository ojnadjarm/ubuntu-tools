---
name: context-rot
description: Measure a Claude model's context-rot curve. Use for "context rot", "long-context test", "needle test", "where does quality drop", "compaction limit", a new model. Plants facts in agent filler (32k..800k), asks headless `claude -p`, scores recall, latency, tokens; table + chart.
allowed-tools: Bash(ctxrot:*), Bash(~/agents/bin/ctxrot:*)
---

Triggers: autoCompactWindow, 8 facts, 2-fact join, tool-less, responsive chart.

# context-rot — our own long-context curve (T129)

```bash
OUT=~/agent-work/research/$(date +%F)/TNNN
ctxrot corpus $OUT                                   # snapshot filler from ~/agents KB/briefs/research/bin + skills (secret filter)
ctxrot run $OUT --lengths 32000,128000,200000,300000 # plain test, seeds 1,2,3; resumable, appends to results.json
ctxrot run $OUT --lengths 32000,128000,200000,300000 --hard   # superseded values + twin entities, facts buried in tool output
ctxrot run $OUT --lengths 32000,500000,970000 --updates 6   # stress6: six superseded values per fact; 970k = largest that fits 1M
ctxrot report $OUT                                   # results.md auto block + page/ (index.html from page.html, data.json)
mkdir -p "$OUT/drop" && cp -rT "$OUT/page" "$OUT/drop/context-rot" && ~/agents/bin/drop-link "$OUT/drop/context-rot" tNNN   # folder name = link name
python3 ~/.claude/skills/context-rot/selftest.py $OUT/corpus.jsonl   # offline oracle: plumbing, token targeting, spread
```

- Flags: `--model` (default `claude-opus-5-5[1m]`), `--effort` (default `medium`, the global setting), `--seeds`, `--variant control|rest|quote|pad|checkpoint` (T144/T145 prompt arms; mode `stressN+variant`).
- Isolation: every call is `claude -p --tools "" --strict-mcp-config --setting-sources "" --system-prompt …
  --no-session-persistence` from a temp dir; ~441 tokens of overhead, no tools, no CLAUDE.md, no hooks.
- Token targeting uses one calibration call (`calibration.json`, chars per token of this corpus); approximate: ±6 % at 32k, ±3.5 % at 128k+ (T129).
- Hand-written text in `results.md` (outside the `ctxrot:auto` markers) and edits to `page/index.html` survive a rerun;
  set the proposed limit with `<body data-proposed="NNN000">`.
- `ctxrot`/`drop-link` live in `~/agents/bin`, which may not be on PATH: use full paths. A changed variant keeps its own mode name.
- Pitfalls and numbers: `~/agents/KB/guides/context-rot-test.md`.
