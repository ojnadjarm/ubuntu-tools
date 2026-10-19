# Weekly code review of the fleet: find bugs, fix them, retire what is not useful (code-review swarm)

Ticket: T74 · Last verified: 2026-10-19 (T449: `bin/tests/run.sh` timed), 2026-10-15 (T347-02) and 2026-09-24 by `bin/tests/code-review.test.sh` 37/37 and the fixture selftest `code-review/selftest/run.sh` (harden run 2: oracle 16/16, 421 s, $8.02; effectiveness fixture: valuable tool kept)

## When to use
- Reading or changing the Saturday 03:00 `agent@code-review` run, its lanes, its rules, or what it may touch.
- A finding came back wrong, a fix needs undoing, or a retired tool is needed again (restore lines below).
- Running a one-off review of fleet code with the same safety (sandbox, backups, claims).
- Not for reviewing a diff or PR in a git repo: use the built-in `/code-review`. Not for planning new tools: toolsmith.

## The path we took
- Started from `research-swarm/template.js` (Workflow lanes with schemas), the `hello` agent folder, `agent-run`
  and pcbench's bwrap `exec.sh`. Architecture: `~/agent-work/research/2026-09-24/T74/architecture.md` (§10 = harden).
- Chain: timer → `agent-run code-review` → `agent-exec` → `adapters/claude/run` → `AGENT_WRAP`
  (`code-review-sandbox --post --`) → `claude -p BRIEF.md` → `code-review prep` → `Workflow(swarm.js, args.json)` →
  `result.json` → `code-review finish` → session exits → outside the sandbox: `code-review cleanup` + `code-review deliver`.
- **Allowlist sandbox**: `$HOME` read-only; writable only `~/agents` (real) or the fixture, `~/.claude/skills`, the
  session's projects dir, `backups/code-review` and `backups/retired`. Read-only again over them: `.git`, AGENTS.md,
  FLEET.md, research, backups, and everything `code-review containment` lists (the CLI, sandbox, netproxy, guards,
  runner, swarm files, its tests). tmpfs over secrets, asr-corpus, `.ssh`, `.gnupg`, gh config, keyrings,
  `/run/user/$UID`, `/tmp`; `/dev/null` over the docker and system D-Bus sockets; own pid namespace.
- **Network**: `--unshare-net`; `code-review-netproxy serve` (outside) tunnels CONNECT only to :443 of anthropic.com,
  claude.ai, claude.com; `relay` inside listens on 127.0.0.1:18474 and `HTTPS_PROXY` points there. GitHub, ssh, the Eye
  bridge and every LAN service are unreachable.
- Shims are bound over the real binaries (any PATH): systemctl, systemd-run, busctl, docker, notify-owner,
  plan-publish, eye; `pc` refuses only `--apply` and `undo`.
- Focus (T447): `prep` gives each area `focus` (files with mtime after the last finished run's prep, then a stable
  sha1 quarter of the rest) and `sweep`; every 4th finished run is a full sweep; a focused area with no files gets no lanes.
- `swarm.js`: areas × 5 lenses (real data, correctness, perf, **value**, replace) → dedup by key and by meaning against
  earlier findings (`seen_before`) → 2 refuters, a third only on a split or no answer (T433; removals get all 3 and need 3/3 and must answer "what would a future agent lose?";
  a failed refuter is no vote, retried once; if the missing votes could still flip it, the verdict is `unverified`, back next week)
  → per area, retire lanes first, then fix lanes, serial; a finding on an item retired this run becomes `deferred`.
- Fix lane: `claim` → `backup` → `tests <id> before` → failing test → fix → guide → `tests <id> after` → `unclaim`.
  A fix counts only if `tests … after` wrote `VERIFIED` (no new failure, nothing deleted outside `retire`);
  `finish` restores any "fixed" item without it and reports it `unverified`.
- **Usefulness, never usage counts**: `retire --why broken|duplicate|superseded|obsolete`; duplicate/superseded also
  need `--by <item>` and a side-by-side `--proof`; no references (units, crontabs, docs, code); not claimed.
- Output: `REPORT.md` 5 lines, `state/runs/<run>/findings.md` (secrets redacted), `outbox.json`; `deliver` publishes
  with `plan-publish` and sends one push per run (`pushed`/`delivered` markers).

