# Ubuntu OS survey: the machine numbers for an Ubuntu wave in one command

Ticket: T1115, T1130 · Last verified: 2026-10-21 by `bin/tests/os-survey.test.sh` (38 checks incl. 5 mutations, 0 failed) and live runs under `nice -n 19`: `--quick` 13/13 sections in 3.1 s, full 23/23 in 7.6 s (5 s of it the netdata sample, in parallel)

## When to use
An Ubuntu/OS wave planner needs measurements.txt: status, doctor, failures, CPU per unit, memory growth, timers,
kernel OOM/dmesg, journal lines per unit, fleet-ci verdict, agent error clusters, boot, disk, network, AppArmor,
agent-work writers, docker, transcript "command not found", caches, helper daemons, netdata cost, sudo commands,
journal sources, disk writes per cgroup. Waves 25-28 built this by hand (~35 min each).
Not for fleet/agent numbers (tests, tokens, flaky, shipped items): use `fleet-survey`. Not for diagnosing one item:
run the source command a row names.

## The path we took
- Existed: `fleet-survey` (fleet layer, not OS), the `pc` verbs each section calls. Chosen: one read-only Python CLI
  that calls them and reads files directly; no new collectors. From zero because no OS-level aggregate existed.
- Shape: `SECTIONS` = (name, quick, fn); `probe(label, argv, n/keep/tail/shape)` = one labelled block; `run()` is the only
  place a command starts (timeout `OS_SURVEY_TIMEOUT`, max 10 s; `OS_SURVEY_BIN` = the only command dir, the test seam).
  Each section fails soft to `n/a: <why>`; 4 threads; rows matching `vass|moodle45` end `(Vass, owner-only)`.
  A timeout kills the probe's whole process group. Footer `N/M sections clean` = sections with no `n/a` row at all.
- SOLID: one function per section; a new section is one function + one `SECTIONS` row; commands only via `run()`.

| section | source |
|---|---|
| status | `pc status --brief` + `pc status` WARN/FAIL rows |
| doctor / failures / cpu | `pc doctor --quick --brief` / `pc failures --since` / `pc units cost --all --since` top 12 |
| memory / timers | `pc mem growth -n 8`, `pc mem agents` / `pc timers --overlap` |
| kernel | `pc kernel oom` kills line, `pc kernel dmesg --digest --since -<since>` top 10 (journal, not the ring buffer) |
| journal | `journalctl --since -1h -o json` lines per unit top 10, `pc journal size` |
| fleet-ci | newest `~/agents/log/fleet-ci/*.txt`: verdict line, red file count |
| agents-log | `--errors --cluster --since` top 10, `--raw --since` |
| boot / disk / network | `systemd-analyze` + blame top 8 / `df /` `/tmp` + `pc docker disk` / `pc net wifi`, `pc net tailscale` |
| apparmor (full) | `journalctl -k -g 'apparmor="DENIED"'` by profile |
| agent-work (full) | os.walk: size, bytes written in since/6h/1h, top 5 writer dirs (6 h) |
| docker (full) | `pc docker stats` |
| command-not-found (full) | `rg -F` prefilter over every `*.jsonl` (recursive, < 7 d, batches of 1000), then JSON: only `tool_result` lines starting `bash: X: command not found`, one per tool_use id, skipping calls whose input has the text (T1146: claims 58 → 0, the 7 real ones predate its 10-18 link); names on PATH count only after the link's ctime (install time; mtime is the package build date: flake8 2026-01-12 vs dpkg 10-21), `(on PATH now since YYYY-MM-DD HH:MM UTC, N before)`; minus test-helper names, sbin tools total |
| caches (full) | `du -m --max-depth=1 ~/.cache` top 7 |
| daemons (full) | /proc cmdline per kind (`DAEMONS`, anchored on argv[0]/argv[1]: watchman, node playwright-mcp, node <mcp script>): count, VmRSS, inotify watches from fdinfo |
| netdata (full) | netdata.service cpu.stat over `OS_SURVEY_NETDATA_WAIT` (5 s) as s/h; top 5 threads of its cgroup.procs (ticks / age); `/api/v1/charts` per plugin (`NETDATA_URL`) |
| sudo (full) | `journalctl SYSLOG_IDENTIFIER=sudo --since` COMMAND basename top 8 |
| journal-sources (full) | `journalctl --user` and `--system` 1 h, lines by SYSLOG_IDENTIFIER (else _COMM) top 8 |
| io (full) | every cgroup io.stat wbytes: total of top-level, leaf cgroups top 8, gone = parent minus its children |

