# Eye voice latency per turn: why is the reply slow

Ticket: T48-L4, T1196, T1214 · Last verified: 2026-10-21 by a body-sandbox run (`--audio null`) logging `playback started` and `eager audio seq=0 last=true` and latency.test.sh 42/42 (T1214); 2026-10-21 by a body-sandbox run: 2 phone turns taken before any answer, a third acked, an unsolicited speak (`~/agent-work/evidence/T1196/`) and latency.test.sh 36/36 (T1196 fix); 2026-10-20 by `eye-latency --help`, parser patterns vs `body/src/main.js`/`replies.js` log lines (T846); 2026-10-07 by `~/the-dark-eye/bridge/relay/tests/latency.test.sh` (18/18 ok) and a fixture run

## When to use
You need p50/p95 of how long The Dark Eye takes to answer a voice turn (mic or phone), per stage.
Not for ASR accuracy (WER is `/api/voice/stats` on the dashboard) and not for driving a live turn (`~/the-dark-eye/body/test/e2e-voice.sh`, uses the real mic).

## The path we took
`eye-latency` (`~/the-dark-eye/bridge/relay/`, on PATH via its `install.sh`) is a read-only Python parser of `journalctl --user -u dark-eye -o short-iso-precise`.
It pairs each turn by its `[t<n>] ` tag (by order in journals before T1196): end of speech (`mic audio:` / `remote audio:`) → ASR text (`heard (`) →
brain reply (`speak received:`) → past the hold (`speak sent`) → first TTS chunk (`audio chunk seq=0 last=`) → phone reply (`reply N for the phone: … bytes`) →
phone playback (`reply N played on the phone after Mms`, logged on `/remote/ack`); local playback (`playback started`, first bytes into `pw-cat`,
once per utterance) and the notes-mode voice (`eager audio seq=N last=true`), and prints
p50/p95 for nine stages: `asr`, `brain`, `tts`, `reply_to_audio`, `first_audio`, `local_play`, `eager_ready`, `phone_reply`, `phone_play`.
Turns cut by a restart, answers more than 300 s late, cut chunks and text-only replies are dropped.
The body tags a reply with the oldest turn its brain took (`brains.answer`, `body/src/brains.js`) and has not
answered by a speak or an `eye ack`; a turn stops being owed after 300 s. `tts` runs from `speak sent`.

## Exact commands
```bash
eye-latency                               # last 7 days, table
eye-latency --since "2 hours ago" --json  # machine-readable
eye-latency --file saved-journal.txt      # parse a saved journal text (- for stdin)
bash ~/the-dark-eye/bridge/relay/tests/latency.test.sh
```

## Pitfalls (measured)
- `reply_to_audio` mixes brain time and first-sentence TTS: no log line marks the brain reply (T48-L4 run 2026-09-22: p50 8.45 s, p95 37.06 s over 114 turns).
- `audio chunk` is logged at synthesis; `local_play` (eos → `playback started`) is bytes handed to `pw-cat`, not sink latency.
- No brain sends a turn id back: the body pairs a reply with the oldest turn its brain took and left unanswered. A brain
  that answers two turns in one speak, or answers t2 before t1, gives the next speak the wrong turn; untagged journals
  (before T1196) are paired by order.
- An `eye ack` closes its turn with no `brain` time; a speak after the ack is untagged.
- Notes-mode (eager voice) turns have no `audio chunk` line: they show only as `eager_ready` (eos → the eager job's last chunk).

## Links
- Code: `~/the-dark-eye/bridge/relay/eye-latency`
- Tests: `~/the-dark-eye/bridge/relay/tests/latency.test.sh` with `tests/fixtures/latency-journal.txt`
- Design / results: `~/agent-work/research/2026-09-22/T48-L4-result.md`
