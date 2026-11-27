# Ask for AI concept art on the owner's Google plan (genai, Antigravity CLI)

Ticket: T2006 · Last verified: 2026-11-27 by bin/tests/genai.test.sh (fake agy; no real agy installed yet)

## When to use
Any fleet agent that needs a concept image (a look to aim at, a character idea, a mood) asks `genai`. A generated image
is a concept, never the delivered asset: project rules "assets drawn in code" stay as they are, the delivered art is
still made by code (/code-hero-render, /char3d, /pixel-avatar, SVG, Blender by script). Not for video, voice or music.
The paid OpenRouter path (`concept-img`, guide concept-img) stays as it is.

## The path we took
`genai` hands the ask to Google's Antigravity CLI (`agy -p`, headless), signed in with the owner's Google AI Pro account:
plan quota, no API key, no dollars. One account, so one ask at a time: `genai ask` runs inline under one `flock`
(`~/agents/log/genai.tsv.lock`); no daemon, queue or service. The backend is one function, `run_agy` in `bin/genai`.
Output: `~/drop/T<n>/concept/<id>-<k>.png` plus `<id>.md` (first line "CONCEPT, not an asset"; need, prompt sent,
refs, backend, model, date). One TSV line per ask in `~/agents/log/genai.tsv`: ts, ticket, seat, n, backend, exit, seconds.

## Exact commands
```bash
genai ask --ticket T<n> --need "<what the art is for and what it shows>" [--n 1..4] [--ref img.png]...
genai doctor        # installed (path, version), signed in, last ask; exit 0 only when an ask can run
# exit 0 made · 1 backend error · 2 usage · 3 quota exhausted (prints the reset line if agy gave one) · 5 agy missing or not signed in
```
The owner's two steps (agy is not installed yet; `genai` prints them on exit 5):
1. `curl -fsSL https://antigravity.google/cli/install.sh | bash`
2. run `agy` and sign in with his Google AI Pro account.

## Pitfalls (measured)
- `run_agy` is unproven against a real agy (none here on 2026-11-27); written from third-party sources: the flags
  (`-p ... --output-format json`), whether the headless agent may save images without an approval prompt (no
  `--dangerously-skip-permissions`: it would approve every tool), where images land (asked for the cwd; paths printed
  in the output are picked up too), the 429 and sign-in error texts, and a `model` field in the JSON. Re-check with
  `agy --help` and one real `genai ask` once he has signed in.
- Reported upstream: `agy -p` can hang or drop stdout without a TTY; `genai` gives agy 600 s (doctor 120 s).
- `genai doctor` proves sign-in with a one-word text prompt: it spends a little plan quota.
- Quota is the plan's: a 429 is exit 3, wait for the reset; never retry in a loop.
- Never read, copy or print agy's token file; no proxy reuses its login outside agy.

## Links
- Code: ~/agents/bin/genai
- Tests: `bash ~/agents/bin/tests/genai.test.sh` (fake agy on a temp PATH and HOME, no network)
- Design: ~/agent-work/briefs/T2006-genai-agent.md
