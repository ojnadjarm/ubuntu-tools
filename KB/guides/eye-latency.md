# Eye voice latency per turn: why is the reply slow

Ticket: T48-L4 · Last verified: 2026-10-07 by `~/the-dark-eye/bridge/relay/tests/latency.test.sh` (18/18 ok) and a fixture run

## When to use
You need p50/p95 of how long The Dark Eye takes to answer a voice turn (mic or phone), per stage.
Not for ASR accuracy (WER is `/api/voice/stats` on the dashboard) and not for driving a live turn (`~/the-dark-eye/body/test/e2e-voice.sh`, uses the real mic).

## The path we took
`eye-latency` (`~/the-dark-eye/bridge/relay/`, on PATH via its `install.sh`) is a read-only Python parser of `journalctl --user -u dark-eye -o short-iso-precise`.
It pairs each turn by order: end of speech (`mic audio:` / `remote audio:`) → ASR text (`heard (`) →
first TTS chunk (`audio chunk seq=0 last=`) → phone reply (`reply N for the phone: … bytes`), and prints
p50/p95 for four stages: `asr`, `reply_to_audio`, `first_audio`, `phone_reply`.
Turns cut by a restart, answers more than 300 s late, cut chunks and text-only replies are dropped.

## Exact commands
```bash
eye-latency                               # last 7 days, table
eye-latency --since "2 hours ago" --json  # machine-readable
eye-latency --file saved-journal.txt      # parse a saved journal text (- for stdin)
bash ~/the-dark-eye/bridge/relay/tests/latency.test.sh
```

## Pitfalls (measured)
- `reply_to_audio` mixes brain time and first-sentence TTS: no log line marks the brain reply (T48-L4 run 2026-09-22: p50 8.45 s, p95 37.06 s over 114 turns).
- `audio chunk` is logged at synthesis, not playback; phone playback start is not logged at all.
- Turns are paired by order, not by id: a tail over 60 s may be an unanswered turn paired with later speech.
- Notes-mode (eager voice) turns return before the `audio chunk` line, so they have no first-audio point.

## Links
- Code: `~/the-dark-eye/bridge/relay/eye-latency`
- Tests: `~/the-dark-eye/bridge/relay/tests/latency.test.sh` with `tests/fixtures/latency-journal.txt`
- Design / results: `~/agents/research/2026-09-22/T48-L4-result.md`
