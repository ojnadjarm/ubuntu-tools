# Dashboard pronunciation: drill prompts, Kokoro references and the machine error floor

Ticket: T30 · Last verified: 2026-10-15 by reading the code and counting state/floor.json against voice_prompts.json

## When to use
You edit or add a prompt in `~/agents/dashboard/voice_prompts.json`, the Voice page says "floor.json missing" or
"floor stale", or a reference wav is missing. Not for narration audio: use kokoro-narration-word-timings.

## The path we took
| File | What |
|---|---|
| `voice_prompts.json` | every prompt (`id`, `lang`, `group`, `text`, `len`); `group: drill` prompts get a floor |
| `src/tts-gen.js` | one Kokoro wav per drill sentence and per target word into `state/tts/`; skips a wav whose text matches `state/tts/texts.json` |
| `transcribe.js` | one-shot Parakeet decode of a wav, the Eye's model and settings; prints JSON |
| `src/floor.js` | runs tts-gen, decodes each drill wav with transcribe.js, scores it with the dashboard rules → `state/floor.json` |
| `dash/services/voice.py` | `floor()` drops a prompt whose text changed (stale); his WER = raw WER minus the floor |

## Exact commands
```bash
cd ~/agents/dashboard
node src/floor.js           # new or edited drill prompt: its wavs made, only new or changed prompts decoded
node src/floor.js --force   # every wav remade, every drill decoded
node src/tts-gen.js         # reference wavs only, no floor
voice-progress [--json]     # drill progress: errors per 100 target words per pattern vs the week-0 baseline; read-only
```

## Pitfalls (measured)
- floor.json covers drill prompts only: 30 of the 90 prompts on 2026-10-15, all 30 current. The other 60 always score raw.
- Changing a drill prompt's text makes its floor stale (dropped) until `node src/floor.js` runs again.
- Sentence wavs are named `s-<id>.wav`; tts-gen remakes one when its text differs from `state/tts/texts.json`. A wav with no entry there is remade too, so the first run after 2026-10-17 remakes every wav.
- transcribe.js loads a ~1.1 GB model; the dashboard runs it in a transient unit with MemoryMax=2G.

## Links
- Code: `~/agents/dashboard/src/{tts-gen,floor}.js`, `transcribe.js`, `dash/services/voice.py`
- Tests: `cd ~/agents/dashboard && python3 -m pytest tests/test_voice.py -q`; `~/agents/bin/tests/voice-progress.test.sh`