## Exact commands
```bash
bash ~/agents/bin/tests/code-review.test.sh            # 46 fixture checks, no model, ~60 s (2026-09-24, 37 then); in the code-review sandbox the agents-stop/agents-start checks fail or skip (systemctl shimmed)
bash ~/agents/code-review/selftest/run.sh              # real swarm on the seeded fixture (model, ~6-10 min, ~$7-10)
code-review-sandbox --selftest                         # proves hidden secrets, read-only containment, Claude-only network
code-review restore <run> <F-id>                       # undo one fix; what it left goes to the backup's displaced/
cat ~/agents/backups/retired/<date>/MANIFEST.tsv       # col 3 = one-line restore (mv … …), col 4 = why
code-review retire <path> --why obsolete --check       # would the gates let it go?
agent-now code-review                                  # one real run now, through systemd (hours)
```

## Pitfalls (measured)
- T347-02 (2026-10-15): a test loop next to a live run re-created the fixed `state/sandbox/net/proxy.sock`; Verify got
  140/140 refuter failures, and null votes counted as refutations. Now each sandbox run has its own `state/sandbox/net.XXXX`,
  `netproxy serve` refuses to replace a live socket, the real-mode selftest skips while `code-review/.lock` is held,
  and the fix gate ignores `ok`/`PASS` lines that contain FAIL.
- The first build's denylist sandbox was escaped three ways (user D-Bus/systemd-run, the docker socket, ssh-agent +
  a GitHub remote on `~/agents`). Only an allowlist plus `--unshare-net` holds; keep new paths out of the writable set.
- `~/.claude` stays writable as a directory (auth refresh writes there); existing entries are read-only and new
  top-level entries are logged to `state/claude-new-entries.log` after each run. Detection only, not prevention.
- The audit log, `FILE-CLAIMS.md` and `code-review/state` are writable because the hook and the CLI write them;
  `policy` forbids lanes from editing them. A lane could forge `VERIFIED` only by a deliberate write.
- A retire lane that also backs up the item made `tests after` flag the deletion, and `cleanup` then restored the
  retired tool (harden selftest 1). Automatic restores and the deletion check now skip items retired and not brought back.
- The real `bin/tests/run.sh` runs 106 files 8 at a time: 420 s on 2026-10-19 at load 30, 23 red, 3 on the 170 s
  per-file timeout (code-review, pc-doctor, toolsmith-inputs); 567 s sequential before T445. Some red only under load
  (wait-nudge: red there, green alone). `tests` compares failures before and after with digits masked, under one lock across lanes.
- The effectiveness fixture's oracle checks some files byte-for-byte; a verified fix of a *different* real bug in
  that file (log-trim archives, stale-locks depth) shows as FAIL. Read the finding before calling it a false positive.
- Headless, the Workflow call returns at once with a run id: wait for the completion notification (BRIEF step 2).
- `claude -p` kills background tasks after 600 s by default (first real run, 2026-09-24: $38.69 for 10 min, found 0).
  `agent.env` exports `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=13500000` (under `TIMEOUT`) so the session waits for the swarm.
- A run can die on the account session limit (second real run, 2026-09-24 14:21: exit 1, 669 s, $37.55, log is only
  "You've hit your session limit · resets 3pm"). `finish` never runs; `cleanup`/`deliver` push a generic "run error"
  (found 0) that does not name the limit: read `logs/<run>.log`. Keep heavy interactive use off the Sat 03:00 slot.
- A run can also die on a dropped API connection (2026-10-15 13:42: exit 1, 3520 s, $30.75, found 0; log is only
  "API Error: Connection dropped (ECONNRESET)"). The push is the same generic "run error", so it can hide either
  cause: read `logs/<run>.log`. Before paying for a new run, try `resumeFromRunId` (`research-swarm-and-judge.md`);
  finished lanes come from cache. Untested for a headless run whose session died.
- Workflow lanes have no network to the Eye: they no longer appear as orbiters.
- Never SendMessage to a running workflow agent (see `research-swarm-and-judge.md`); steer by editing `LANES.md`.

## Links
- Code: `bin/code-review`, `bin/code-review-sandbox`, `bin/code-review-netproxy`,
  `code-review/{BRIEF.md,LANES.md,swarm.js,agent.env}`, `code-review/selftest/{build.py,template/,oracle.sh,run.sh}`
- Tests: `bin/tests/code-review.test.sh`, `bin/tests/agent-run.test.sh` (AGENT_WRAP), `code-review/selftest/run.sh`,
  effectiveness fixture `research/2026-09-24/T74/critic-eff/run.sh`
- Design / results: `~/agent-work/research/2026-09-24/T74/{architecture.md,build.md,critic-safety.md,critic-effectiveness.md}`; skill `/weekly-code-review`
