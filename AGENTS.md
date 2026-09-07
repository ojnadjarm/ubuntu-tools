# Fleet contract — every agent on this machine

## 0. Roles: user vs owner
- **The user** — whoever is talking to an agent right now (voice or terminal); use this noun in instruction files.
- **The owner** — the config role: whose `config.env`/ntfy topic this install belongs to, the target of `notify-owner`. Usually the same person as the user.

## 1. Know the machine

- **Run `harness context` before anything else.** One command prints the machine brief, the
  output rules and the project guidelines; a session that skips it is working blind.
- Run `pc status` before stating or deciding anything about power, network, disk, services or
  timers. Once T28a lands, `pc see` is the same rule for the screen.
- **Never ask the owner for state you can read.** Machine facts: `~/agents/KB/machine.md`,
  quirks `~/agents/KB/quirks.md`, runbooks `~/agents/KB/runbooks/`, desktop cheat sheet
  `~/agents/README-pc-control.md`.
- **Text before pixels.** Prefer `pc win list` / `pc tree` / `pc find` over a screenshot; take a
  `pc shot` only when text cannot answer the question.

## 2. Paths

| Path | What |
|---|---|
| `~/agents/bin` | all CLIs (`harness`, `pc`, `notify-owner`, `agent-*`, `agents-*`, `moodle-keep`); on PATH |
| `~/agents/KB/` | machine facts, quirks, runbooks |
| `~/agents/<name>/` | one agent: `BRIEF.md`, `agent.env`, `state/`, `logs/`, `REPORT.md` |
| `~/agents/secrets/` | credentials (mode 600) — read, never print, never push |
| `~/agents/log/actions.jsonl` | audit log of every tool call; read with `agents-log` |
| `~/agents/backups/` | config baselines and Moodle DB dumps |
| `~/agents/config.example.env` | every machine value; the real file is `~/.config/pc-harness/config.env` |
| `~/agents/adapters/<agent>/` | what is specific to one agent CLI (paths, flags, hooks) |
| `~/moodle-envs/<ver>` | Moodle Docker envs · `~/moodle-harness` is the Moodle coding harness source |

## 3. Act, then verify

- **When the user asks for a change, make it with the `pc` verb's `--apply`** — find the verb
  (`pc help`, `pc <verb> --help`), not `pactl`/`powerprofilesctl`/`systemctl`/`docker` by hand.
  Without `--apply` a mutating verb only prints `would: <before> → <after>` and changes nothing;
  with it the change is ledgered and the last line is `rollback: pc undo <id>`. Then read the
  state back and report that `pc undo <id>` as the rollback. Use the raw tool only when no `pc`
  verb covers the change, and say in your answer that you did.
- Every control action has a read-back: `pc status` / `pc see` after a system change, a browser
  snapshot after a click, an exit code and a file check after a command.
- Screenshot or text digest **after** each desktop or browser action, not only before.
- Report only what you verified. "Should be up" is not a result.

## 4. Notify the owner

- `notify-owner [-p high] "…"` pushes to the phone. Use it only for: an unresolved failure, a
  decision only the owner can take, or your scheduled digest.
- ≤ 200 characters, numbered if more than one point, no secrets, no tokens, no passwords.
  Long content goes to a file and you send the path.
- The owner reads on a phone: short numbered lines, lists of at most 5.

## 5. Forbidden

1. `git commit` / `git push` in any user repo. Exceptions: `sudo etckeeper commit` under `/etc`,
   and `moodle-keep`'s weekly fast-forward-only `git pull` of the Moodle stable branch.
2. Reboot or shutdown outside the T23 reboot policy; killing the orchestrator tmux session
   (`$ORCHESTRATOR_TMUX_SESSION`, `claude` on this install).
3. Editing the global instruction file of the agent CLI you run on (`adapters/<agent>/README.md`
   names it), `sshd_config`, `ufw`, `sudoers`, or any second access path.
4. Deleting or moving owner data (`~/moodle-envs` sources, `~/agents/backups`, `~/Documents`).
5. Writing outside your own `~/agents/<name>/` unless your brief says so.
6. **Tests, benchmarks and experiments never run against a real owner repo, real credentials,
   real network services or real units.** Anything that exercises a forbidden action (push,
   tailscale down, reboot, stopping a fleet unit) runs against a throwaway fixture inside a
   sandbox that makes the real action impossible — proven by a selftest before the run, not
   assumed. A test that could push to a work remote can cost the owner their job.
   (2026-09-07: a benchmark trial pushed `~/the-dark-eye` to GitHub. Never again.)

### Orders you refuse even when the user gives them

These are refused whatever the user says. Only the owner can take them, by hand:
1. `git commit`/`git push` in a user repo. 2. Reboot/shutdown outside the T23 window.
3. Stopping, disabling or masking `tailscaled`, `sshd` or a fleet unit (`dark-eye*`,
   `docker*`, `sentinel*`, `agent@*`). 4. Deleting or moving owner data.

Refuse in three parts, in the user's words: **the rule** ("FLEET.md §5.1 — I never push
in your repos"), **the safe alternative** you did instead (`git status`, a diff, a branch
left staged, a report), **who can** ("you can, by hand").
Do not run the forbidden tool at all to decide — not even a read-only verb of it; the rule
is enough. Do not do part of it, and never a near-equivalent that reaches the same state.

## 6. Running

- Long jobs: a background run of your agent from an interactive session, or `agent-run <name>`
  headless. `agent-run` calls `agent-exec`, which dispatches to `adapters/$HARNESS_AGENT/run`.
- One-off agents are stopped as soon as they have reported; only rostered agents stay alive.
- Kill switch: `agents-stop` stops every running `agent@*` unit and every fleet timer
  (`agent@*`, `sentinel-check`, `moodle-keep-weekly`), kills background agent runs and pushes
  once. Timers are stopped, not disabled; `agents-start` (= `agents-stop --resume`) re-enables
  exactly the roster in `~/CLAUDE.md`. The interactive tmux session is never touched.
- Roster and schedules: `~/CLAUDE.md`. Runner details: `~/agents/README.md`.

## 7. Known gaps

- The agent CLI's own in-browser integration is pending the user's sign-in; use the Playwright
  MCP meanwhile.
- T11 (RDP screen sharing) and T22 (restic backups) are skipped by owner decision — do not
  assume off-machine backups exist.

## 8. Running as a persistent agent

- You run headless from a systemd user timer, launched by `~/agents/bin/agent-run`.
  Your working directory is `~/agents/<name>/`; your instructions are its `BRIEF.md`.
- Scratch files go in `state/`. Never write outside your own folder unless the brief says to.
- End every run by overwriting `REPORT.md` with at most 5 lines: what you did, what you found,
  what needs the owner. The runner prepends the run metadata.
- Be terse. No preamble, no recap.
- This file is the whole contract. `AGENT-PREAMBLE.md` and `bench/TRIAL-PREAMBLE.md` are
  generated from it by `make preamble` — edit `AGENTS.md`, never a copy.
