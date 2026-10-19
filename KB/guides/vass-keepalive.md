# Keep the vass services and the Moodle 4.5 env alive (restart policy, boot units, sentinel self-heal)

Ticket: T269 · Last verified: 2026-10-07 by `pc status`, `systemctl is-enabled`, `docker inspect`, tests below

## When to use
A vass container, vass user unit, the 4.5 cron timer or the 4.5 site is down, or a new service must be kept alive the same way.
Not for the Moodle code itself (owner's repo `~/moodle-envs/vass`, never edited).

## The path we took
| Layer | What keeps it alive |
|---|---|
| crash / Docker restart | compose containers `moodle45-*`, `vass-services-*` run `restart: unless-stopped` (already set, 4/4) |
| boot | `docker.service` enabled; user units `vass-middleware`, `vass-frontend`, `vass-frontend-proxy` and `moodle45-cron.timer` enabled, linger on |
| detection | `pc status` section `docker` (per compose project) and section `keepalive` (`KEEPALIVE_UNITS` active, `KEEPALIVE_HTTP` answers 200), 60 s cache |
| repair | `sentinel-check` (15 min): `docker.*` → `compose up -d`; `keepalive.<unit>` → `systemctl --user restart`; `keepalive.http-<project>` → `compose restart`; all wrapped in `bounded` (3 tries in a row, then one push, reset when the key clears) |

## Exact commands
```bash
pc status | sed -n '/^KEEPALIVE/,/^$/p'          # unit states + 4.5 HTTP code
pc status --json | jq '.sections.docker'          # per-stack n/N up
systemctl --user is-enabled vass-middleware.service vass-frontend.service vass-frontend-proxy.service moodle45-cron.timer
ls ~/agents/sentinel/state/tries/                 # keys under repair and their try count
bash ~/agents/bin/tests/sentinel-keepalive.test.sh
```
Add a watched unit or site: set `KEEPALIVE_UNITS` / `KEEPALIVE_HTTP` (`<project>=<url>`, project = compose `name:`) in `~/.config/pc-harness/config.env`.

## Pitfalls (measured)
- `docker stop` (or `pc docker stop`) on an `unless-stopped` container stays stopped: only the sentinel's `compose up -d` revives it, within one 15-min tick.
- `pc status` caches docker and keepalive for 60 s; the sentinel's re-check uses `--fresh`, a hand check right after a fix should too.
- `vass-middleware` orders `After=docker.service`, a system unit the user manager cannot see; at boot it may start before mongo/redis and rely on `Restart=on-failure`.
- A unit that keeps failing (a broken owner build) gets 3 restarts, then one push; no restart loop.
- A timer that re-fires a failing oneshot every minute (`moodle45-cron` on "upgrade pending", 2 587 times 10-09 → 10-13) never shows in `pc status`; `pc doctor` row `unit-loops` FAILs at ≥ 10 fails/h and `moodle-keep` prints the owner's `upgrade.php` line (TSP-038).

## Links
- Code: `~/agents/bin/pc-status` (keepalive section), `~/agents/bin/sentinel-check` (`bounded`, `fix_keepalive`), `~/agents/dashboard/dash/services/projects.py` (tile lists `moodle45-` and `vass-services-` containers)
- Tests: `bash ~/agents/bin/tests/sentinel-keepalive.test.sh`, `bash ~/agents/bin/tests/pc-status.test.sh`, `bash ~/agents/bin/tests/sentinel-check.test.sh`
