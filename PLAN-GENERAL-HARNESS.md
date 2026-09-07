# PLAN-GENERAL-HARNESS — make the harness agent-agnostic, person-agnostic, installable

Date: 2026-09-07. Scope: ~/agents (fleet), ~/.claude (live), ~/moodle-harness (git source), ~/CLAUDE.md.
Out of scope: ~/the-dark-eye (note: `~/.claude/skills/eye/SKILL.md` is a symlink INTO it), ~/.claude/CLAUDE.md
(read-only), ~/.claude/projects. Nobody but the owner runs `git commit`/`push`/`init`.

## 0. Survey in three lines (what exists, what we pick)
- Conventions that already exist: **AGENTS.md** (read natively by Codex CLI, OpenCode, Gemini CLI via
  `contextFileName`, Aider via `--read`; Claude Code via `@AGENTS.md` include in CLAUDE.md); **SKILL.md**
  (agentskills.io format: `name` + `description` frontmatter, Claude Code and Codex `~/.agents/skills` load it);
  **MCP** for tool exposure (Playwright MCP already registered agent-agnostically via `~/agents/bin/playwright-mcp`).
- Already agent-neutral here: the whole `pc` family, `notify-owner`, `agents-*` (systemd), `pc` guards in
  `pclib.sh` (real enforcement, independent of any permission model), bench task scripts, KB markdown.
- QA tooling (none installed today; all apt/pip, no framework): **shellcheck** (`-S warning`, correctness),
  **shfmt** (`-d -i 2 -ci`, style only, never reflow logic), **jscpd** (`--min-tokens 40`, cross-file duplication
  in bash+python), **lizard** (cyclomatic complexity per function, bash + python), `wc -l`/`cloc` for the counts.
  Baseline numbers are written once by `bin/tests/qa-metrics.sh` and diffed per ticket.
- Pick: plain markdown (AGENTS.md as the single contract) + shell CLIs + one `config.env`; Claude Code becomes
  `adapters/claude/` (hooks + settings fragment + skill symlinks). No framework, no new language.

## 1. Inventory

### 1a. Person naming (live files only; `bench/arms/{old,new}` are built copies, not sources)
| Tree | Hits | Where |
|---|---|---|
| ~/agents | 2 "<owner name>" + 2 pronoun | `ubuntu-ai-first/PLAN.md:3` ("Owner: <owner name>"); `ubuntu-ai-first/qa/phase0.md:184` (historical QA log quoting a Tailscale audit line — keep, it is a record); `FLEET.md:52` ("cost the owner his job"); `KB/runbooks/locked-out.md:79` ("his phone") |
| ~/.claude | 4 "<owner name>" + 9 pronoun | `skills/moodle-pluginskel/SKILL.md:24` (copyright `<owner name> <owner email>`); `skills/eye/SKILL.md` lines 3,7,23,26,27,29,33,36,51,55,61,62 — **symlink to ~/the-dark-eye/bridge/SKILL.md, out of scope** |
| ~/moodle-harness | 1 | `skills/moodle-pluginskel/SKILL.md:24` (same copyright line, synced copy) |
| ~/CLAUDE.md, ~/.claude/CLAUDE.md | 0 | — |
Word usage today: FLEET.md owner=11/user=1, AGENT-PREAMBLE owner=10/user=2, KB owner=39/user=35, ~/CLAUDE.md
owner=4/user=7, moodle-harness owner=0/user=33, ~/.claude/CLAUDE.md owner=0/user=2.

**Recommended convention: "the user"** in every instruction file an agent reads (matches the owner's request,
AGENTS.md/Claude/Codex vocabulary, and the coding harness). Keep **"owner" only as a config role**, defined once
in AGENTS.md §0: "owner = the user whose `config.env` this install belongs to; `notify-owner` reaches them".
Do not churn the 39 fleet "owner" mentions that refer to that role (notify target, data owner); replace only
the literal name, "his/him/he", and "owner" where it means "the person talking to you now" (→ "the user").