## Exact commands
```bash
os-survey --quick                 # 13 cheap sections, <= 15 s
nice -n 19 os-survey              # all 23 sections, <= 15 s
os-survey --since 6h              # window for failures, cpu, agents-log, apparmor, agent-work
nice -n 19 bash ~/agents/bin/tests/os-survey.test.sh
```

## Pitfalls (measured)
- Bytes written are not growth: agent-work 24 h "written" 7,690 MB while the 6 h window was 1.4 MB (nightly showcase rebuild + paused 3D). Read the 6 h and 1 h numbers; net growth needs a size history (T1102).
- `pc kernel dmesg` without `--since` is the ring buffer only (09:52-14:40 on 10-21); the survey passes `--since` so it reads the kernel journal.
- cgroup io.stat of a parent keeps the bytes of removed children: on 10-21 150 of 476 GB written since boot sat in gone cgroups (transient scopes, recreated containers), so the leaf top 8 never sums to the total.
- `user.slice` has no io controller below it here: it shows as one 257 GB leaf; per-session writes need `pc io`.
- sudo lines land in the user journal (`_UID` of the caller): 35,680 of 36,725 user lines in 1 h on 10-21 were sudo; `--system` alone misses them.
- `pc journal digest` groups by unit + message: 3 rows for an hour that had 5,991 lines; count `journalctl -o json` per unit instead.
- Subagent transcripts are nested: `*/*.jsonl` found 404 of 2,784 files; glob `**/*.jsonl` recursively. Count `bash: X: command not found` only (plain `X: command not found` matched more noise).
- The `bash:` prefix does not drop test noise: unexported test helpers print `bash: line N: ok: command not found`. On 10-21, 150 of 522 hits were helper names (`ok` 56, `is` 48, `has` 12); the CLI drops every function name defined in `bin/tests/*.sh` and prints `test helpers dropped N`. Placeholders such as `X` or `tp` still count.
- `journalctl -g` and `rg` exit 1 on zero matches: `run(..., nomatch_ok=True)` makes that an empty list, or a quiet window prints `n/a: rc 1:`.
- `subprocess.run(timeout=)` kills only the direct child: a `sleep | cat` grandchild held the pipe past the cap. `run()` starts a new session and kills the group.
- rg with every transcript as argv hits E2BIG at about 5x today's 2,793 paths: pass paths in batches.
- `du -s --max-depth=1` exits with an error (summarize vs depth) and prints nothing: use `du -m --max-depth=1`.
- `fwupdmgr get-remotes --json` (2.1.1) prints a text tree after the JSON: `jq` fails at line 64; use `json.JSONDecoder().raw_decode` (T1080).
- An unanchored `playwright-mcp` regex counted 4 on 10-21 where `ps` had 2: the long-lived bwrap sandboxes carry `--ro-bind /dev/null ~/.claude/playwright-mcp.json` in their args. Match argv[0]/argv[1] only (fixture pids 600, 700).
- The /proc and cgroup walks (daemons, io) stop at `OS_SURVEY_TIMEOUT` and mark the row `(partial: timeout N s)`, like agent-work.
- `pgrep -f <pattern>` inside a CHECK matches its own shell (T1084 red); use `pgrep -x` or a cgroup file.
- Full chromium-1243 `--headless --dump-dom about:blank` hung > 120 s; chrome-headless-shell answers in 0.08 s. This CLI never starts a browser (the test greps the source).
- New CLI in ~/agents/bin: link it (`~/agents/install.sh --links`) or live sessions get "command not found".

## Links
- Code: ~/agents/bin/os-survey
- Tests: `nice -n 19 bash ~/agents/bin/tests/os-survey.test.sh` (stub bin, fake AGENT_WORK/HARNESS_HOME/projects/cache, fake /proc and cgroup tree via OS_SURVEY_PROC/OS_SURVEY_CGROUP)
- Design / results: ~/agent-work/research/2026-10-21/T1100/BACKLOG.md #15, ~/agent-work/research/2026-10-21/T1100/measurements.txt
