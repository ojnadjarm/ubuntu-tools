# Add subtle UI sounds to a web page with procedural Web Audio (no samples, no speakers)

Ticket: T57 · Last verified: 2026-09-24 by `node --test test/remote-sound.test.js` (with ack/orbiter tests: 13/13 pass)

## When to use
- A page needs soft UI sound: taps, chimes, whooshes, ambient beds that follow a live value (mic level, state).
- Start from `~/the-dark-eye/body/src/remote-www/sound.js` (286 lines, one IIFE, `window.Sound.create()`), and invoke the
  `ui-sound-design` skill for the describe-generate-listen-refine loop and its rulebook.
- A fixed spoken word or clip is not synthesis: see `eye-ack-tts-clip.md`. The dashboard does not have the kit yet (T57 scope:
  second pass only after the owner likes it).

## The path we took
- Survey: ZzFX sounds chiptune, Tone.js is ~300 kB, howler only plays samples, so we wrote our own synthesis.
- Graph: every voice → `bus` → `duck` (gain) → `out` (user volume) → `WaveShaper` tanh soft clip at −10 dBFS →
  low-pass 7 kHz, Q 0.5 → destination. One shared 2 s noise buffer for airy sounds.
- Musical: D major pentatonic, `note(d)` maps a scale degree to Hz (0 = D3, 5 = D4, 10 = D5).
- Envelopes: `linearRampToValueAtTime(peak)` then `setTargetAtTime(0, …)`; never a ramp to 0, never an instant step (clicks).
- 8 sounds. Events: `shimmer` (eye assembles), `chime` (agent in / out), `whoosh` (section), `tick` (tap). States via
  `kit.state(name)`: listening air bed follows `kit.mic(level)`, thinking pad, speaking ducks everything.
- Rate limits per sound (`gap(k, s)`), parameters driven at ≤ 30 Hz, no per-frame main-thread work.
- Autoplay: silent until `kit.unlock()` runs inside a gesture (the page calls it on the first `pointerdown`/`keydown`).
- Idle cost: with no bed running the context suspends 5 s after the last sound (`stir()`); `kit.hidden(true)` suspends it.
- Settings: `{on, vol}` in `localStorage` key `darkeye.sound` (per device), mute button + volume slider in the page header.

## Exact commands
```bash
cd ~/the-dark-eye/body
node --test test/remote-sound.test.js          # served without cookie, lab behind the key, levels rendered offline
# lab page with every sound on a button (behind the Eye key):  https://<tailnet>:8644/lab/sound.html
cd ~/agents/research/2026-09-23/T57/build            # a stub Eye on :18657 (key t57), never the live body
./nosound node dev-server.js &                        # nosound = bwrap hiding /dev/snd and the pipewire socket
./nosound node levels.js    # peak/bed dBFS via window.labLevels() on an OfflineAudioContext
./nosound node duck.js      # duck depth under the voice · fps.js: fps before/after the kit
```

## Pitfalls (measured)
- **Never play on the machine's speakers or TV** (T57 rule): render with `OfflineAudioContext`
  (`Sound.create({context})`) or launch test browsers with `--mute-audio` (added to all 33 Dark Eye test launches).
- The owner's first reaction: too quiet. First kit peaked at −29.7 dBFS, beds −38.7 at full volume; the brief's ceilings
  were −24 / −36. Final default: events −23 dBFS, beds ≈ −33, slider +6 dB above default, duck 23.5 dB under TTS
  (brief asked ≥ 12). Measure levels **at the default volume**, which is what he hears.
- The live Dark Eye server returned 401 for `sound.js` until restart: static files are an allowlist
  (`PUBLIC` in `body/src/remote.js`). A new page asset needs an entry there and a dark-eye restart (the owner's call).
- fps unchanged (60 → 60 at 400 and 1920); idle CPU 20.2 → 19.8 % because the context naps; +2.5 % while a bed plays.
- The listening bed plays while the mic is open (≤ −38.7 dBFS at first); browser echo cancellation must remove it.
- `tools/analyze-sound.mjs` in the skill shells out to ffmpeg with a quoted path: give it plain filenames.

## Links
- Code: `~/the-dark-eye/body/src/remote-www/sound.js`, wiring in `remote-www/index.html` ("the sound" block), lab `remote-www/lab/sound.html`
- Tests: `~/the-dark-eye/body/test/remote-sound.test.js`
- Scripts: `~/agents/research/2026-09-23/T57/build/` (`common.js` = muted Playwright launch) · backups `~/agents/backups/T57/`
  (the 20 s demo video `~/drop/t57/` is gone from the drop as of 2026-09-24)
- Brief: `~/agents/briefs/T57-sound-design.md` · Skill: `ui-sound-design`
