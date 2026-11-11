# Generate AI concept art (character sheets) through OpenRouter under a hard dollar cap

Ticket: T1035, T1632 · Last verified: 2026-11-11 by bin/tests/concept-img.test.sh (mock); 9 real calls 2026-10-21

## When to use
Only when the requester's own words ask for an AI, generated or concept image (owner 2026-11-11, T1632): create / draw /
design / represent = make it yourself by code (/code-hero-render, /char3d, /pixel-avatar, /familiars-style,
/cutaway-style, SVG, Blender by script). A generated image is a concept, never the delivered asset. Not for textures or
image-to-3D.

## The gate (T1632): one gate, in the tool
- `--asked "<verbatim quote>"` is required; the quote must name an AI/IA, generated, concept or image-model ask, else
  exit 4 with one line: "make it yourself by code; the image model needs the requester's own words asking for an AI
  image". The quote is logged in the spend TSV (`asked` column) and the month ledger.
- No key in the environment (`OPENROUTER_KEY_FILE` empty, e.g. `/dev/null`) is exit 4 too. Discord liaison jobs run with
  `/dev/null`; `discord-liaison art --asked "<quote>"` passes the key and quote only when the quote is in the job's own
  messages. `po-work` workers get `/dev/null` unless their brief has a line `AI image grant: "<his exact words>"`.
- Caps (config keys, `config.example.env`): `CONCEPT_IMG_JOB_CAP` 2.00 a job (one `--log`) when no `--cap`;
  `CONCEPT_IMG_MONTH_CAP` 10.00 a calendar month over the ledger `CONCEPT_IMG_LEDGER` (~/agents/log/concept-img.tsv),
  both exit 3 before any POST; crossing 80 % of the month sends one `notify-owner` line.
- Not a sandbox: an agent that reads the key file itself bypasses the gate; the prompts (manager template, JOB.md, art
  skill heads) carry the rule.

## The path we took
No fleet image CLI existed. `concept-img` calls OpenRouter's dedicated Image API (`POST /api/v1/images`, base64 PNG in
`data[0].b64_json`, `usage.cost`), not chat completions. Before each call it reads `GET /api/v1/key` `data.usage`, takes
spent = max(usage - start, last logged total) and refuses (exit 3) when spent + reserve > cap. Each call appends model,
resolution, aspect, out, cost, key usage and the running total (last column) to a TSV.

## Exact commands
```bash
concept-img --asked "<his words asking for AI concept art>" --model bytedance-seed/seedream-5-0-flash \
  --prompt-file draft.txt --resolution 2K --aspect 16:9 --out draft.png --log spend.tsv --start <key usage at ticket start>
concept-img --asked "<same quote>" --model google/gemini-3-pro-image --prompt-file callouts.txt --ref turnaround.png --resolution 2K \
  --aspect 16:9 --out callouts.png --log spend.tsv --start <start>
# pick models and prices: curl -s https://openrouter.ai/api/v1/images/models/<id>/endpoints
```

## Pitfalls (measured)
- `--start 0` makes job spent = the key's lifetime usage, so the default $2 job cap refuses every call; omit `--start`
  (spent = the log's total) unless you read the key usage at the job's start (the liaison's `art` dropped it, T1632).
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
- Design / results: ~/agent-work/research/2026-10-21/T1035/ (prompts, drafts, spend.tsv), ~/drop/T1035/ (pruned)
