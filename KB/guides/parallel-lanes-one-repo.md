# Parallel lanes in one repo or one live env: lock, copies, scratch, notes fold, deploy order

Ticket: T1405 (from the Mooblox night run T1364/T1371-T1375 and play-test lanes T1379-T1403) · Last verified: 2026-10-27 by the
`flock` + `quiet-gate` one-liner below (quiet rc 0 ran the command, busy rc 3 skipped it), and by evidence from night/PLAN.md and the Mooblox `git log`

## When to use
Two or more agents change the same repo, share one perf measurement, or deploy into the same live env (a Moodle site, a
`~/drop` page, a served dist). Typical cases: a night run with lanes (art, perf, motion, load, assets), or play-test fix lanes.
Not for one agent alone, and not for file ownership as such (that is `claims`, guide file-claims).

## The path we took
- **Lanes by file area.** Each lane claims only the folders it edits (`claims add T<n> <paths>`). T1371 first claimed all of `client/src`
  and had to narrow it.
- **One common-rules file** that every lane brief names (Mooblox: `~/agent-work/briefs/T1276-mooblox-common.md`). New rules are
  appended there once, with the time they were added.
- **Shared tree = only committed work.** Commit small and often. A/B runs and perf runs happen in a clean copy or `git worktree` of
  HEAD plus your own diff, never by swapping files in the shared tree.
- **Ignored dirs in worktrees are copied, never symlinked.** A symlink to an ignored dir gets committed, and a squash merge then
  deletes the real dir (quirks.md, T1395).
- **Per-ticket scratch:** `<scratchpad>/T<n>/`, never the scratchpad root. Agents share the root.
- **One measurement at a time:** one lock file per project. Every hold has a timeout, and the load check runs inside the lock, using
  the existing `quiet-gate`. Do not write a sleep loop; a hook blocks it.
- **Notes per lane** (`research/<date>/T<n>/ROUNDS.md`). The repo CLAUDE.md is not claimed by any lane; one wrap agent folds all
  lanes into it at the end, rebuilds dist from a clean HEAD, and runs the tests once (T1375).
- **One live env, one deployer at a time.** Deploy only a committed HEAD. Read the live version first; your version must be higher.
  Bump it, deploy, then read it back.

## Exact commands
```bash
claims add T<n> "<repo>/client/src/world/props <repo>/client/test/world/props"   # narrow paths, not the whole src
S=<scratchpad>/T<n>; mkdir -p "$S"                                                # own scratch subfolder
git -C <repo> worktree add "$S/wt" HEAD && cp -r <repo>/.research "$S/wt/"        # copy ignored dirs, never ln -s
# one measurement at a time; load checked after the lock is held; 900 s cap per hold
flock /tmp/<project>-perf.lock timeout 900 bash -c \
  'quiet-gate --max-load1 8 --wait 1800 && echo "load $(cut -d" " -f1 /proc/loadavg)" && npm run test:perf'
# A/B: >= 3 alternating pairs (base, mine, base, mine, ...), compare medians; log load at each run's start
# deploy to a shared Moodle env: read the live version, bump past it, deploy from HEAD, read back
grep -o "[0-9]\{10\}" <repo>/moodle/local/<plugin>/version.php | head -1      # yours
~/.claude/skills/moodle-ci/scripts/mdb --env 5.2 "select value from {config_plugins} where plugin = ? and name = 'version'" local_<plugin>   # live
```

## Pitfalls (measured)
- **Shared-tree WIP hangs other lanes' perf runs.** An uncommitted chunk-weld change failed with "Cannot read properties of null
  (reading 'byteLength')", and 2 hung runs held the lock for 35 min (night 07:03). Fix: run A/B in a copy, and put a timeout on
  every hold.
- **An old asset swapped into the shared tree for A/B** (kit.glb) sat there for 20 min while another lane measured (night 02:24).
- **Scratchpad root clash.** Lane A overwrote lane D's `page.py` and regenerated D's drop page (night 23:37).
- **The load check must run inside the lock.** Checked before the queue, stress runs started at load 3-14 and the numbers were noise
  (night 17:23).
- **Single perf runs lie.**
  - One stress run swings 29-51 fps.
  - Art round 12 was reverted for a "halved fps" that a 3-pair A/B showed was noise; it was re-landed in round 13.
  - The perf lane (D) spent 4 rounds (r10-r14) on a one-time cold SwiftShader stall (cold 283-300 ms vs warm 50 ms). Report the
    cold first visit as its own non-gating metric.
- **The lock queue becomes the bottleneck.**
  - The queue grew 5 deep: 6 runs took 63 min.
  - One lane's round took 130 min, of which about 20 min per run was lock wait.
  - Run the gate only for engine changes (`change-class`, guide change-tiers): 19 of 28 gate runs (12.6 min each) were in
    tickets with no engine file.
- **Polling the lock** every few seconds (T1373) wastes turns: make one foreground `flock` call.
- **Deploy order.** T1394 synced the plugin folder at version 2026102614 over T1393's uncommitted 2026102613. T1393 had to rebase,
  bump past it and redeploy. The last sync wins silently.
- **Load and reboots.** At load 15/16 cores the orchestrator paused one lane; the 04:10 auto-reboot killed 4 lanes mid-round. Lanes
  that commit small lose little: the relaunched agents kept the killed agents' diffs.
- **A round that measures no better is not committed.** P r13 and r14 ended with "NO commit" (r14 cut tris 51k → 41k but raised
  high-tier crossing frames 2 → 6). That kept HEAD clean.

## Links
- Rules file: `~/agent-work/briefs/T1276-mooblox-common.md` (night-run sections)
- Log: `~/agent-work/research/2026-10-24/night/PLAN.md` (one line per handback, the rule each incident added)
- Postmortem: `~/agent-work/research/2026-10-27/T1405/POSTMORTEM.md`
- Related guides: file-claims, change-tiers, wait-for-and-stuck-loops; quirks.md (`.research` symlink, T1395)
