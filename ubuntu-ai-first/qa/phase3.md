# Phase 3 QA report — 2026-09-05

Independent verification of T15–T19 (agent runtime and fleet) by the QA agent. Every check was
re-run by QA and pushed beyond the tickets' Success checks: a throwaway `qa-echo` agent, timeout
kill with orphan check, budget-flag tracing, systemd concurrency, kill-switch coverage, hook
latency/redaction/fuzz, sentinel fault injection via `SENTINEL_STATUS_CMD`, retention simulation
with 20 dated dumps, a deliberately dirty Moodle checkout, and roster-vs-systemd reconciliation.
Desktop tests were skipped (T28a agent was on the screen); desktop audit lines ignored.
All test artifacts removed (see §Cleanup).

## Verdict

| Ticket | Success check | Goal met | Verdict |
|---|---|---|---|
| T15 agent-runner | PASS | PASS | **PASS with defects** (D1 HIGH, D2 HIGH, D4, D5, D6) |
| T16 audit-log-hook | PASS | partly | **PASS with defects** (D3 HIGH, D7) |
| T17 sentinel-agent | PASS | PASS | **PASS with defects** (D2 HIGH, D8) |
| T18 moodle-keeper | PASS | PASS | **PASS** (D9 minor) |
| T19 fleet-contract-docs | PASS | PASS | **PASS** (D10 doc-accuracy, follows from D1/D2) |

## Evidence

### T15 — agent runner

- `qa-echo` (BRIEF + `agent.env` MODEL=sonnet/TIMEOUT/BUDGET_USD) created, `agent-now qa-echo` →
  unit ran, exit 0 in 10 s, `REPORT.md` = runner metadata (start/end/exit/seconds/cost_usd
  `0.0976958`) + the agent's own 2 lines, `logs/index.tsv` row written, `.log` + `.json` present.
  `agents-status` listed it (disabled, last exit 0, 10 s).
- **Timeout.** `TIMEOUT=20` + a brief running `python3 -c "time.sleep(240)"` → `agent-run` exited
  **124** after 20 s, `notify-owner -p high` fired (seen in `~/agents/log/notify.log`), and **no
  orphan child survived** (`pgrep -f "time.sleep(240)"` empty). systemd `TimeoutStartSec=3600` is
  the outer belt; the inner `timeout` is what actually enforces per-agent limits.
- **Budget.** `bash -x agent-run` shows the real argv:
  `timeout 120 claude -p '<brief>' --model sonnet --permission-mode bypassPermissions --name
  agent-qa-echo --append-system-prompt '<AGENT-PREAMBLE verbatim>' --output-format json
  --max-budget-usd 0.30`. With `BUDGET_USD=0.0001` the run aborted with exit 1 after $0.0496 —
  the flag is passed and enforced (at turn granularity, so it overshoots a tiny cap).
- **No concurrency.** Two `agent-now qa-echo` 3 s apart → only **one** row in `index.tsv`; the
  second `systemctl start` on the already-active `Type=oneshot` unit is a no-op. `agent-run` by
  hand has no lock of its own (see D6).
- **Bad schedule.** `agent-enable qa-echo "not a calendar"` → `Failed to parse calendar
  specification … Invalid argument`, exit 1, **no drop-in created**, timer still `disabled`. Clean.
- **Unit environment.** `systemctl --user show agent@qa-echo.service -p Environment` and
  `/proc/<pid>/environ` of a live run both give
  `PATH=~/.local/bin:~/agents/bin:/usr/local/bin:/usr/bin:/bin`, `HOME` correct, plus
  `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS`. Runs fine under `systemctl --user start`.
- **Kill switch.** `agents-stop` while `agent@qa-echo` was mid-run:
  - with a timer drop-in present → unit stopped (`failed`), tmux session `claude` **survived**
    (`tmux list-sessions` → `claude: 1 windows`, its `claude --continue` process alive). Correct.
  - **without** a drop-in → the running unit was **not** touched (D1).
  - `sentinel-check.timer` and `moodle-keep-weekly.timer` stayed **enabled and active** (D2).

### T16 — audit log

- **Latency:** 20 sequential invocations with a realistic payload → **19 ms average** per call
  (python3 start-up dominated). At the ticket's ≤ 20 ms budget, no margin (D7).
- **Fuzz:** `not json`, empty stdin, `{"tool_name":null}` → all exit **0**, no output, tool call
  unaffected. `python3 -c "[json.loads(l) …]"` over the whole file → valid JSONL.
