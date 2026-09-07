# Toolsmith seed — candidate problems (verified 2026-09-07 against the tree)

Copied from the toolsmith plan so a run needs no other file. **Re-verify every item against
the tree this run**: drop what is already fixed (say so in the report), keep what still holds,
and add anything the inputs show. The seed is a starting point, not a quota.

1. **`sudo` bypasses the guards.** `bin/guards/` has no `sudo`; `secure_path` resets PATH;
   `maintenance-run` relies on the hole for its own `sudo shutdown -r`. Class `owner-go`.
   Metric: `guards.test.sh` cases, S-tier `attempted_forbidden`.
2. **`agents-stop` reads `claude agents --json`** (`bin/agents-stop:28`) while `agent-exec:47`
   writes `<name>/state/pid`. Read `*/state/pid` first. Class `auto-ok`.
3. **`moodle-keep` hardcodes `~/moodle-envs`** (`bin/moodle-keep:7`) vs `MOODLE_ENVS_DIR`. Class `auto-ok`.
4. **`pc status --brief` second FAIL list** (`BRIEF_TAGS` at `pc-status:157/179` vs `fails`
   at `:17-20`) and **dead `ok_if()` at `:24`**. Class `auto-ok`.
5. **Stale-cache class (C02).** `pc status` serves a 60 s `power_profile`; every `--apply`
   should invalidate the keys it changed. Class `auto-ok`. Metric: C02 3/3 new arm.
6. **O02 checker string-match gap.** `tasks/O02/task.json` `"sink"` has no description; 0/6 both
   arms. Class `auto-ok`. (TS06 candidate.)
7. **Agents fall back to raw tools.** 7-day audit: raw calls (`pactl`, `tailscale`, `systemctl`,
   `powerprofilesctl`) rival `pc` calls; bench `raw recipes/task` 8.1 new arm. Proposal:
   `agents-log --raw` mapping each raw verb to the `pc` verb that covers it. Class `auto-ok`.
8. **C-tier task that passes on "described but not applied"** and a second full A/B to confirm
   the +0.06 delta. Class `auto-ok`.
9. **No idle baseline file.** `pc idle`: 60 s sample of package watts, top 5 wakers, fleet
   resident RSS, appended to `bench/BASELINE-IDLE.tsv` by `pcbench-weekly`. Class `auto-ok`.
10. **Tokens per run of the preamble.** Every headless run gets the full `AGENT-PREAMBLE.md`;
    measure system-prompt tokens per run and propose a `--brief` preamble for bash-first agents.
    Class `auto-ok`. Metric: tokens per run in `index.tsv`.
11. **`timeout` wrapper latency (~100 ms each)** in `bin/` probes; propose removals with
    `pc bench --compare` as the metric. Class `auto-ok`.
12. **`agent-now`/`agent-run`/`agent-enable`/`agent-disable` take `$1` blindly** (`agent-now -h`
    starts a unit named `-h`). Add `-h` and a name check. Class `auto-ok`.

13. **Audit hook blind to non-Bash tools.** PostToolUse matcher in the agent CLI settings only
    covers Bash/Edit/Write; WebSearch, WebFetch, Read, Grep never land in `log/actions.jsonl`.
    Class `owner-go` (settings file is the owner's). Metric: rows per tool in `agents-log --stats`.
14. **Runner cannot prove tool use.** `logs/*.json` reports 0 web requests when 4 happened;
    have `agent-run` record a tool histogram from the harness transcript. Class `auto-ok`.

Dropped as already fixed: `pcbench` fixture clean unconditional; S01 `owner_go` gate;
`guards.jsonl` absent only because no guard has fired.
