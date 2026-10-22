# Time the Claude Code tool-call hooks (p50/p95 per hook)

Ticket: T1073 · Last verified: 2026-10-21 by `bin/tests/hook-bench.test.sh` (11 ok) and `hook-bench -n 50` on the live settings

## When to use
Before and after editing any PreToolUse/PostToolUse hook, or when calls feel slow: every hook runs on each of the ~21,000 tool calls a day, and agents-log records no hook timing. Not for SessionStart/Stop/Subagent*/PostCompact hooks (listed as skipped: rare, and orbit-hook pushes to the Eye).

## The path we took
- Survey: hyperfine cannot feed a different stdin per run; `pc bench` covers only `pc-*` verbs; nothing timed hooks. Chosen: a small Python CLI with `time.perf_counter_ns` around each run.
- `hooks()` reads `~/.claude/settings.json` (read only), one row per hook command (first tool event wins, so audit-log is timed once as PostToolUse).
- `payloads()` rebuilds hook stdin from the newest `log/actions.jsonl` rows the matcher accepts (`summary` stands in for `command`/`file_path`), cycled up to `-n`; TaskStop rows are skipped (audit-log would start orbit-hook).
- `sandbox_env()` points HOME, HARNESS_HOME and XDG_RUNTIME_DIR at a mktemp dir; `$HOME` in the command is expanded to the real home first. One untimed warm-up run per hook, then `-n` timed runs; the dir is removed at the end.

## Exact commands
```bash
hook-bench -n 50                 # <hook> <event> n 50 p50 X ms p95 Y ms [async]
hook-bench -n 50 --max-p95 30    # exit 1 when a hook's p95 is above 30 ms
hook-bench --settings F --log L  # fixture settings / recorded calls
nice -n 19 bash ~/agents/bin/tests/hook-bench.test.sh
```

## Pitfalls (measured)
- `subprocess.run(..., timeout=)` waits in sleeps that double up to 50 ms: every python hook came out at 16.0 or 32.0 ms. The timeout is now a `threading.Timer` kill; image-reread went 32.1 → 20.4 ms p50.
- 2026-10-21 baseline (load ~2, nice 19, n 50): audit-log 11.6 / 14.4 ms (async, so it does not block the call), sleep-loop-block 2.7 / 3.0 ms (dash front), image-reread 20.4 / 25.0 ms.
- image-reread is slow because 32 of the newest 50 Reads were images, which take its full path (json/os import, stat, counts file); a bare `python3 -IS -c pass` costs ~8 ms here.
- The real log grows from live agents during a run, so the test checks for rows with session `hookbenc` (the payloads' id, clipped to 8) instead of a byte count.

## Links
- Code: ~/agents/bin/hook-bench
- Tests: `nice -n 19 bash ~/agents/bin/tests/hook-bench.test.sh`
- Design: ~/agent-work/research/2026-10-21/T1058/BACKLOG.md §15