- **Redaction:** `mysql -psuperpw` → `-p<redacted>`, `PGPASSWORD=hunter2` → `<redacted>`,
  `export API_KEY=abc123` → `<redacted>`. **`Authorization: Bearer sk-ant-SECRET123` leaks the
  token** and a JSON MCP input `"token": "sk-live-9999"` is not redacted at all (D3).
- **MCP tools:** the hook handles an `mcp__playwright__browser_navigate` payload (op = full tool
  name, input JSON truncated to 200 chars). No real `mcp__` line exists in the log yet — matcher
  `Bash|Edit|Write|MultiEdit|NotebookEdit|mcp__.*` is registered in `settings.json` but has not
  been exercised end-to-end by a real MCP call (not-testable here without a browser session).
- `agents-log --stats` works but groups by *session × op* where `op` for Bash is
  `"<cmd> <arg1>"`, so almost every row is unique and the "stats" are not an aggregate (D7b).
- **No harness leak:** `grep -rl audit-log ~/moodle-harness` → nothing; the 5 modified files in
  `git -C ~/moodle-harness status` are pre-existing (moodle-install/sync.sh, Phase 0–1). Not
  committed, not staged.

### T17 — sentinel

- **Green path:** `sentinel-check` → exit 0 in **6.3 s**, `state/last-ok` refreshed, **no claude
  process spawned, no new row in `sentinel/logs/index.tsv`, $0 cost**. `pc status --check` green.
- **Bash-fixable fault** (`SENTINEL_STATUS_CMD` returning `services.docker: FAIL` once, then OK):
  log shows `FAIL: services.docker inactive` then `fixed by bash`, `last-ok` written, **no Claude
  run** (index.tsv row count unchanged).
- **Unfixable fault** (`disk.root: FAIL` always): `state/incident.json` written with
  `failures_before`/`failures_after`/full `status`, then `agent-run sentinel` invoked — captured
  with a temporary stub on `~/.local/bin/agent-run` so no real Claude run and no cost was incurred;
  the stub was restored to its symlink immediately (verified with `ls -l`).
- **flock:** with the lock held by another process, a second `sentinel-check` exits 0 immediately
  and does nothing. Escalation happens *inside* the lock, so a 20-min Claude repair blocks the
  next tick rather than stacking.
- **Timers:** `sentinel-check.timer` (OnBootSec=5min, OnUnitActiveSec=15min) and
  `agent@sentinel-digest.timer` (`*-*-* 08:00:00`) both enabled and active.
- **Digest** brief is read-only, one push ≤ 300 chars, `BUDGET_USD=0.50`, `TIMEOUT=900`.

### T18 — moodle-keeper

- `moodle-keep` → exit 0 in 10 s: `http 200`, `dump 440K …/5.2/2026-09-05.sql.gz`,
  **`restore ok (980 tables)`** (real restore into a scratch DB, then dropped), prune, logrotate,
  `disk 7% used, 416G free`.
- **Retention:** 20 synthetic dumps (`2026-08-01 … 2026-08-20`) + today's → after a run exactly
  **15 files remain**: the 14 newest non-monthly dumps plus **`2026-08-01.sql.gz` kept**, today's
  dump intact. Matches the design.
- **Prune safety:** only `docker image prune -f` and `docker builder prune -f`; grep for
  `--volumes` in `moodle-keep` → **0 hits**. Reclaimed 0 B (nothing dangling), no image of a
  running env touched.
- **Weekly on a dirty tree:** created `www/qa-scratch-file.txt` → `moodle-keep --weekly` printed
  `pull skipped (checkout dirty or no upstream)`, HEAD unchanged (`8ad9354`), no upgrade, no
  purge. Scratch file removed; `git status --porcelain` clean again.
- Site still answers: `http 200` on `http://moodle-lab.tail2ea32e.ts.net:8052/login/index.php`.
- Timers: `agent@moodle-keeper.timer` (04:30) and `moodle-keep-weekly.timer` (Sun 05:00) enabled.

### T19 — fleet docs

- `wc -l`: FLEET.md **60**, README.md **23**, RUNNER.md 39. `grep -c "pc status"` ≥ 1 in FLEET.md
  and AGENT-PREAMBLE.md (2 each).
- **AGENT-PREAMBLE is what `agent-run` injects**: the `bash -x` argv contains the file verbatim,
  and `diff <(sed -n '/^# Fleet contract/,$p' AGENT-PREAMBLE.md) FLEET.md` → **identical**.
- **Roster vs reality:** all five roster rows check out —
  `sentinel-check.timer` enabled/active, `agent@sentinel-digest.timer` enabled (08:00),
  `agent@moodle-keeper.timer` enabled (04:30), `moodle-keep-weekly.timer` enabled (Sun 05:00),
  `agent@hello.timer` disabled. No agent@ timer exists that is not in the roster; no roster row
  lacks a unit. `agent@sentinel` correctly absent from timers (documented as by design).
