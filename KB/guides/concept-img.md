# Generate AI concept art (character sheets) through OpenRouter under a hard dollar cap

Ticket: T1035 · Last verified: 2026-10-21 by bin/tests/concept-img.test.sh (mock) and 9 real calls

## When to use
2D concept sheets (turnaround, callouts, mood) where AI images are allowed. Not for final asset pixels or textures
(char3d builds those by code), not for image-to-3D.

## The path we took
No fleet image CLI existed. `concept-img` calls OpenRouter's dedicated Image API (`POST /api/v1/images`, base64 PNG in
`data[0].b64_json`, `usage.cost`), not chat completions. Before each call it reads `GET /api/v1/key` `data.usage`, takes
spent = max(usage - start, last logged total) and refuses (exit 3) when spent + reserve > cap. Each call appends model,
resolution, aspect, out, cost, key usage and the running total (last column) to a TSV.

## Exact commands
```bash
concept-img --model bytedance-seed/seedream-5-0-flash --prompt-file draft.txt --resolution 2K --aspect 16:9 \
  --out draft.png --log spend.tsv --start <key usage at ticket start> --cap 3.00
concept-img --model google/gemini-3-pro-image --prompt-file callouts.txt --ref turnaround.png --resolution 2K \
  --aspect 16:9 --out callouts.png --log spend.tsv --start <start> --cap 3.00
# pick models and prices: curl -s https://openrouter.ai/api/v1/images/models/<id>/endpoints
```

## Pitfalls (measured)
- Key usage lags a few seconds: 3 parallel calls all read 0.0056, so totals undercounted. Run calls one at a time; the
  CLI falls back to the logged total.
- `google/gemini-nano-banana-2.1` has one provider (Google AI Studio) and returned HTTP 429 quota 3 times on
  2026-10-21; `google/gemini-3-pro-image` (Vertex too) worked: $0.135 per 2K image (2752x1536 at 16:9).
- Cheap drafts: `bytedance-seed/seedream-5-0-flash` $0.018 per 2K image, returns JPEG (the CLI converts to PNG when
  `--out` ends in .png). Its "side" view drifts to three-quarter; ask for "strict orthographic 90-degree profile".
- Callouts stay on-model when the turnaround is passed back with `--ref`.
- urllib honours proxy env: the mock test sets `no_proxy=127.0.0.1` (a proxy answered 502 otherwise).

## Links
- Code: ~/agents/bin/concept-img
- Tests: `bash ~/agents/bin/tests/concept-img.test.sh` (localhost mock, no network)
- Design / results: ~/agent-work/research/2026-10-21/T1035/ (prompts, drafts, spend.tsv), ~/drop/T1035/
