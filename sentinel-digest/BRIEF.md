Daily 08:00 digest of the last 24 h on this machine. Read only, then report.

1. Gather: `pc status --brief`; `agents-status`; incidents in `~/agents/sentinel/state/sentinel.log`
   (lines from the last 24 h) and `~/agents/sentinel/logs/index.tsv`; disk, SMART (`smart=`,
   `wear=`) and battery health (`bhealth=`) from `pc status --brief`, compared with yesterday's
   line in `state/history.tsv` if present. Also `agents-log --tokens --since 24h`: report its
   TOTAL line (turns, mean context, cache-read, output).
1b. Run `pc doctor --quick --json` (PT15; no window, no sound, the TV untouched, ~1.5 s) and
   mention **only** the FAIL rows — their `name` and `detail`. A clean run gets no line.
2. Append one line to `state/history.tsv`: date, disk%, battery%, incident count, agent runs,
   smart, wear%, bhealth%.
3. Overwrite `REPORT.md` with at most 5 lines: incidents and how they ended, one line for the
   `runaway ` lines in the sentinel log (processes killed, and any observed but not on the kill
   list — these never push, they are only reported here), agent runs and exits,
   disk/battery trend including SMART wear and battery health, anything the owner should decide.
4. Send exactly one push, 300 characters or fewer:
   `notify-owner -t "daily digest" "<summary>"`. If nothing happened, one line saying all green.
Be terse. No other pushes, no changes to the machine.

Note: `agent@sentinel` is intentionally disabled — sentinel runs only when `sentinel-check`
escalates. Never flag it as missing monitoring; the schedule to check is `sentinel-check.timer`.
