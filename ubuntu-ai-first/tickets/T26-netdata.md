# T26 — Netdata dashboard over the tailnet

**Phase 5 · nice · Model: opus · Estimated agent time: 45 min**

## Goal
The owner (and agents, via its API) get live CPU, RAM, disk, network, temperature and per-container metrics on `http://moodle-lab.tail2ea32e.ts.net:19999`, tailnet-only, with no cloud account.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4). Run `pc status` before making any statement about the machine; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- Nothing installed; sysstat collects locally. Netdata's apt repo/kickstart installs a system service; disable its cloud/telemetry (`--disable-telemetry`, `[cloud] enabled = no`). Bind to the Tailscale IP only (`[web] bind to = 100.99.234.53` — note the IP is stable within the tailnet; fall back to `*` + ufw if T25 is done).
- Docker metrics via the cgroups collector need the netdata user in the docker group.

## Steps
1. Install Netdata from its official repo with telemetry/cloud off; bind to the Tailscale IP; enable the docker/cgroups collector; keep retention small (`dbengine` 1 GB).
2. `pc status` gains a `netdata` service line; `~/agents/KB/machine.md` gets the URL and the API example (`curl 'http://100.99.234.53:19999/api/v1/data?chart=system.cpu&after=-60&points=1'`).
3. Health alarms: keep defaults but route to `notify-owner` for critical only (`health_alarm_notify.conf` custom method calling the script; root-readable ntfy env as in T24).

## Success check
```bash
systemctl is-active netdata
ss -tlnp | grep 19999                                    # bound to 100.99.234.53 only
curl -s 'http://100.99.234.53:19999/api/v1/info' | python3 -c "import json,sys;print(json.load(sys.stdin)['version'])"
curl -s --max-time 3 http://192.168.1.20:19999 >/dev/null; echo lan-exit=$?   # non-zero (not reachable on LAN)
```

## Rollback
`sudo apt remove netdata` (or the uninstaller), remove the config dir.
