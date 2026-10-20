# Prove install.sh / uninstall.sh on a fresh machine (Ubuntu container with systemd)

Ticket: T456, T474, T477, T507, T568, T587, T614, T623, T672, T692 · Last verified: 2026-10-20 by T846 audit (paths, `--help` flags, line refs, `git status`); 2026-10-19 by `bin/tests/install-fresh.sh` (PASS ubuntu:24.04 + 26.04, 25 s warm)

## When to use
After changing install.sh, uninstall.sh, units/, adapters/*/install or anything a fresh box needs. Not for the
`--links` step alone (`bin/tests/bin-links.test.sh` is faster).

## The path we took
- Existing: install.sh had only run on this box; piece tests (bin-links, no-machine-values). Chosen: a Docker
  image per Ubuntu release with systemd as PID 1 and a lingering random user `fx<6 hex>` (no systemd-in-docker image
  needed: 10-line Dockerfile on the official `ubuntu:<ver>` base).
- Sandbox: `--network none`, no bind mounts, not privileged; `--cap-add SYS_ADMIN` + `apparmor=unconfined` only
  so the entrypoint can remount the *private* cgroup namespace rw. The test asserts `none 0 false` from
  `docker inspect` and that the host `~/.local/bin` and `~/.config/systemd/user` are unchanged.
- Input: the working-tree copy of `git ls-files` (what a clone would have, plus uncommitted edits) and
  `fixtures/install-fresh/config.env` (placeholders, `HARNESS_AGENT=claude` to exercise the adapter).
- Input also takes untracked `units/` files (a clone lacks them until the owner `git add`s them).
- Checks: install.sh exit 0, units enabled, every `units/` file in `systemctl --user list-unit-files` (prints
  `units/: N, missing: []`), the fragment's hooks in `~/.claude/settings.json`, `harness context`,
  `pc status --brief` rc 0, `pc status --json`, `guide wait`; uninstall.sh keeps `claude-orchestrator.service`,
  `uninstall.sh --with-orchestrator` then leaves 0 links into ~/agents and 0 files under ~/.config/systemd/user.

## Exact commands
```bash
bash ~/agents/bin/tests/install-fresh.sh            # both releases; last line PASS/FAIL
bash ~/agents/bin/tests/install-fresh.sh 26.04      # one release
~/agents/install.sh --plan [--links|--test-deps|--gamedev]   # no container, writes nothing: `would: apt|link|unit|config|vcpkg|venv <what>`, last line `plan: N changes` (= a real run's count; bin/tests/install-plan.test.sh; adapters not planned)
SUITE_OUT=~/agent-work/evidence/<T>/fresh-suite.txt bash ~/agents/bin/tests/install-fresh.sh --suite --skills 24.04 26.04   # + run.sh -j 4 --skills in each box -> fresh-suite-<ver>.txt
bash ~/agents/bin/tests/run.sh --portable                # host suite minus `# host-only` files
```
Image build needs network once (apt); the containers never have one. Images `install-fresh:<ver>` stay cached
(~0.7 GB both); `docker rmi install-fresh:24.04 install-fresh:26.04` to reclaim.

## Pitfalls (measured)
- systemd exits silently without the cgroup remount ("Failed to create /init.scope control group: Read-only file
  system"); `--cap-add SYS_ADMIN` alone is not enough, the docker-default AppArmor profile blocks the remount.
- `systemctl is-system-running --wait` right after `docker run` fails with "Failed to connect to bus"; poll until
  `running|degraded`.
- `docker exec` sets no USER: pc-status died on `USER: unbound variable`; it now defaults `USER` to `id -un` (pc-status:130) and the test still passes USER like a login does.
- install.sh used to exit with `pc doctor --quick`'s code (1 on any headless box); now an advisory line.
- uninstall.sh left `agent@<name>.service.d/timeout.conf` (written by install.sh for UNIT_TIMEOUT); now removed.
- Untracked files a fresh clone lacks: bin/moodlelib.sh and bin/claims are tracked since; 102 `??` paths remain (2026-10-20),
  e.g. bin/quiet-gate, bin/pc-crashes, bin/tests/lib/, bin/tests/host-only.txt, 12 of 30 `units/` files; the owner must `git add` them. The test prints such `line N:` errors.
- KEEPALIVE_UNITS now defaults to empty (pc-status:197; set it in config.env), so a fresh box reports no `ka_*` rows.
- A config.env value with a space must be quoted (it is sourced by bash).
- uninstall.sh disables every `units/` file; without `--with-orchestrator` it skips `claude-orchestrator.service`
  so it never stops the orchestrator session (AGENTS.md §5.2). Never run uninstall.sh on the host.
- On 26.04 install prints `could not enable claude-orchestrator.service` (no nm-online/claude/tmux in the
  image); the file is installed and enabled, only the start fails. Expected.
- Not in `units/` by decision (T474): `moodle52-cron`, `moodle45-cron` (per-env: hard-coded container names,
  4.5 is Vass).
- `orchestrator-pulse` and `pulse-5h-reset` ship in `units/` since T477 (ExecStart sources env.sh, no `bash -l`).
  install.sh never enables a unit named in `UNITS_OFF` (default `orchestrator-pulse.timer`, off by owner 2026-10-18);
  the test asserts `enabled disabled` for the two timers.

## Second run and the suite in the box (T507, 2026-10-19)
- Every run also re-runs install.sh and asserts `second install: 0 change(s) applied, EXIT=0` (it was already a no-op).
- `--suite` runs `bin/tests/run.sh -j 4` in the first release's container after the second install; the red list
  (`FAIL <file> <s>`, tagged ` host-only` when the file has the header) goes to `$SUITE_OUT`, the raw log beside it.
- 24.04 measured: 32/114 green; 10 reds host-only by design (`# host-only: <why>` in line 2; `run.sh --portable` skips
  them), 33 missing a dependency (21 pytest + 4 node in dashboard/tests, then bwrap, tmux, gcc, column, curl,
  /usr/bin/time), 39 need a fixture (systemctl/pc shim selftests, env such as AGENT_SCRATCH_GLOBS, fleet user name
  colliding with no-person-hardcoded). pc-power.test.sh is host-only too (header not added: T500 held it).
- T528: `--suite` starts the container on the bridge, runs `install.sh --test-deps` as root (apt: DEPS.tsv level `test` + the
  `# test-also:` tools), then `docker network disconnect` before install.sh; container user `fx<6 hex>` per run and `fixtures/install-fresh/` not shipped (no-person-hardcoded greps the tree for user, host, owner). Measured 24.04: 74/114 green, 0 missing-tool lines.
- Untracked `bin/tests/lib/` and `bin/tests/fixtures/` ship into the box: without them 6 more files die on
  `ok/nok/is/budget: command not found` (owner must `git add` them, as for units/).

## Host-only skips and Node 22 (T568, 2026-10-19)
- `--suite` runs `FLEET_FRESH=1 run.sh -j 4`; FLEET_FRESH=1 (= `--portable`) prints `SKIP host-only <file>` for files in
  `bin/tests/host-only.txt` (12 desktop/hardware tests) or tagged `# host-only`, and counts them as ok in `N/M`.
- The box gets the latest `node <N>.x` from nodejs.org (N: DEPS.tsv node row, 5th field), sha256 checked against
  SHASUMS256.txt on the host, cached in `~/.cache/install-fresh/`, streamed with `tar | docker cp -` (plain `docker cp`
  of the dir fails on the `bin/corepack` symlink). Installed before `--test-deps`, so apt skips nodejs/npm.
- Untracked `bin/tests/host-only.txt` must ship (first run missed it: 94/114). Measured 24.04: 104/114, 20 SKIP.
- run.sh's OOM probe checks `memory.events` exists first (container user scopes lack it): 0 grep lines.

## Owner-data skips and Playwright in the box (T587, 2026-10-19)
- `--suite` installs the DEPS.tsv `test` rows `npm:<pkg>` (npm -g, version + sha512 logged) and `playwright:<browser>`
  (`playwright-core install-deps` as root, `install` as the user) while the box is on the bridge. Measured 24.04: 111/114.
- docker `--tmpfs /tmp` is noexec, so run.sh puts TMPDIR under `/run/user/<uid>`; a test whose bwrap mounts `--tmpfs /run`
  hides its own `mktemp -d` dir unless it binds it back (maintenance-run.test.sh).
- Tests needing gitignored or untracked files print `SKIP owner data absent: <path>` (pcbench: bench/arms; pcbench-weekly:
  KB/orchestrator.md, bench/BASELINE-IDLE.tsv; pc-explain: untracked bin/pc-crashes; sentinel-check: untracked bin/compose-services).

## Every release, skill tests, reasons (T614, 2026-10-19)
- `--suite` now runs in every listed release; red list per release in `${SUITE_OUT%.txt}-<ver>.txt` (line 1 the run.sh
  summary, with `--skills` line 2 `skills N/M pass-or-skip`). `--skills` ships the untracked `skills/` (the claude adapter
  links them into ~/.claude/skills) and runs `run.sh --skills` (docker shimmed). Moodle-harness skills are another repo: not in the box.
- `host-only.txt` lines take a reason: `<path>  # <why>`; run.sh prints `SKIP host-only <file> (<why>)`. Skill rows: Blender
  EEVEE (mv-camera, mv-logo, mv-render-blender), Blender + ~/opt/gamedev tools (asset-*), vcpkg + GPU (cpp-crash, cpp-golden),
  essentia venv (mv-beats).
- Untracked `bin/quiet-gate` broke 3 bin tests (ci-window, ci-autofix, fleet-ci-daily) and 4 gamedev tests (cpp-ci, cpp-vram,
  game-ci, perfgate: their load gate); it ships now, the owner must `git add` it.
- Skill tests needed numpy, unzip, clang-tidy (now in `# test-also:`) and `zip` (new `test` row).

## Self-skips and vmaf in the box (T623, 2026-10-19)
- A test whose tool is not apt and absent prints `SKIP needs <tool> ...` and skips only the cases that need it, never a
  silent green: mv-quality (vmaf CLI at `${MV_VMAF:-~/.local/opt/mv-quality/vmaf}`), mv-mix-fit `--fit bars` cases
  (essentia venv `${MV_BEATS_VENV:-~/.local/opt/mv-beats}`; cp314 wheels, so no 24.04), game-ci T543 budget cases (`ktx`,
  KTX-Software; Ubuntu ffmpeg's own vmaf is only `vmafmotion`).
- Shipping the host vmaf CLI into the box was tried: mv-quality then ran for real but hit the 170 s run.sh timeout at
  host load 39 (vmaf drops to 1 thread under load) on both releases, so the box SKIPs it instead.
- host-only.txt += cpp-pbr, cpp-play, cpp-vram (vcpkg + Iris Xe), mv-look, mv-film, mv-render-speed (Blender EEVEE/Cycles).
- Measured before the last host-only rows (load 30-39): 24.04 136/144, 26.04 137/146; the suite grows as parallel tickets add files.

## Fleet-test fixes and the M-3 bar (T672, 2026-10-19)
- Bar: `N >= M - 3` on the run.sh total (the suite grows as parallel tickets add files; a fixed `/141` regex drifted). Measured 26.04: 162/165 in 138 s (reds: ailearning-ci-daily off limits, cpp-ci mid-edit by T673, code-review).
- run-sh: the 4 over-cap oom cases need `memory.max` in a `--user --scope`; the box has none, the test SKIPs them.
- sleep-loop-block: an absolute 15 ms p50 failed on the host too; it now asserts the median hook-minus-bare-`python3 -IS` gap over 10 back-to-back pairs (<= budget(6 ms)).
- code-review: selftest/build.py makedirs the empty template dirs (git ships no empty dir); roster case falls back to a fixture row without KB/orchestrator.md; both sandbox selftests SKIP when api.anthropic.com gives http 000 (`--network none`).
- tmux in tests: run.sh's nested per-file TMPDIR makes `$WORK/tmux/tmux-UID/default` > 108 bytes; keep TMUX_TMPDIR in a short `mktemp -d /tmp/tmx.XXXXXX`.
- host-only.txt += 14 skill tests (vcpkg Vulkan builds, Blender EEVEE); mv-report SKIPs its VMAF lane without the vmaf CLI.

- `bin/DEPS.tsv` (tool, apt package(s), verbs, required|advisory) is the one list. install.sh step 1 reads it and
  prints `MISSING required`, `missing advisory (N)`, `not from apt` and one `sudo apt install …` line; it never runs apt
  and exits 1 only on a required tool (python3, jq, systemctl).
- `bin/tests/deps-manifest.test.sh` fails when a command called in bin/* is in neither DEPS.tsv nor a base package
  (`BASE` in `bin/tests/lib/deps_scan.py`: coreutils, grep, sed, procps, util-linux, …). Regenerate a row's verbs with
  `python3 ~/agents/bin/tests/lib/deps_scan.py ~/agents/bin`.
- T521 (2026-10-19): levels are now required|advisory|test|optional:media|optional:gamedev (strongest use wins), and the
  scanner also reads bin/tests, dashboard/tests, hooks tests and the motion-video + gamedev skill scripts
  (`deps_scan.py <dir|file>...`, `python3 -m <mod>` counts). Non-apt tools carry a `# hint` line. install.sh still
  treats every non-required level as advisory until it prints the groups (wave 7 #9).
- Scanner limits (measured): it sees commands in command position (line start, after `| ; && $( (`, after `sudo`/
  `timeout`/`pc_cmd`), `bash -c '…'` scripts, Python `subprocess` lists and third-party imports; a command held in a
  variable (`$P play`) or only named in a string is not counted. Only tools on PATH(+sbin) are resolved.
- Package names checked with `apt-cache show`: all 62 exist on 26.04; on 24.04 `localsearch` and `tinysparql` do
  not (24.04 ships tracker3), so drop those two from the apt line there.

## Links
- Code: ~/agents/install.sh, ~/agents/uninstall.sh
- Tests: ~/agents/bin/tests/install-fresh.sh, fixtures in ~/agents/bin/tests/fixtures/install-fresh/

## The C++ template on lavapipe (T692, 2026-10-19)
- `install.sh --gamedev` (alone, then exits): apt the DEPS.tsv `# gamedev-cpp:` packages (cmake, ninja, gcc/g++, clang, mold,
  ccache, glslang, spirv-tools, weston, mesa EGL + `mesa-vulkan-drivers` = lavapipe, validation layers, python3-venv/-dev), vcpkg
  shallow-fetched at the template's `builtin-baseline` into `$VCPKG_ROOT` (default ~/opt/gamedev/vcpkg) and bootstrapped,
  `vcpkg fetch cmake`, and the FLIP venv (flip-evaluator 1.7, built from source on Python 3.14). Second run: `gamedev present`.
- `install-fresh.sh --suite --skills --gamedev`: only in the release matching the host (vcpkg hashes gcc and its own cmake into
  every ABI, so only the same release hits): `install.sh --gamedev` on the bridge, the host's `~/.cache/vcpkg/archives` mounted
  read-only at /opt/vcpkg-archives, `VCPKG_BINARY_SOURCES=clear;files,/opt/vcpkg-archives,read` for the suite.
  `SUITE_ONLY=<glob>` passes `run.sh --only` (iterate: `SUITE_ONLY='*/c[op][dp]-*'` = cpp-* + code-review, ~200 s).
- cpp-crash, -play, -audio, -collide, -hot, -shadow left host-only.txt; they print `SKIP needs vcpkg (install.sh --gamedev)`
  without vcpkg (24.04 box). cpp-shadow compares with `--no-ibl` (IBL lifts the shadow to 17 %, 47 % without) and skips the
  GPU timing on llvmpipe. cpp-play/-audio replay at `--size 320x180`: Debug build on lavapipe 29 s -> 5 s per 600 ticks
  (at 720p the 60 s run cap cut the mix at 571 ticks in the box).
- Pitfalls: flip-evaluator has no cp314 wheel (needs g++, cmake, python3-dev); without `vcpkg fetch cmake` an offline configure
  dies as "unable to find a build program corresponding to Ninja". Cold box: ~2,300 CPU s for the cpp files (each builds the template).
