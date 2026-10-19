# Timed Moodle upgrade rehearsal 4.5 -> 5.3 with a tested rollback

Ticket: T423 · Last verified: 2026-10-19 by a full run (up, run, rollback, report, down) on a throwaway upstream site

## When to use
Pricing or planning a Moodle upgrade: you need measured step times and a proven rollback. Not for a customer's real site; for its plugin list use /moodle-upgrade-audit.

## The path we took
- Existing: /moodle-install builds envs, but its project name is `moodle<MM>`, so `4.5` would recreate the Vass containers. Chosen: its compose/config shape, re-used inside a separate script with its own project `moodle45r` and port 8145.
- Steps: maintenance on, backup (pg_dump -Fc, moodledata tgz, code tgz), pg13 -> pg17 restore, code swap, `.env` docroot `/public` + PHP 8.4, `admin/cli/upgrade.php`, theme check, smoke login (logintoken POST, `logout.php` in page).

## Exact commands
```bash
S=~/.claude/skills/moodle-upgrade-rehearsal/rehearse.sh
bash ~/.claude/skills/moodle-upgrade-rehearsal/tests/guard.test.sh
ci-window && $S all && $S down
```

## Pitfalls (measured)
- Upgrade window 110 s on XS data: upgrade.php 83.4 s, backup 12.8 s, pg move 4.5 s. Rollback 17.6 s. Fresh 4.5 install 78 s.
- The backup is taken inside maintenance, so a restore comes back in maintenance (HTTP 503 at login). Rollback must run `maintenance.php --disable`.
- upgrade.php itself moves `theme=classic` to boost (MDL-88351); 5.3 `public/theme` holds only boost.
- `set -e` is ignored inside `f || rc=$?`; `step` uses `( set -e; f )` so a failing pg_dump cannot report ok.
- Compose flow maps: `{APACHE_DOCUMENT_ROOT: ${DOCROOT}}` breaks YAML; quote the `${...}`.
- Files in moodledata are root-owned (CLI runs as root): tar it inside the app container; `down` uses sudo rm.

## Links
- Code: ~/.claude/skills/moodle-upgrade-rehearsal/rehearse.sh
- Tests: ~/.claude/skills/moodle-upgrade-rehearsal/tests/guard.test.sh (fixture HOME, no real env paths)
- Results: ~/drop/money/samples/rehearsal-4.5-to-5.3.md