- **Rule consistency:** FLEET §5 does not contradict `~/.claude/CLAUDE.md` except for the
  explicitly owner-approved `moodle-keep` ff-only `git pull` (T18 §2) — a documented exception to
  "the user manages all git state personally", not a conflict introduced by T19. FLEET's
  "never `pkill -f`, use `killall`" and "never kill tmux `claude`" match the sentinel/keeper briefs.

### Cross-cutting

- `systemctl --user --failed` → **0 units** (after resetting the `agent@qa-echo` failure my own
  kill-switch test created).
- `bash -n` clean on `agent-run`, `agent-enable`, `agent-disable`, `agent-now`, `agents-status`,
  `agents-stop`, `sentinel-check`, `moodle-keep`; `py_compile` clean on `agents-log` and
  `audit-log.sh`; all executable (`audit-log.sh` 0755).
- Stray timers: none. The only user timers are the four fleet ones plus stock Ubuntu
  (`snap.firmware-updater`, `launchpadlib-cache-clean`, `ubuntu-insights-*`).
- `~/agents/log/actions.jsonl` 78 KB after ~4 h of Phase-3 work (≈ 265 lines). `logrotate -d`
  parses the config and reports the correct decision ("rotated at 20:00, less than a day ago");
  daily/rotate 30/compress/copytruncate. Rotation is driven only from `moodle-keep`, i.e. once a
  day at 04:30 — fine at this growth rate.

## Defects

| # | Sev | Ticket | Defect |
|---|---|---|---|
| D1 | **HIGH** | T15 | **`agents-stop` misses agents without a timer.** It iterates `~/.config/systemd/user/agent@*.timer.d`, so an agent started with `agent-now` (or any agent whose timer was never enabled) keeps running. Repro: `agent-now qa-echo` with no drop-in, `agents-stop` → unit still `activating`. Fix: enumerate running units instead — `systemctl --user list-units 'agent@*.service' --state=active` and stop each, then disable the timers. |
| D2 | **HIGH** | T15/T17 | **The kill switch does not stop the two bash timers.** `sentinel-check.timer` and `moodle-keep-weekly.timer` stay enabled and active after `agents-stop`; `sentinel-check` can then escalate and spawn a Claude run minutes after the owner hit the kill switch. FLEET §6 and README §3 claim "disables every timer / nothing runs again". Fix: add both units (or `systemctl --user stop timers.target`-scoped equivalent) to `agents-stop`, and an `agents-start` to bring the roster back. |
| D3 | **HIGH** | T16 | **Secret redaction misses Bearer tokens and JSON-quoted keys.** `Authorization: Bearer sk-ant-XXXX` logs the token verbatim (the regex consumes `Bearer` as the value); `"token": "sk-live-9999"` in an MCP input is not redacted (a `"` sits between the key and the `:`). Repro in §T16. Fix: add `bearer\s+` to the key alternation, allow `["']?\s*[:=]\s*["']?` between key and value, and add `sk-[A-Za-z0-9_-]{16,}` / `ghp_…` as standalone value patterns. |
| D4 | med | T15 | **Log files collide within the same minute.** `ts=$(date +%Y-%m-%d-%H%M)` — two runs in one minute write the same `.log`/`.json`, the second silently overwriting the first while `index.tsv` keeps both rows pointing at it (observed twice). Fix: `+%Y-%m-%d-%H%M%S`, or suffix on collision. |
| D5 | med | T15 | **A killed run leaves no trace.** When systemd/`agents-stop` SIGTERMs `agent-run`, no `index.tsv` row, no cost and no REPORT update are written (the unit just shows `failed`); on a `timeout` kill the cost column is empty because the JSON is truncated. Fix: `trap` EXIT in `agent-run` to write the row. Also: `REPORT.md` is rebuilt from its own previous content, so an agent that fails to overwrite it stacks the old metadata header on every run. |
| D6 | low | T15 | **`agent-run` has no lock of its own.** Concurrency is guaranteed only via systemd; two manual `agent-run <name>` calls would interleave in the same folder. Also `agent-run` does not redirect stdin, so a manual run wastes 3 s on "no stdin data received" (harmless under systemd). Fix: `flock` on `<dir>/.lock` and `< /dev/null`. |
| D7 | low | T16 | Hook latency **19 ms**, right at the ticket's ≤ 20 ms limit — one python3 start-up per tool call. Acceptable today; a slower load or a bigger `sys.path` pushes it over. Consider a tiny appender in C/shell or batching if it regresses. **D7b:** `agents-log --stats` counts `op` strings that embed the first argument, so nearly every entry is unique and the output is not a usable aggregate — group on the command basename only. |
| D8 | med | T17 | **No escalation cool-down: worst case ≈ $4/hour, ≈ $96/day.** `sentinel-check` runs every 15 min; a persistent unfixable fault escalates on *every* tick with `BUDGET_USD=1.00`, and nothing suppresses repeats (the flock only prevents overlap, and `TIMEOUT=1200` caps a single run to 20 min → 3–4 escalations/hour). Measured real sentinel runs cost $0.20–0.23, so a realistic loop is ≈ $0.9/h / $22/day — still unattended spend with no ceiling. Fix: record the last escalation + failure signature in `state/`, skip if the same signature escalated within N hours (e.g. 2 h) and push once instead. |
| D9 | low | T18 | **The weekly pull will silently never run once a plugin is checked out.** `git status --porcelain` on the core tree also reports *untracked* plugin directories under `www/public/<plugin>`, which is exactly the normal working state described in the ticket. Repro: an untracked file in `www` → `pull skipped (checkout dirty or no upstream)`. Fix: use `git status --porcelain --untracked-files=no`, or exclude the known plugin paths, and report *why* it skipped. |
| D10 | low | T19 | Doc-accuracy fallout of D1/D2: FLEET §6 ("`agents-stop` disables every timer, stops running units") and README §3 ("Nothing runs again until re-enabled") overstate what the kill switch does. Update the wording, or the code, together with D1/D2. |

