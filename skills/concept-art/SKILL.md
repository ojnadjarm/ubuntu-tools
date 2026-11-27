---
name: concept-art
description: Get an AI concept image to aim at (mood, palette, density) - OpenRouter via `concept-img` (paid, capped) or `genai ask` (Google plan, free). Use for "concept art", "concept image", "AI image", "generate a concept", "mood board", "reference image". Never the delivered asset.
allowed-tools: Bash(concept-img:*), Bash(genai:*), Bash(secret:*), Bash(drop-link:*)
---

Triggers: openrouter, seedream, gemini image, image model, look to aim at.

# concept-art: an AI concept image, never the asset

- A concept is a target for mood, palette and density. The delivered art is still made by code (/code-hero-render,
  /char3d, /pixel-avatar, SVG, Blender by script); a project whose rules say "assets drawn in code" keeps that rule.
- Only when the requester's own words ask for an AI, generated or concept image; "draw / design / make" = by code.
- Never send a file of the owner's or any private data (names, accounts, screenshots of his apps) to an image service.

## Route 1 (main): OpenRouter through `concept-img`
1. Lease: a launcher runs `secret grant openrouter --ticket T<n> --asked "<requester's words>"` and exports the lease as
   `FLEET_LEASE_OPENROUTER`; a worker gets it from its brief's `AI image grant: "<quote>"` line (never asks itself).
2. Call, one at a time (key usage lags; parallel calls undercount):
   ```bash
   concept-img --asked "<same quote>" --model bytedance-seed/seedream-5-0-flash --prompt-file p.txt \
     --resolution 2K --aspect 16:9 --out ~/drop/T<n>/concept/a.png --log ~/drop/T<n>/concept/spend.tsv
   ```
3. Models (measured): `bytedance-seed/seedream-5-0-flash` about 0.018 USD at 2K, verified working 2026-11-27 (start here);
   `google/gemini-3-pro-image` about 0.135 USD, refused HTTP 402 "exceeds your available credits" on 2026-11-27 when the
   balance was low: fall back to seedream or route 2, never add credits.
4. Caps: 2 USD a job (one `--log`), 10 USD a month; exit 3 = cap, exit 4 = gate or lease refused. Omit `--start` unless
   you read the key usage at the job's start. `--ref img.png` keeps a series on-model.

## Route 2 (no cost): Google plan through `genai ask`
```bash
genai ask --ticket T<n> --need "<what the art is for and what it shows>" [--n 1..4] [--ref img.png]
genai doctor    # exit 0 only when an ask can run; exit 5 = agy missing or not signed in (owner steps printed)
```
About 5 images per quota window; exit 3 = quota exhausted, wait for the printed reset, never retry in a loop.
Writes `~/drop/T<n>/concept/<id>-<k>.png` plus `<id>.md`.

## The prompt
One paragraph, in this order:
1. Subject: what it shows and what it is for.
2. What makes it unlike the default take (the twist, the era, the material).
3. Look: medium, lighting, camera or framing.
4. Palette (3-5 named colours) and mood.
5. Format: aspect, single image or sheet.
6. End with: "original composition, not a copy of any existing artwork; no text, no logo, no watermark".

## Where results go
- `~/drop/T<n>/concept/` (link with `drop-link`); copy the chosen target to `~/agent-work/evidence/T<n>/`: the drop is cleaned.
- Report model, cost (spend.tsv last column) and the prompt beside the image.

Guides: `guide concept-img`, `guide genai`.
