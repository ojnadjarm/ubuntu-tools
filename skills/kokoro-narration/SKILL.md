---
name: kokoro-narration
description: Narration with local Kokoro TTS (af_heart, English) or edge-tts (es-ES-AlvaroNeural, Spanish). Use for narrated explainers, voice-over, TTS clips with word timestamps, audio-driven animation timelines. Gives word timings, {cue} marks, cues.json and -16 LUFS Opus/AAC clips.
allowed-tools: Bash(~/.local/opt/kokoro/bin/python:*)
---

Triggers: cue sheet, sync to the spoken word.

# kokoro-narration: script with {cue} marks → clips + cues.json

```bash
PY=~/.local/opt/kokoro/bin/python   # uv venv: kokoro 0.9.4, torch 2.14 CPU
$PY ~/.claude/skills/kokoro-narration/render_narration.py unit.json public/bundles/a01        # all clips
$PY ~/.claude/skills/kokoro-narration/render_narration.py unit.json public/bundles/a01 w2 d1  # re-render only these (clips with no earlier render in cues.json are rendered too)
```

`unit.json` (real example: `~/agent-work/research/2026-09-23/T65/mockups/atelier/content/a01.unit.json`):
```json
{ "voice": { "engine": "kokoro-82M-fp32", "voice": "af_heart", "speed": 0.92 },
  "clips": [ { "id": "w1", "sentences": ["{tubes}Two numbers go in on the left.", "Each one is called an {input}input.|"] } ] }
```
- `{name}` marks the start of the **next word** (+40 ms bias). Put it right before the word the visual must land on.
- A sentence ending in `|` gets a 0.65 s pause after it (used after a new term), otherwise 0.30 s. Each clip starts with 0.15 s of silence.
- Output: `<out>/audio/<id>.opus` + `.m4a` (two-pass loudnorm to −16 LUFS, −1.5 dBTP), `<out>/cues.json`
  (`kbps`, `clips.<id>.{src,duration,marks,words[{w,s,e}]}`), raw WAVs in `<out>.raw/` **beside** `<out>` (do not ship them: never render into `public/`; render to
  `content/.render/<id>` and copy `cues.json` + `audio/`, as the explainer starter's `tools/narrate.sh` does).
- **Site (ailearning):** `KOKORO_PY=$PY KOKORO_RENDER=~/.claude/skills/kokoro-narration/render_narration.py tools/narrate.sh 01-neuron c4c`
  renders only the named clips (render dir seeded from the shipped `cues.json`, 24 kbps default) and merges only their cue entries and
  `audio/<id>.{opus,m4a}` into `public/bundles/<slug>/`. Never copy the whole render folder there: it can hold stale clips (skip, t0).
- Bitrate: Opus 64k + AAC 96k, or `NARRATION_KBPS=24` for both (AAC then 24 kHz; the ailearning default). It is saved as `kbps` in
  `cues.json`; a clip-id re-render reuses it, and stops if `NARRATION_KBPS` differs (re-render all clips to change it).
  `NARRATION_KBPS=default` names the 64/96k pair (`kbps` null: ailearning 02-layers, 03-loss need it with `tools/narrate.sh`). Never lower the
  bitrate to fit a budget the owner did not set: T99 re-encoded U01 to 22 kbps for an agent-made 3 MB cap, which he removed (2026-09-26).
  The site caps only the first chapter (600 kB per format).
- stderr `WARN word count` means Kokoro tokenised differently from the script (`U.S.`, `real-time`, `5.50`). Marks still land on their word:
  they are placed by text position. A mark in a sentence with no timed word, or whose tokens are not in the text, stops the render.
- **Spanish: `--engine edge`** (owner's pick, T1428): `$PY …/render_narration.py --engine edge unit.json out` with `"voice": "es"`
  (→ `es-ES-AlvaroNeural`) or any edge voice name. Words and marks come from edge-tts word boundaries; output is the same as Kokoro's.
  Kokoro `ef_dora` gives no Spanish word timings, so `{cue}` marks fail there. Edge needs network and uses Microsoft Edge's **unofficial**
  read-aloud endpoint (no key, may break). The paid fallback is Azure Speech with the same voice. About 6 s for a 2-sentence clip.
- Runtime: play through one `AudioContext`, clock = `ctx.currentTime − ctx.outputLatency`, scrub the timeline to it.
  Never drive animation from `setTimeout`. Reference: `T65/mockups/atelier/src/core/clock.ts`, `src/audio/voice.ts`.
- Speed: ~1× real time on this CPU (fixture: 2 sentences in 7.8 s wall, model load included).

Full guide (voices, measured scores, pitfalls): `~/agents/KB/guides/kokoro-narration-word-timings.md`.
