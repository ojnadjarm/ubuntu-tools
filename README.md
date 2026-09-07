# pc-harness

An agent-agnostic harness for one Linux desktop: a `pc` CLI that drives the machine, a fleet of
scheduled agents run by systemd user timers, a shared contract every agent reads, and adapters
that wire it to whichever agent CLI is installed.

- **The contract:** `AGENTS.md` (`FLEET.md` is a symlink to it). Every agent reads it.
- **The machine:** `KB/toolbox.md`, `KB/quirks.md`, `KB/runbooks/`; `KB/machine.md` is generated.
- **The contract:** `AGENTS.md`; results: `bench/BASELINE-PCBENCH.md`, `bench/QA-REPORT.md`.

## Install

```bash
git clone <this repo> ~/agents
~/agents/install.sh          # or: make -C ~/agents install
```

`install.sh` is idempotent — a second run prints `no changes`. It:

1. checks prerequisites (`python3`, `jq`, `systemd --user`; `tmux` and `ydotoold` are advisory);
2. creates `~/.config/pc-harness/config.env` from `config.example.env` if it is missing;
3. symlinks the harness commands into `~/.local/bin` (not the `pc-*` subcommands, which `pc` dispatches);
4. installs `units/*` into `~/.config/systemd/user/`, reloads systemd and enables exactly the
   agents whose `agent.env` says `ENABLED=yes`, on their `SCHEDULE=`;
5. generates `KB/machine.md` from `pc status --facts`;
6. runs `adapters/$HARNESS_AGENT/install` to wire the agent CLI in use;
7. finishes with `pc doctor --quick`.

`uninstall.sh` reverses steps 3, 4 and 6 and keeps `secrets/`, `log/`, `backups/` and
`config.env`. Reinstalling after it restores the same roster.

**Prerequisites this repo does not install** (they are system-wide, one per machine):
Docker and the `docker` group, `ydotoold`, Tailscale, and the GNOME "Window Calls" extension.

## Configuration

Everything person- or machine-specific lives in `~/.config/pc-harness/config.env`
(fallback `~/agents/config.env`, both untracked). `config.example.env` lists every key with its
default. `bin/env.sh` loads it, and variables already exported by the caller win over the file.

## Multiple people on one machine

The harness is `systemd --user` and `$HOME` throughout: each person clones it into their own
home, runs `install.sh`, and gets their own `config.env`, their own ntfy topic and their own
timers. Nothing is shared but the system prerequisites above. No instruction file names a
person: `AGENTS.md` §0 defines *the user* (whoever is talking to the agent) and *the owner*
(whose `config.env` this install belongs to, and where `notify-owner` pushes).

## Adapters

One directory per agent CLI in `adapters/`, selected by `HARNESS_AGENT` in `config.env`:

| Adapter | State | Notes |
|---|---|---|
| `claude` | complete | hooks merged into `~/.claude/settings.json`, skills symlinked, `@AGENTS.md` include |
| `opencode` | complete | verified against opencode 1.18.29: `run --format json --auto`, skills + `instructions` in `~/.config/opencode/opencode.json` |
| `codex` | skills + audit stub | unverified: no `codex` CLI on this machine |
| `gemini` | audit stub | unverified |
| `generic` | complete | runs `$HARNESS_AGENT_CMD` with the prompt in `$PROMPT` |

Each adapter provides `run` (the `agent-exec` I/O contract), `install`, `uninstall` and a
`README.md` naming the flags it uses and what is lost against the Claude adapter. `bin/agent-exec`
is the only place that knows an adapter exists; `agent-run` and the units are agent-agnostic.

## Putting this directory under git (the owner runs these)

Agents never run `git init`, `add`, `commit` or `push` here. The first-time setup is:

```bash
cd ~/agents
git init
git add -A
git status                                   # review what is staged
git ls-files -o --exclude-standard | head    # must be empty-ish: nothing untracked left over
git ls-files | grep -E '^(secrets|log|backups|browser|state)/' ; echo "^ must print nothing"
du -sh .git 2>/dev/null                      # sanity: a few MB, not hundreds
git commit -m "pc-harness: initial import"
```

`.gitignore` keeps out `secrets/`, `log/`, `backups/`, `browser/`, `state/`, every agent's
`logs/`, `state/`, `REPORT.md` and `.lock`, `KB/machine.md`, `config.env`, `bench/runs/`,
`bench/arms/{old,new}/` and `__pycache__/`.

---

# Your agents

1. **What runs by itself**
   - `sentinel-check` (bash, every 15 min), `moodle-keeper`, `moodle-keep-weekly`, `sentinel-digest`.
   - The roster of record — every agent, its schedule, its task and when it contacts you — is the table
     in `~/CLAUDE.md`; each agent's own brief is `~/agents/<name>/BRIEF.md`.

2. **Where to look**
   - **Status page (phone): `http://$HARNESS_TAILNET_FQDN:19998`** (also `http://$HARNESS_LAN_IP:19998` on the LAN) — one screen: verdict,
     power, disk, docker + Moodle URLs, network, agents, last 24 h, live charts. Full netdata
     is on :19999 (tailnet name or LAN IP, both work).
   - `agents-status` — every agent: enabled, schedule, next run, last run, exit code, duration.
   - `~/agents/<name>/REPORT.md` — what that agent did on its last run (5 lines).
   - `agents-log --since 24h` — audit log of every tool call agents made.
   - `~/agents/<name>/logs/` — full output per run.

3. **How to stop everything**
   - `agents-stop` — the kill switch: nothing scheduled runs until you resume. `agents-start` brings
     back exactly the agents listed in `~/CLAUDE.md`. One agent only: `agent-disable <name>`.
   - Exactly what each of those stops and starts: `RUNNER.md` "Commands".

4. **Where the rest is**
   - Roster and orchestrator rules: `~/CLAUDE.md`. Rules every agent follows: `~/agents/AGENTS.md`.
   - Machine facts and runbooks: `~/agents/KB/`. Desktop control: `~/agents/README-pc-control.md`.
   - Benchmark and QA results: `~/agents/bench/BASELINE-PCBENCH.md`, `~/agents/bench/QA-REPORT.md`.
   - How an agent is built and added: `~/agents/RUNNER.md` (`~/agents/hello/` is the template).
