# T19 — Fleet contract: roster, conventions, owner-facing README

**Phase 3 · must · Model: opus · Estimated agent time: 45 min**

## Goal
Every agent (orchestrator, one-off worker, persistent) finds the same short contract: where things are, how to check the machine, how to log, when to notify, what is forbidden; the owner has a 1-page README and a filled roster.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4). Run `pc status` before making any statement about the machine; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- `~/CLAUDE.md` (orchestrator rules, roster table empty), `~/agents/README.md` (T15 draft), `~/agents/README-pc-control.md`, `~/agents/KB/`, `~/agents/AGENT-PREAMBLE.md` (T15), skills `/desktop` `/browser` `/moodle-web`.
- Owner reads on the phone: numbered, short paragraphs, lists ≤ 5.

## Steps
1. Write `~/agents/FLEET.md` (≤ 60 lines): 1) know the machine (`pc status` first, never ask the owner for readable state), 2) paths (bin, KB, secrets, log, backups, agents/<name>), 3) act-verify loop (screenshot/read-back after each desktop or browser action), 4) notify policy (only on unresolved failure, decisions, or daily digest; ≤ 200 chars; no secrets), 5) forbidden (git commit/push, reboot outside T23 policy, sshd/ufw/sudoers edits, deleting owner data, editing `~/.claude/CLAUDE.md`), 6) long jobs use `claude --bg`/`agent-run`, one-off agents are stopped after reporting.
2. Make `AGENT-PREAMBLE.md` include `FLEET.md` verbatim (or `cat` it at run time in `agent-run`). Add one line to `~/CLAUDE.md` Machine section pointing to `FLEET.md`; fill the roster table (sentinel, sentinel-digest, moodle-keeper, hello=template) with schedule and "contacts user" column.
3. Rewrite `~/agents/README.md` for the owner (≤ 25 lines): what runs when, where to look (`agents-status`, `agents-log`, REPORT.md files), how to stop everything (`agents-stop`), where the plan is.
4. Ask the orchestrator to confirm the roster with the owner (that is the only owner touchpoint).

## Success check
```bash
wc -l ~/agents/FLEET.md ~/agents/README.md          # <= 60 and <= 25
grep -c "pc status" ~/agents/FLEET.md ~/agents/AGENT-PREAMBLE.md   # >= 1 each
grep -A6 "^| Agent" ~/CLAUDE.md                     # roster filled
claude -p --model sonnet "You are a worker agent on this machine. Where must you look before making a statement about power or network, and what are you forbidden to do? Answer in 3 lines." | tail -3   # cites pc status and the forbidden list
```

## Rollback
Delete `FLEET.md`; restore `~/CLAUDE.md` and `README.md` from `~/agents/backups`.