### 1b. Claude-Code-specific dependencies and the generic replacement
| Kind | Where (live) | Generic agent needs |
|---|---|---|
| File layout | `~/.claude/{CLAUDE.md,skills/*/SKILL.md,hooks/,settings.json}`; `~/CLAUDE.md` orchestrator; `moodle-harness/sync.sh` copies into `~/.claude`; `set-moodle-harness` checks 20 `~/.claude/...` paths | `~/agents/AGENTS.md` as the contract (Codex/OpenCode/Gemini read it; Claude includes it); skills in `~/agents/skills/<name>/SKILL.md` (agentskills.io frontmatter only) symlinked per adapter; hooks replaced by a CLI the agent is told to run first (`harness context`) |
| CLI invocations | `agent-run:41` `claude -p --model --permission-mode bypassPermissions --name agent-$name --append-system-prompt --output-format json` + `jq .total_cost_usd/.result`; `agents-stop:27` and `pc-status:352` `claude agents --json`; `pcbench:401` `claude -p` + stream-json; `claude-orchestrator.service` `claude --remote-control`; FLEET §6 `claude --bg`; `sentinel-check` escalates to `agent-run` | `agent-exec` shim: `agent-exec --prompt-file BRIEF.md --system-file PREAMBLE --model M --cwd D` → result text on stdout, `meta.json` `{exit,cost_usd?,tokens?}`; per adapter: Codex `codex exec --json`, Gemini `gemini -p --yolo`, OpenCode `opencode run`, Aider `aider --message --yes`, custom loop = any script honouring the same I/O. "Background sessions" = `agent-run` + systemd, never a vendor flag |
| Permission/settings | `settings.json`: `defaultMode: bypassPermissions`, allow list, `model`, `effortLevel`, hooks table | Policy lives in AGENTS.md §5 (forbidden list) and is **enforced by `pclib.sh` guards** (agent-agnostic today). Each adapter maps "full-auto" its own way (`codex --full-auto`/`-a never`, `gemini --yolo`); model/effort come from `agent.env` `MODEL=` passed to `agent-exec` |
| Hooks | SessionStart `moodle-session-start.sh` + `machine-status.sh`; Stop `moodle-stop-reminder.sh`; PostToolUse `audit-log.sh` → `log/actions.jsonl`; SubagentStart/Stop `orbit-hook` (Eye) | `harness context [--moodle]` prints exactly what SessionStart injects (AGENTS.md line 1: "run it first"); stop reminder → checklist line in AGENTS.md; audit → documented `actions.jsonl` schema + per-adapter converter from the agent's own JSON stream (Claude keeps the hook); orbit-hook stays Claude-only (the-dark-eye) |
| Monitor / eye listen-loop | `skills/eye/SKILL.md` (Monitor tool, `persistent: true`); `KB/toolbox.md:64` | `eye listen-loop` is a plain stdout stream; agents without a Monitor tool poll it in a background shell. Doc lives in the-dark-eye — only a pointer here |
| Memory / scratch dir | `sentinel-runaway` rules 1 and 5 hardcode `/tmp/claude-<uid>/*/*/scratchpad` | `AGENT_SCRATCH_GLOBS` in config.env (default = today's glob) |
| Agent names in units / sessions | `agent@.service` "Persistent Claude agent"; `--name agent-$name`; `claude-orchestrator.service`; tmux session `claude` guarded in `pclib.sh:140`, `pc-units:30`, `boot-check.sh:15`, `pc-status:149`, `pcbench.d/fingerprint.sh:17`, BRIEFs of sentinel/moodle-keeper/maintenance, FLEET §5.2/§6 | Keep unit **names** (`agent@`, `sentinel-check`) — they are generic already. `ORCHESTRATOR_TMUX_SESSION` and `ORCHESTRATOR_UNIT` in config.env; guards read them. Renaming `claude-orchestrator.service` itself is an owner decision (D5) |
| Machine identity | `/run/user/1000` in `agent@.service`, `env.sh`; `100.99.234.53` in `agents-dashboard.service`, `dashboard/server.py`; `moodle-lab` in `notify-owner` (title), `maintenance-run`; docs: FLEET, PREAMBLE, README*, KB/machine.md, toolbox, 3 runbooks, browser skill | All from config.env (`HARNESS_UID=$(id -u)`, `HARNESS_HOST=$(hostname)`, `HARNESS_TAILNET_FQDN`, `HARNESS_LAN_IP`); `KB/machine.md` becomes generated (`pc status --facts`) and gitignored |
Also found: `AGENT-PREAMBLE.md` is a hand-pasted copy of FLEET.md and has **already drifted** (lacks §5.6, the
2026-09-07 push incident rule). GH06 fixes this structurally.

## 2. Target architecture

```
~/agents/                      = git repo "pc-harness" (init in place; owner runs git)   [D2]
  README.md                    what it is, install, uninstall, multi-user, adapters
  AGENTS.md                    THE contract: §0 roles (user/owner), §1-7 = today's FLEET + preamble, agent-neutral
  FLEET.md -> AGENTS.md        symlink kept for existing references
  config.example.env           every person/machine value (below); real file is outside the repo
  install.sh / uninstall.sh    idempotent; Makefile targets `install`, `uninstall`, `doctor`, `preamble`
  bin/                         pc*, agent-*, agents-*, notify-owner, sentinel-*, moodle-keep*, harness, agent-exec, tests/
  KB/                          toolbox.md, quirks.md, pc-cli.md (generated), runbooks/; machine.md GENERATED + ignored
  skills/                      desktop/, browser/ (agentskills.io SKILL.md; Claude-only keys live in adapters/)
  agents/                      hello/, sentinel/, sentinel-digest/, moodle-keeper/, maintenance/: BRIEF.md + agent.env only
  units/                       agent@.service/.timer, sentinel-check.*, moodle-keep-weekly.*, agents-dashboard.service (%h, no uid)
  adapters/                    claude/ (run, install, settings.fragment.json, hooks/, README), codex/, gemini/, opencode/, generic/
  hooks/                       audit-log.py, machine-status.sh (adapter-neutral cores called by adapters/*/hooks)
  dashboard/                   server.py, index.html
  bench/                       SCHEMA.md, PLAN, tasks/, tickets/, arms/build-*.sh + exec.sh; runs/, arms/{old,new}/ ignored
```
Machine-local, **never in git** (.gitignore): `secrets/`, `log/`, `backups/`, `browser/` (profiles, 27 MB),
`bench/runs/`, `bench/arms/{old,new}/`, `*/logs/`, `*/state/`, `*/REPORT.md`, `*/.lock`, `KB/machine.md`,
`config.env`, `__pycache__/`. `~/moodle-harness` stays a separate repo (Moodle coding harness, different
audience); its Claude-only parts are already isolated by `sync.sh`. [D9]

**config.env** — path `~/.config/pc-harness/config.env` (XDG, per-user, survives re-clone; fallback
`~/agents/config.env`). Shell syntax, sourced by `bin/env.sh` (already sourced by 21 scripts + `agent-run`). [D3]
```
HARNESS_HOME=$HOME/agents            HARNESS_AGENT=claude          # claude|codex|gemini|opencode|generic
HARNESS_AGENT_CMD=                    # optional override for adapters/generic/run
HARNESS_OWNER_NAME=                   HARNESS_OWNER_EMAIL=          # default: git config user.name/email
HARNESS_HOST=$(hostname)              HARNESS_TAILNET_FQDN=         HARNESS_LAN_IP=
HARNESS_UID=$(id -u)                  # -> XDG_RUNTIME_DIR, DBUS address
NTFY_ENV_FILE=$HARNESS_HOME/secrets/ntfy.env                       # secrets stay in secrets/, mode 600
ORCHESTRATOR_TMUX_SESSION=claude      ORCHESTRATOR_UNIT=claude-orchestrator.service
AGENT_SCRATCH_GLOBS="/tmp/claude-$HARNESS_UID/*/*/scratchpad"
MOODLE_ENVS_DIR=$HOME/moodle-envs
```
**Multi-user**: everything is `systemd --user` + `$HOME`; each person installs in their own home with their
own config.env and ntfy topic. Shared system pieces (ydotoold, docker group, Tailscale) are documented as
prerequisites in README, not installed by `install.sh`. AGENTS.md says "the user" / "the owner" only.

**Adapter contract** (`adapters/<name>/`): `run` (implements `agent-exec` I/O), `install` (wire context file,
skills, hooks for that agent; idempotent), `uninstall`, `README.md` (flags used, what is lost vs Claude).
`adapters/claude/install` = today's `set-moodle-harness` step 4 logic (merge hooks into `~/.claude/settings.json`),
symlink `skills/*` into `~/.claude/skills/`, add `@~/agents/AGENTS.md` include line to a project-level
`~/CLAUDE.md` (the global `~/.claude/CLAUDE.md` is not touched).

## 3. Tickets (each <= 2 h; [D] = needs an owner decision first)

**Phase A — rename pass (mechanical)**
- **GH01 Person names out of live docs.** Files: `ubuntu-ai-first/PLAN.md:3` → "Owner: see config.env";
  `FLEET.md:52` "his job" → "their job"; `KB/runbooks/locked-out.md:79` "his" → "the user's". Leave
  `qa/phase0.md:184` (historical log). Check: `grep -RIn -E "<owner name>|\b(his|him)\b" ~/agents --exclude-dir={bench,log,backups,browser,state} | grep -v qa/phase0` → 0. Rollback: `git checkout` once repo exists; before that, `baseline.sh` tarball.
- **GH02 Pluginskel copyright from identity, not literal.** [D7] `skills/moodle-pluginskel/SKILL.md:24` + `generate.py`: default `copyright` from `HARNESS_OWNER_NAME/EMAIL`, else `git config user.name/email`; recipe may still override. Apply in `~/.claude`, then `~/moodle-harness/sync.sh`. Check: `grep -c "<owner name>" both SKILL.md` = 0; generate a skeleton into scratch and `/moodle-ci quick` on it passes phpcs. Rollback: sync.sh reverse copy from moodle-harness git.
- **GH03 Eye skill wording** — out of scope (the-dark-eye repo). Deliverable: 5-line note `~/agents/state/NOTE-dark-eye-rename.md` listing the 12 lines for the owner. [D6]
- **GH04 Define the roles once.** Add AGENTS.md/FLEET.md §0 "user vs owner" (3 lines) and the same line to `~/CLAUDE.md` §Machine. Check: `pc explain owner` returns the definition. Rollback: revert the two hunks.

**Phase B — contract layer**
- **GH05 config.env + loader.** [D3] Create `config.example.env`, extend `bin/env.sh` to source config with defaults; replace literals in `env.sh`, `notify-owner`, `maintenance-run`, `dashboard/server.py`, `units/agent@.service`, `units/agents-dashboard.service` (use `%h`, `%U`/`$HARNESS_UID`). Check: `grep -RIn -E "/run/user/1000|100\.99\.234\.53|moodle-lab" bin units dashboard` → 0; `pc doctor` PASS; `systemctl --user daemon-reload && agents-status` unchanged; `notify-owner "GH05 ok"` arrives. Rollback: baseline tarball + `daemon-reload`.
- **GH06 AGENTS.md as the single contract.** Write `AGENTS.md` = FLEET §1-7 + preamble bullets, agent-neutral wording (`claude -p` → `agent-run`/`agent-exec`; `claude --bg` → "a background run of your agent"; `~/.claude` mentions → `adapters/claude/README.md`). `FLEET.md` → symlink. `make preamble` regenerates `AGENT-PREAMBLE.md` from AGENTS.md (fixes the §5.6 drift). Check: `diff <(sed -n '/^# Fleet/,$p' AGENT-PREAMBLE.md) AGENTS.md` empty; `grep -c "claude" AGENTS.md` ≤ 3 (only the config default and the orchestrator guard). Rollback: keep old FLEET.md as `FLEET.md.bak` until GH13.
- **GH07 `agent-exec` shim + `adapters/claude/run`.** `agent-run` calls `agent-exec` instead of `claude` directly; Claude adapter reproduces today's flags and writes `meta.json` (`cost_usd` from `.total_cost_usd`). `adapters/generic/run` = `$HARNESS_AGENT_CMD` with `$PROMPT`/`$SYSTEM` env. Check: `HARNESS_AGENT=generic HARNESS_AGENT_CMD=bin/tests/fixtures/pcbench/bin/claude agent-run hello` produces `REPORT.md` + `index.tsv` row; `agent-now hello` on the Claude adapter unchanged. Rollback: `agent-run` keeps a `HARNESS_AGENT=` unset → legacy path for one release.
- **GH08 `harness context` CLI.** `bin/harness context [--moodle] [--brief]` prints machine brief (`pc status --brief`), ADHD rules, and Moodle guidelines when `moodle-detect.sh` says so — the exact text the SessionStart hooks inject. `adapters/claude/hooks/session-start.sh` becomes a 3-line wrapper. AGENTS.md line 1: "Run `harness context` before anything else". Check: hook output byte-identical to `harness context --json`; `pc doctor` PASS. Rollback: old hook scripts stay in place until GH15.
- **GH09 Audit log schema, adapter converters.** Document `log/actions.jsonl` fields in `KB/audit.md`; move `audit-log.sh` core to `hooks/audit-log.py` (stdin = generic `{tool,input,cwd,session}`); Claude PostToolUse wrapper maps its JSON; `adapters/codex/audit-from-stream` + `adapters/gemini/...` stubs mapping their JSON event streams. Check: `bin/tests/audit-redact.test.py` green; `agents-log --since 1h` shows entries from both paths. Rollback: single-file revert.
- **GH10 Skills to portable form.** Move `desktop/`, `browser/` SKILL.md into `~/agents/skills/`; keep only `name`/`description` in frontmatter; Claude-only `allowed-tools` goes in `adapters/claude/skills-overlay/<name>.yaml`; `adapters/claude/install` symlinks into `~/.claude/skills/`, `adapters/codex/install` into `~/.agents/skills/`. Check: `ls -l ~/.claude/skills/desktop/SKILL.md` is a symlink; `/desktop` still triggers in a fresh Claude session. Rollback: replace symlink with the file.
- **GH11 Orchestrator names from config.** [D5] `pclib.sh:117,140`, `pc-units:30`, `boot-check.sh:15`, `pc-status:149`, `pcbench.d/fingerprint.sh:17`, sentinel/moodle-keeper/maintenance BRIEFs read `$ORCHESTRATOR_TMUX_SESSION`/`$ORCHESTRATOR_UNIT`. Unit file **not** renamed. Check: `bin/tests/pclib.test.sh`, `pc-units.test.sh`, `pc-undo.test.sh` green; `grep -c "session \`claude\`" AGENTS.md` = 0.
- **GH12 Scratch globs from config.** `sentinel-runaway` rules 1/5 iterate `$AGENT_SCRATCH_GLOBS`. Check: `sentinel-runaway.test.sh` green with default and with a second glob.

**Phase C — repo, install, adapters**
- **GH13 Repo skeleton (no git commands).** [D2] Write `.gitignore` (list in §2), `README.md`, move files into the §2 layout using symlinks where a path is referenced by units (`bin/` stays). Deliver a checklist the owner runs: `git init && git add -A && git status`. Check: dry-run `git -C ~/agents ls-files -o --exclude-standard` after `git init` shows no `secrets/`, `log/`, `browser/`, `*/logs`; `pc doctor` PASS; `agents-status` unchanged.
- **GH14 install.sh / uninstall.sh.** Steps: check prerequisites (python3, jq, tmux, systemd --user, ydotoold present); create `config.env` from example if absent (prompt for owner name/email/ntfy topic); symlink `bin/*` into `~/.local/bin`; copy `units/*` to `~/.config/systemd/user/` + `daemon-reload` + enable roster from `agents/*/agent.env` `SCHEDULE=`; generate `KB/machine.md`; run `adapters/$HARNESS_AGENT/install`; finish with `pc doctor --quick`. Uninstall reverses, keeps `secrets/ log/ backups/ config.env`. Check: second run prints "no changes"; `pc doctor` PASS; `agents-status` shows the roster; uninstall then install restores it.
- **GH15 Claude adapter complete.** `adapters/claude/{install,uninstall,settings.fragment.json,hooks/,README.md}`; merges hooks idempotently (reuse `set-moodle-harness` step-4 python); adds `@~/agents/AGENTS.md` include to `~/CLAUDE.md`; `set-moodle-harness` SKILL.md points to it for the fleet part. Check: fresh Claude session shows "Machine: …" banner and `/desktop` works; `diff` of `settings.json` before/after a second install is empty. `/moodle-ci` not needed (no Moodle files).
- **GH16 Second adapter smoke.** [D4] Owner picks Codex or Gemini CLI; implement `run`+`install`; verify flags against the installed CLI's `--help` (none installed today: `codex/gemini/opencode/aider` absent). Check: `HARNESS_AGENT=<x> agent-now hello` → `REPORT.md` 3 lines + push received; audit entries via GH09 converter.
- **GH17 Multi-user rehearsal.** [D8] Owner creates a throwaway Linux user; run `install.sh` there with a different ntfy topic. Check: `grep -RIn "oscar-nadjar\|/home/oscar" ~/agents --exclude-dir={log,backups,browser,bench}` → 0 in the repo; second user's `pc doctor` PASS; their `notify-owner` reaches only their topic. Sandboxed: no real repos, FLEET §5.6.
- **GH18 Docs wording pass.** `README-pc-control.md`, `KB/toolbox.md`, `KB/quirks.md`: Claude-specific notes move to `adapters/claude/README.md`; remaining "owner" occurrences audited against GH04 definition. Check: `grep -RIn -E "\bclaude\b" KB README*.md AGENTS.md` ≤ 5 (config defaults only); `pc explain` index rebuilt.

**Phase D — deep QA and simplification (after GH13: every change is a git diff the owner can review)**
Rules for every D ticket: behaviour identical — `bin/tests/run.sh` (27 suites), `pcbench.test.sh`, `pc bench`
timing table within 10 % of `bench/BASELINE-PCBENCH.md`, `pc doctor` PASS, before and after; usage text
(`pc <sub> -h`) byte-identical unless the ticket says otherwise; one module per ticket; the ticket report
ends with a 4-column table `module | lines before/after | jscpd dupes before/after | shellcheck before/after`.
- **GH19 Metrics harness.** `bin/tests/qa-metrics.sh [module…]` prints the table above (wc, shellcheck
  `-S warning -f gcc` count, jscpd JSON `duplicates`, lizard `CCN>15` count) and `--baseline` writes
  `bin/tests/BASELINE-QA.tsv`. Installs the four tools via `install.sh --dev`. Check: two consecutive runs
  identical; every existing test green. Today's totals to beat: `bin/` shell+python 8043 lines; `pcbench` 802,
  `pc-status` 370, `sentinel-runaway` 234, `pc-doctor` 211, `pclib.sh` 194.
- **GH20 pclib.sh.** Fold repeated option parsing/usage/guard helpers; each `pc-*` that re-implements one
  switches to the helper (jscpd guides the list). Check: `pclib.test.sh`, `pc-undo.test.sh`,
  `pc-units.test.sh` green; guard refusals (`claude-orchestrator`, tmux session, ufw) still exit 3.
- **GH21 `pc` desktop subcommands** (`pc-click*`, `pc-type`, `pc-key`, `pc-move/drag/scroll`, `pc-shot`,
  `pc-see`, `pc-tree`, `pc-win`, `pc-wait*`, `pc-find`): shared coordinate/screen/wait code into pclib;
  `pc_input.py`/`rd_type.py`/`type.sh`/`key.sh`/`click.sh` legacy shims — delete ones no caller uses
  (`grep -rl` over bin, skills, KB, the-dark-eye read-only). Check: `pc selftest` (opens the calculator —
  daytime only, announce it) and `pc-input.test.sh` green; `pc bench` within 10 %.
- **GH22 `pc` kernel/session/services subcommands** (`pc-top/io/power/thermal/trace/kernel/net/hw`,
  `pc-dbus/mutter/input/audio/bt`, `pc-units/journal/docker`): one ticket per group of ≤ 6 files if any file
  is > 200 lines. Check: their 15 `*.test.sh` suites green; `pc-cli.md` regenerated and diff reviewed.
- **GH23 `pc-status` + `pc-doctor`.** Probe table driven from one list (name, cmd, cache TTL, budget) instead
  of two hand-written sequences; keep `--json/--check/--brief/--facts` output byte-identical on a fixture
  (`bin/tests/fixtures/pc-status/*.json` captured in GH19). Check: `pc-doctor.test.sh`; sentinel reads the
  same `--check` verdicts on the fixture.
- **GH24 sentinel (`sentinel-check`, `sentinel-runaway`, `sentinel-digest` BRIEF).** Rules as data (one row
  per fault: probe, fix, cooldown); dead branches removed. Check: `sentinel-runaway.test.sh` green plus a
  fixture replay of the last 7 days of `log/` events producing the same escalation decisions.
- **GH25 pcbench (802 lines).** Split into `pcbench.d/` modules only where it removes duplication; `validate`,
  `run --dry-run`, `--oracle` unchanged. Check: `pcbench.test.sh` green; `pcbench validate` over every
  `bench/tasks/*` identical output; `SCHEMA.md` frozen — no schema change allowed.
- **GH26 agent-*, agents-*, notify-owner, maintenance-run, moodle-keep, harness, agent-exec.** Common
  logging/lock/index helpers into one `fleetlib.sh`. Check: GH07 fake-agent run, `agents-status`,
  `agents-stop --resume` on the roster; `notify-owner` push arrives.
- **GH27 KB docs dedupe.** `toolbox.md` (213), `README-pc-control.md` (266), `quirks.md` (259), RUNNER.md,
  README.md overlap heavily; each fact lives in one file, the others link (`pc explain` must still rank it).
  Check: `pc-explain.test.sh`; `pc explain <10 sample terms>` still hits; total KB lines reported.
- **GH28 QA report.** `qa-metrics.sh` vs `BASELINE-QA.tsv` → `bench/QA-REPORT.md`: lines removed per module,
  duplication and shellcheck deltas, benchmark deltas, list of deleted files. `pc doctor` PASS as the last line.

## 4. Risks
- **Never rename**: the Linux user/home `oscar-nadjar`, `/home/oscar-nadjar` (in units via `%h` only), git
  identity, the Tailscale node `oscar` in `qa/phase0.md`, hostnames, `moodle-lab.tail2ea32e.ts.net`. A grep
  for the literal name must be case-sensitive and word-bounded so it never matches paths.
- Renaming the tmux session `claude` or `claude-orchestrator.service` breaks the `pclib.sh` refuse-guards,
  three test suites, `boot-check`, `pc-status`, `bench` fingerprints and the sentinel BRIEF at once — hence GH11
  parameterises, does not rename; a rename is a separate owner decision after GH11 lands.
- `agent@` unit names and `--name agent-<n>` are matched by `agents-stop`/`agents-status`/`pc-units`; keep them.
- `agents-stop` and `pc-status` use `claude agents --json` to find background runs; other adapters have no
  equivalent — `agent-exec` must record the child PID in `<agent>/state/pid` so the kill switch stays universal.
- `bench/arms/{old,new}` are frozen snapshots for the benchmark; rename passes must skip them or the benchmark
  compares a moving target. `~/moodle-harness` has 5 uncommitted changes — do not run `sync.sh` blindly.
- `AGENT-PREAMBLE.md` drift shows hand-copies rot; GH06's generated file must be the only copy.
- Eye skill is a symlink into `~/the-dark-eye`; touching it here would edit that project.
- A rename that hits `notify-owner` (the command name) breaks 20+ callers and the units; the command keeps its
  name — "owner" is the config role.

## 5. Owner decisions
D1 Convention: "the user" for the person talking; "owner" only as the config role (recommended).
D2 Repo: `git init` in place at `~/agents` (recommended, zero path changes) vs new `~/pc-harness` + symlink.
D3 Config path: `~/.config/pc-harness/config.env` (recommended) vs `~/agents/config.env`.
D4 Second adapter to build first: Codex CLI, Gemini CLI, or OpenCode.
D5 Keep `claude` tmux session / `claude-orchestrator.service` names (recommended) or rename after GH11.
D6 Eye skill wording: schedule inside the-dark-eye project.
D7 Pluginskel copyright: from config.env or from `git config` (recommended: git config, config.env override).
D8 Create a throwaway Linux user for GH17.
D9 Keep `~/moodle-harness` a separate repo (recommended) or fold into `pc-harness/adapters/claude/moodle/`.
D10 Style baseline for shfmt (2-space, `-ci`) applied repo-wide once in GH19 (large diff, no logic)
    or never (only new/edited files) — recommended: once, as its own commit the owner reviews.

## 6. Owner decisions — 2026-09-07 13:30 (voice)
- D1: wording is the orchestrator's call per context; the only rule is **no personal name in any base file**.
- D2: `~/agents` is the central repo, `git init` in place; the owner runs every git command, agents never push.
- D4: **OpenCode first** (more open source); Codex CLI unlikely to be used.
- D5 (clarified 13:45): keep only the **tmux session** name `claude` (and, until GH11, the unit name it guards).
  In every harness file, wording that names a vendor agent ("Claude agent", "Persistent Claude agent",
  "claude session") becomes plain "agent"; vendor commands/paths stay only inside `adapters/claude/`.
- D8: **no throwaway Linux user.** One Linux user on the units; several people share that same account. GH17 becomes
  a "no person hardcoded" audit (grep + config.env round trip), not a second-user install.
- Plan approved: "I like the plan. Go ahead." Implementation one phase per request, starting with Phase A.
