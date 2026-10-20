# Runaway processes the sentinel kills, and forgotten headless browsers

Ticket: T113, T114, T115 (rules 1-5: EF03, T67, TSP-016) · Last verified: 2026-10-20 (T846: `--help`, paths, env knobs, thresholds 50 %/1800 s/2 strikes, 15-min timer read); 2026-10-15 by `sentinel-runaway.test.sh` (63 checks, 8 for rule 6, 4 for the rule-3 read-back, 10 for rule 4), `sentinel-check.test.sh`; real `sentinel-runaway --dry-run` last run 2026-09-26 (0.12 s, no rule-3 or rule-6 line)

## When to use
- A process burned CPU or memory for hours and the sentinel did not catch it: add or tune a rule in `bin/sentinel-runaway`.
- Reading a `runaway killed|would kill|restarted` line in `~/agents/sentinel/state/sentinel.log`.
- Not for stuck `until/while … sleep` wait loops: that is `sentinel-waits` (guide `wait-for-and-stuck-loops`).

## The path we took
- `sentinel-runaway` runs every 15 min from `sentinel-check`. One pass over `/proc`, no per-process forks; per-pid CPU
  samples in `state/runaway.tsv` give each process a `pct` (% of one core since the last run).
- Rules: legacy kill-list and (4) portal/gsd restarts at >= 90% for 2 runs; (1) orphan scratchpad sleep loops; (2) capture
  commands with no reader; (3) hand-run Dark Eye bodies; (5) dead sessions' scratchpads; (6) idle hot Chrome trees.
