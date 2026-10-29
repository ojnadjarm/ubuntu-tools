# Narrate with local Kokoro TTS, word timings and a cue sheet that drives the animation

Ticket: T65 (narration lane), used by T65 mockups, T69, T70 ports; T1428 added `--engine edge` for Spanish · Last verified: 2026-10-29 by T1428 (8/8 skill tests; real renders: es-ES-AlvaroNeural clip, marks botón 0.515 s, cambiar 4.49 s, 6.4 s wall; English fixture unchanged, tubes 0.515 s, input 4.065 s); before: 2026-10-20 by T846 read-only audit (`--help`, paths, code); before: 2026-10-19 by rendering the SKILL.md fixture offline with the skill script (marks tubes 0.515 s, input 4.065 s, 42 s wall at load ~9), the Ogg command and `test -e` on every path

## When to use
- A narrated explainer, voice-over or tutorial where visuals must land on spoken words: use the skill `/kokoro-narration`.
- **Spanish: `--engine edge`** (edge-tts, `es-ES-AlvaroNeural`, owner's pick in T1428). Kokoro `ef_dora` sounds clearly worse
  and gives no word timings in Spanish. English stays on Kokoro `af_heart`.
- Not for the Eye's live voice: that is sherpa-onnx int8 Kokoro in `~/the-dark-eye` (real-time, lower quality, see pitfalls).
- Not for pronunciation reference clips: `~/agents/dashboard/src/tts-gen.js` (T30) already does those.

## The path we took
- Survey: 29 renders of 16 local TTS models, same 3 lines, scored by Parakeet WER, UTMOS22 + UTMOSv2, pitch SD,
  Resemblyzer same-voice score, RTF (`T65/tts/table.md`). Winner: **Kokoro-82M fp32, `af_heart`, speed 0.92**
  (UTMOSv2 3.96, WER at the 0.8 % floor, same-voice 0.974, Apache-2.0, native word timestamps). The owner confirmed
  by ear: "the voice is perfect" (T69 brief). Male fallbacks: `am_michael` (3.75), `bm_george` (3.63).
- Build time: script with `{cue}` marks → Kokoro `KPipeline` (tokens carry `start_ts`/`end_ts`) → marks = next word's
  start + 40 ms → 2-pass ffmpeg loudnorm −16 LUFS / −1.5 dBTP → Opus 64k + AAC 96k (or `NARRATION_KBPS` for both, saved as `cues.json` `kbps`) → `cues.json`.
- Runtime: one `AudioContext`; clock = `currentTime − outputLatency` (`AudioClock`); timeline is scrubbed to it, so
  pause/seek stay in sync. `NullVoice` + `ManualClock` for muted runs, frozen frames and the offline recorder.
- The Godot and Bevy ports (T70) reuse the same `cues.json` and clips (Opus → Ogg Vorbis for Godot).

## Exact commands
```bash
PY=~/.local/opt/kokoro/bin/python
$PY ~/.claude/skills/kokoro-narration/render_narration.py unit.json out/bundle [clip-id…]   # skill copy, paths as args; clip ids re-render only those, plus any clip missing from cues.json, at the sheet's kbps
$PY ~/.claude/skills/kokoro-narration/render_narration.py --engine edge es.unit.json out/es   # Spanish: "voice": "es" (→ es-ES-AlvaroNeural) or any edge voice name; needs network
ffmpeg -loglevel error -i out/bundle/audio/w1.opus -c:a libvorbis -q:a 4 w1.ogg             # Godot wants Ogg
# score a new voice/model the way the lane did (WER, MOS, consistency, table):
cd ~/agent-work/research/2026-09-23/T65/tts/scripts && cat run_all.sh     # r_*.py renderers, score.py, table.py
```

## Pitfalls (measured)
- `{cue}` marks the **next word**: `"{input}Each one is called an input."` fires on "Each" (4.47 s), not on "input".
  Write `an {input}input.` to hit the word (fixture: word 4.025 s → mark 4.065 s).
- Kokoro keeps `well-known`, `U.S.`, `5.50`, `real-time` as one token each, so a regex word count differs. The renderer
  places each mark by the token's position in the text, so it stays on its word; if a sentence with a mark has no timed
  word, or a token is not found in the text, it exits naming the sentence (2026-09-24, F78).
- ailearning: never copy the whole render folder into `public/bundles/` (its `cues.json` held stale `skip`, `t0`); `tools/narrate.sh <slug> <clip…>`
  seeds the render from the shipped sheet and merges only the named clips (2026-09-26, sandbox: one clip changed, 183 files untouched).
- A clip-id re-render without `NARRATION_KBPS` used to fall back to 64k/96k beside 24k clips (ailearning c8a–c9b,
  2026-09-26, F52). The bitrate is now kept in `cues.json` and reused; a differing `NARRATION_KBPS` stops the render.
  `new-lesson --narrate` once rendered at 64/96k (`kbps` null: ailearning 02-layers, 03-loss), so `tools/narrate.sh` (24 by default)
  stops on them; it now passes `NARRATION_KBPS` (default 24), so an empty value still means 24. One clip there:
  `NARRATION_KBPS=default tools/narrate.sh 02-layers <clip>` (`default` = the 64/96k pair; 2026-10-03, F49; 2026-10-15, F45).
- `KPipeline` calls `hf_hub_download` for config, model and voice on every render; with no network it crashed (httpx 403)
  although all three sit in `~/.cache/huggingface/hub`. The renderer now sets `HF_HUB_OFFLINE=1` unless the caller set it;
  on a fresh machine run once with `HF_HUB_OFFLINE=0` to fetch the model (2026-10-10, F53; offline: import 4.9 s, init 2.2 s).
- Native Kokoro word starts sit a constant **61 ms early** vs the MMS_FA forced aligner (57–63 ms per voice, SD 19 ms,
  1,089 words). Hence the +40 ms bias; p95 residual after it 41 ms. Cue on starts: word *ends* jitter ~110 ms.
- The Eye's **int8 sherpa-onnx Kokoro** scored UTMOSv2 2.26 vs 3.55 for the same voice in fp32, and was slower here
  (RTF 1.6 vs 0.8). `~/agent-work/research/2026-09-23/T65/toolchain/sync/render-narration.cjs` used it with Parakeet timings, which sit on an **80 ms grid**:
  too coarse for a clock. Use fp32 `kokoro` for anything shipped.
- Autoregressive models drop words silently (Orpheus `tara` skipped "the result", WER 4.4 %). Any non-Kokoro voice
  needs an ASR gate (`score.py`). The shipped renderer only checks the word count, and it has no WER gate.
- Speed 0.92 helped `af_heart` (172 → 162 wpm, UTMOSv2 3.87 → 3.96) but hurt `am_michael` (3.75 → 3.54): tune per voice.
- CPU only here: F5-TTS RTF ≈ 56, Dia did not finish one line in 28 min, Breeze refuses non-CUDA. Kokoro ≈ 1× real time.
- Licences: Piper lessac (research data), XTTS-v2 (CPML) and F5 (CC-BY-NC) are not usable on a public site.
- Sound around the voice: no music bed under explanation (coherence effect), background ≥ 20 dB under speech,
  earcons ≤ 350 ms and one per concept, 0.4–0.8 s of silence after a new term (lane §7).

- **A budget nobody owned lowered the voice quality** (T84 → T99 → T100): an agent-set 3 MB per-unit cap made T84 encode at 20 kbps and T99
  re-encode U01 to ~22 kbps to fit 7 new lines (3,130 kB). The owner removed the cap ("take out the cap, don't redo anything"); only the
  first chapter keeps 600 kB. Never lower the bitrate to fit a budget he did not set.

- **Spanish (T1428, 2026-10-29).** Kokoro `ef_dora` gives **0 word timings** (`WARN word count 0 != 12`): no Spanish token
  came back with a `start_ts`, so a `{cue}` mark stops the render. `--engine edge` takes words from edge-tts `WordBoundary` events.
  Over 41 words those starts sat a median 0–60 ms from faster-whisper word starts (Alvaro 22–30 ms), so the same +40 ms bias applies.
- edge-tts uses Microsoft Edge's **unofficial** read-aloud endpoint: no key, no SLA, and it can break or be blocked at any time. The paid
  fallback is **Azure Speech** with the same voice name (~$0.014/min, needs an Azure account). It needs network: an offline render fails.
- Edge clips end in ~0.8 s of silence, which would stretch every sentence gap. The renderer cuts each sentence 0.15 s after the last word's end.
  Edge speed: unit `speed` maps to `rate` (0.95 → `-5%`); the Kokoro-tuned 0.92 is not a tested choice for Alvaro (the proof used 1.0).
- Rejected for Spanish (T1428 page `~/drop/tts-es/`): Qwen3-TTS local (RTF 11–29 on this CPU, one variant misread 2 of 3 lines),
  OpenRouter `openai/gpt-audio` (~$0.083/min) and `-mini` (~$0.005/min). Those are chat models that answer the line unless told
  "your spoken reply is only this text", and they give no word timings.

## Links
- Skill: `~/.claude/skills/kokoro-narration/` (SKILL.md + `render_narration.py`)
- Code: `~/agent-work/research/2026-09-23/T65/mockups/atelier/tools/render_narration.py` (original),
  `…/atelier/src/core/clock.ts`, `…/atelier/src/audio/voice.ts`, unit `…/atelier/content/a01.unit.json`
- Scoring: `~/agent-work/research/2026-09-23/T65/tts/scripts/` (`r_kokoro.py`, `score.py`, `table.py`, `mixdemo.py`)
- Design / results: `~/agent-work/research/2026-09-23/T65/lanes/narration.md`, `T65/tts/table.md`, `T65/plan.md` §8
- Listening set: `~/agent-work/research/2026-09-23/T65/audio/` (renders; scores in `T65/tts/table.md`, `T65/tts/scores.jsonl`)
