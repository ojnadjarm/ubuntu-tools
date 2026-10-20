# Answer a voice line with a silent ack and a pre-rendered "Understood" clip (eye ack)

Ticket: T58 (ack), T63 (clip) · Last verified: 2026-10-20 (T846: paths, `eye ack` usage, config defaults, live clip 200 44 638 bytes); 2026-10-19 by `node --test test/remote-ack.test.js` (3/3, muted), the live body serving `/understood.wav` (200, 44 638 bytes) and `test -e` on every path; `eye ack` not sent (no sound)

## When to use
- The owner says something that needs no words ("ok", "yeah"): `eye ack --as <brain>` instead of `eye speak`.
  It counts as the answer for the unanswered-voice watchdog (T49); otherwise the page "thinks" for 60 s and he gets a nudge.
- Adding any other fixed spoken cue to the Eye: copy the clip pattern (render once offline, ship a wav, play on the reply context).
- Longer narration with word timings is a different job: invoke the `kokoro-narration` skill.

## The path we took
- Command path: `eye` = `~/.local/bin/eye` → `~/the-dark-eye/bridge/relay/eye-tap` (marks `~/.local/state/dark-eye/relay/<brain>.spoke` after a successful
  `speak|link|ack`) → `~/the-dark-eye/bridge/eye.sh ack [--to local|remote|both]` → `POST /bridge/ack {to, brain}` in
  `body/src/server.js` → `replies.ack()` → the page's long-poll gets `reply.ack`.
- `--to` defaults to where he last spoke. `remote` (the phone/PC page) blinks, glances down and plays the clip on the
  same `AudioContext` as replies. `local` sends the same samples through `audio.play` to the room.
- The clip (T63): `body/scripts/understood.js` renders "Understood." once with sherpa-onnx Kokoro in the Eye's own reply
  voice (`DEFAULTS.voiceModelDir`, `voiceSid` 17, `voiceSpeed`), trims silence (10 ms head pad, 50 ms tail), writes 16-bit
  mono `body/src/remote-www/understood.wav` (0.93 s, 44 638 bytes). Deterministic: no live TTS, no LLM.
- The page decodes it once (`fetch("understood.wav")` → `decodeAudioData`) and plays it only in `call` mode with a running
  context. Audio-notes mode, or a clip not decoded yet, falls back to the T57 soft chime; when the word plays, the chime is dropped.
- Served without login through the `PUBLIC` allowlist in `body/src/remote.js` (`"/understood.wav"`).

## Exact commands
```bash
eye ack --as "${EYE_BRAIN:-main}"                 # after a line that needs no words
eye ack --to remote --as main                     # force the phone/PC page
cd ~/the-dark-eye/body && node scripts/understood.js   # re-render the clip (after a voice change)
node --test test/remote-ack.test.js               # Playwright, muted, asserts the playback event and ≤ 300 ms
curl -s -o /dev/null -w '%{http_code} %{size_download}\n' http://127.0.0.1:8644/understood.wav   # live clip served?
```

## Pitfalls (measured)
- Latency: `eye ack` → page ready p50 66 ms / p95 78 ms (T58, 12 trials); `eye ack` → audio start 56–73 ms alone (T63),
  but 404 ms under the full parallel suite because bash starts slowly under load. The test times bridge arrival → audio start.
- A new route or asset in the body needs a dark-eye restart; until then `eye ack` returned 404 (T58) and the page got a 404
  for the clip and fell back to the chime (T63). Agents never restart dark-eye: say it needs one.
- `bridge/install.sh` used to reset `~/.local/bin/eye` to `eye.sh`, dropping `eye-tap` (every answer then looks unanswered).
  Since T280 it keeps the tap; `bridge/relay/install.sh` restores it.
- Tests must never play on the speakers or TV: muted browser, playback asserted by event, not heard.
- The one known Dark Eye suite failure (`eye-sh.test.js` notes) comes from `NOTES_*` env vars in agent sessions; 49/49 pass unset.

## Links
- Code: `~/the-dark-eye/bridge/relay/eye-tap`, `~/the-dark-eye/bridge/eye.sh` (`ack)`), `body/src/server.js` (`POST /bridge/ack`), `body/src/main.js`
  (clip samples for `local`), `body/src/remote-www/index.html` (`understood`), `body/scripts/understood.js`
- Tests: `~/the-dark-eye/body/test/remote-ack.test.js`
- Briefs: `~/agent-work/briefs/T58-orbiters-instant.md`, `T63-ack-says-understood.md` · backups `~/agents/backups/T63/`
- Docs: `~/the-dark-eye/bridge/relay/README.md` (watchdog), `KB/runbooks/eye-relay.md`, skill `eye` (§ ack)