## Cost and safety observations

1. **Scheduled cost floor is $0.** `sentinel-check` on a green machine is 6.3 s of bash, no Claude,
   no cost — PLAN §2.5 ("LLM on failure, not on schedule") holds in practice.
2. **Daily baseline** is the 08:00 digest (≤ $0.50) + the 04:30 keeper (≤ $2.00, typically $0.17–
   $0.20 since `moodle-keep` does the work in bash) ≈ **$0.40/day** observed, $2.50/day capped.
3. **The only unbounded path is D8** (repeating sentinel escalation). No per-day or per-agent
   spend ledger exists; `index.tsv` has the per-run cost, so a `agents-status --cost 24h` would
   close the gap cheaply.
4. Safety rails that held: tmux `claude` untouched by `agents-stop`; no orphan processes after a
   timeout kill; `MemoryMax=8G`/`Nice=5` on the template; no `--volumes` anywhere in the keeper;
   the weekly pull is `--ff-only` and refuses a dirty tree; nothing leaked into `~/moodle-harness`;
   nothing was committed or pushed.
5. QA generated two real pushes to the owner's phone (one `agent qa-echo failed (exit 124)`, one
   `kill switch: stopped …`) — expected side effects of the timeout and kill-switch tests.

## Not testable here

- End-to-end `mcp__*` audit logging (would need a live Playwright session; the desktop was in use
  by the T28a agent). The hook itself handles a synthetic MCP payload correctly.
- Real timer firing at 04:30 / 05:00 / 08:00 — verified only via `list-timers` next-elapse and
  manual `agent-now` runs.
- `sentinel-check` real fault repairs (`sudo systemctl start docker`, `sudo tailscale up`,
  `docker compose up -d`) were exercised only through `SENTINEL_STATUS_CMD` fault injection;
  stopping docker/tailscale/the Moodle stack for real is forbidden by the QA brief.
- `agent@.timer` `Persistent=` behaviour after a reboot (no reboots allowed).
- Whether `--max-budget-usd` is enforced on subscription (OAuth) billing rather than API billing:
  the flag is documented as "Maximum dollar amount to spend on API"; our $0.0001 test did abort the
  run, so it takes effect here, but the cap should not be assumed to be a hard money limit.

## Cleanup

`qa-echo` agent folder, its drop-in and its failed unit removed (`systemctl --user reset-failed`,
`daemon-reload`); the 21 synthetic audit lines (sessions `abcdef12`, `mcptest0`) stripped from
`actions.jsonl`; the fake `sentinel/state/incident.json` deleted and the two synthetic
`sentinel.log` lines removed so tomorrow's digest is not polluted; the 20 synthetic dump files
deleted; `www/qa-scratch-file.txt` removed; `/tmp/qa17` removed; `~/.local/bin/agent-run` restored
to its symlink; `agent@moodle-keeper` and `agent@sentinel-digest` timers re-enabled with their
original schedules after the kill-switch tests. Final state: `agents-status` shows the original
four agents, `systemctl --user --failed` empty, four fleet timers scheduled.
