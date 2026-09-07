# T06 — Tailscale SSH as the second access path

**Phase 0 · must · Model: opus · Estimated agent time: 30 min**

## Goal
The owner can reach a shell two independent ways (OpenSSH with keys, Tailscale SSH), so later hardening can never lock them out.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 3 and 4).
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"` (available after T01).
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- Tailscale 1.102, `RunSSH=false`. OpenSSH listens on :22 with password auth on. `~/.ssh/authorized_keys` exists (check whose key). Tailnet `tail2ea32e.ts.net`, node `moodle-lab`.
- Tailscale SSH needs an ACL rule on the tailnet admin console (`ssh` section) — the owner may have to click; the default tailnet policy usually allows self-owned devices.

## Steps
1. `sudo tailscale set --ssh` (keeps existing settings). `tailscale status` must still show connected.
2. Test locally: `tailscale ssh oscar-nadjar@moodle-lab true` (or `ssh oscar-nadjar@100.99.234.53` from the tailnet — from this host, use `tailscale ssh`). If it reports ACL denial, put the exact ACL snippet the owner needs in your report and stop there (ticket stays open for the owner).
3. Confirm at least one owner public key is in `~/.ssh/authorized_keys`; if none, generate nothing — ask the orchestrator to get the owner's key (or the phone app's key) and record the gap.
4. Add `runbooks/locked-out.md` to `~/agents/KB`: both paths, the Tailscale admin console URL, how to revert sshd/ufw with etckeeper.

## Success check
```bash
tailscale debug prefs | grep RunSSH        # true
tailscale ssh oscar-nadjar@moodle-lab echo tailscale-ssh-ok   # prints it
wc -l ~/.ssh/authorized_keys               # >= 1
```

## Rollback
`sudo tailscale set --ssh=false`.