- Rule 2 (F10): stdout `pipe:[N]` with no other holder, or an absolute path that no longer exists, marks a capture orphaned.
  `socket:[N]` and `anon_inode:` stdout are never judged (a socket's peer has its own inode; a dead peer gives SIGPIPE).
- Rule 4 (F07): the unit is the last `*.service` under `user@N.service` in `/proc/<pid>/cgroup`, never `<comm>.service`
  (gsd-power runs as `org.gnome.SettingsDaemon.Power.service`). A refused restart (gsd units set `RefuseManualStop=true`)
  is logged `could not restart <unit> … left running`; only a helper in no user unit is killed instead.
- Rule 5 (F02): a scratchpad is wiped when its newest file (not the dir's mtime) is > 24 h old and the session is not
  live. Live = a process argv or claude fd names the uuid, or `~/.claude/projects/*/<uuid>.jsonl` changed within 24 h,
  or the uuid is among the k newest transcripts of its project dir (`/tmp/claude-1000/<slug>/`), k = claude processes
  whose cwd is that project dir or below it (`SENTINEL_RUNAWAY_PROJECTS` overrides the root in fixtures).
- Rule 3 (T114): a body carrying `DARK_EYE_SANDBOX=<name>` gets `body-sandbox down --name <name>` once per run, then each
  body pid is read back in `/proc`. `down` exits 0 on a pid it cannot see, so a survivor is logged `failed to take down
  sandbox <name>: pid N survived` and killed by pid (`stop_pid 3`). "took down" is logged only when the pid is gone.
- Rule 6 (T113): any process whose argv[0] is `chrome`/`chromium`/`headless_shell` is a Chrome process; the one without
  `--type=` is the browser root. Children's `pct` is summed onto the root by walking `ppid` (renderers and the
  `--type=gpu-process` sit 2-3 levels down). Tree >= 50% of a core on 2 consecutive runs (strikes in
  `state/runaway-browsers.tsv`) and no `mcp__playwright__*` tool call in `~/agents/log/actions.jsonl` for 30 min → TERM the
  root (KILL after 10 s). `playwright-mcp` stays up; its backend drops a disconnected browser and the next tool call relaunches it.
- Why these signals: a static page idles at 0-2% of a core, the leak ran 100-165%, so 50% has margin both ways; 2 runs is
  the same ~30 min the other CPU rules wait. The actions log is the only record of a Playwright MCP call; it is read
  (`tac | grep -m1`) only when a tree already has 2 strikes, so a quiet box pays nothing. It is global, not per session: a
  call from any session spares every browser, which errs toward sparing.

## Exact commands
```bash
sentinel-runaway --dry-run                               # print "would …" lines to stdout, kill nothing, write no state
SENTINEL_RUNAWAY_DRYRULES=6 sentinel-runaway             # rule 6 log-only, the others live; logs to sentinel.log, updates runaway*.tsv
bash ~/agents/bin/tests/sentinel-runaway.test.sh         # fake /proc + fake actions log + pinned clock, ~1 s
bash ~/agents/bin/tests/sentinel-check.test.sh
grep 'rule6' ~/agents/sentinel/state/sentinel.log        # past browser closes
```

## Pitfalls (measured)
- 2026-09-26: the orchestrator's headless Chrome sat 2.5 days on a WebGL lesson page. SwiftShader drew WebGL on the CPU at
  100-165% of a core; the box idled at 11% CPU instead of 1%. No rule matched Chrome before rule 6.
- The CPU is in the gpu-process grandchild, not the root: a per-process rule on the root would never fire.
- A Chrome driven by a node script (not the MCP) logs no Playwright tool call: if it stays >= 50% for 30 min it is closed too.
- Cheapest prevention: `browser_close` at the end of every browser task (`/browser` skill, working rules).
- Fixtures use pids above `pid_max` so the non-dry baseline ticks cannot signal a real process (FLEET §5.6).

- 2026-09-22 → 09-26 (T114): an orphaned sandbox `eye-render` (`asr`, its node parent dead, reparented to `systemd --user`,
  sandbox dir already removed) was "taken down" 397 times over 101 h. `body-sandbox down` kills only the pid in `body.pid`
  and that pid's direct children, so with no dir it does nothing and exits 0; rule 3 trusted the exit code.
- `SENTINEL_RUNAWAY_DRYRULES=legacy,1,2,4,5,6 sentinel-runaway` runs rule 3 alone live: the way to reap one stale sandbox now.
- 2026-09-26 (T115): strike fixtures (rules 4 and 6) flaked ~1 run in 5-20. The test wrote `/proc/uptime` from one `date`, the
  script read `now` from a second one; a second boundary between them moved `boot_epoch`, so the `pid:start` key changed
  and the strike history was lost. Fix: `SENTINEL_RUNAWAY_NOW=<epoch>` pins the script's clock; `sync_uptime <epoch>` in the
  test writes the matching uptime, and ticks run 900 s apart on that clock with no `sleep`. New fixtures must pass it too.

- 2026-10-03 (F07): rule 4 restarted `gsd-<x>.service`, which does not exist, then SIGTERMed the helper; its unit has
  `Restart=on-failure`, so the helper stayed down. No gsd hit in sentinel.log yet; a fixture with a `systemctl` stub proves it.

- 2026-09-30 and 10-02 (F02): rule 5 wiped the live orchestrator's scratchpad twice as a "dead session". It runs
  `claude --continue`, so the uuid is in no argv, and the dir's mtime stayed old while files inside were written.
- 2026-10-07 13:40 and 10-08 (F02 again): the 10-03 fix still wiped it after the orchestrator idled > 24 h (transcript
  silent 10-06 11:36Z → 10-07 15:14Z, same process). Fix 10-10: the newest-transcript-per-running-claude check above.

## Links
- Code: `~/agents/bin/sentinel-runaway`, called by `~/agents/bin/sentinel-check`
- Tests: `~/agents/bin/tests/sentinel-runaway.test.sh`, `~/agents/bin/tests/sentinel-check.test.sh`
- State: `~/agents/sentinel/state/{sentinel.log,runaway.tsv,runaway-browsers.tsv}` (the last exists only while a Chrome tree has strikes; 0 `rule6` lines on 2026-10-20) · Toolbox: `KB/toolbox.md` item 10
