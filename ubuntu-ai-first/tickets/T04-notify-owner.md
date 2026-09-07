# T04 — notify-owner: push channel from any agent to the owner's phone

**Phase 0 · must · Model: opus · Estimated agent time: 45 min**

## Goal
Any script or headless agent can send a short push to the owner's phone with one command, with no Claude session involved.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 3 and 4).
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"` (available after T01).
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- PushNotification only works inside an interactive Remote Control session. Timers and `claude -p` runs need their own channel.
- Decision (PLAN §4, §7 Q1): ntfy. Default to the public `https://ntfy.sh` with a random 32-char topic. If the owner answered Q1 with Telegram, stop and ask the orchestrator for the bot token instead.
- Gmail MCP exists for long reports; pushes stay under ~200 chars and never carry credentials.

## Steps
1. Generate a topic: `ntfy-moodle-lab-$(openssl rand -hex 12)`. Store it in `~/agents/secrets/ntfy.env` (`NTFY_URL=https://ntfy.sh`, `NTFY_TOPIC=...`), `chmod 600`, dir `700`.
2. Write `~/agents/bin/notify-owner` (bash): usage `notify-owner [-p low|default|high|urgent] [-t title] "message"`; reads the env file; `curl -fsS` POST with `Title`/`Priority`/`Tags` headers; exit non-zero on failure; log every send to `~/agents/log/notify.log` (create dir).
3. Add `notify-owner` to `~/agents/README-pc-control.md` (usage + "secrets in ~/agents/secrets, never echo them").
4. Send a test push; put the subscription instructions in your report: install the ntfy app, subscribe to the topic (paste the topic in the report — it is the secret, keep it out of any other file). Ask the orchestrator to confirm the owner received it.

## Success check
```bash
~/agents/bin/notify-owner -t "T04" "notify-owner works"; echo exit=$?    # exit=0
tail -1 ~/agents/log/notify.log                                            # the line above
stat -c %a ~/agents/secrets/ntfy.env                                       # 600
```
Owner confirmation of the push closes the ticket.

## Rollback
Delete `~/agents/bin/notify-owner`, `~/agents/secrets/ntfy.env`; unsubscribe on the phone.
