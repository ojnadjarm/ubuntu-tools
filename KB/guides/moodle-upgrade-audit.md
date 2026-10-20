# Audit a Moodle site's plugins for an upgrade (keep / replace / remove per add-on)

Ticket: T414 · Last verified: 2026-10-20 (T846) by `audit.py --help`, the cached pluglist counts, `unshare -rn` probe and paths; 2026-10-19 by tests/audit.test.sh (9/9, no network) and a live run on the 5.2 env

## When to use
Step 1 of the upgrade offer: every add-on checked for a target-release version. Not for core plugins (skipped) and
never on the 4.5 / Vass env.

## The path we took
- Existing: moosh `plugin-list` (lists the directory, no installed-vs-target verdict; not installed here); the admin
  "Plugins check" page (only after the new code is in place). Chosen: `core_plugin_manager` read in the container +
  the public `download.moodle.org/api/1.3/pluglist.php`, stdlib Python. Reason: works before the upgrade, offline-testable.
- `audit.py`: collect (docker exec php) → load_directory (cached pluglist) → assess (pure verdict rules) → render md/html.

## Exact commands
```bash
python3 ~/.claude/skills/moodle-upgrade-audit/audit.py --container moodle52-app-1 --label "Moodle 5.2 demo site" \
  --md ~/drop/money/samples/upgrade-audit-5.2.md --html ~/drop/money/samples/upgrade-audit-5.2.html
bash ~/.claude/skills/moodle-upgrade-audit/tests/audit.test.sh
```

## Pitfalls (measured)
- pluglist.php returns HTTP 403 to Python's default `Python-urllib` User-Agent (curl gets 200); send a User-Agent.
- The list is 15.6 MB, 3114 plugins; on 2026-10-19 only 952 version-support entries name 5.3 (5.2: 2958), so many
  "no 5.3 version" rows are maintainers not caught up yet: hence the 365-day rule before saying replace.
- `is_enabled()` is null for most plugin types; only an explicit false means disabled.
- `unshare -rn` is blocked here (uid_map not permitted); `bwrap --unshare-net` works for the no-network test.
- The 5.2 env has 1 add-on (local_aicharts, custom), so its sample shows one row; the fixture covers all 5 rules.

## Links
- Code: ~/.claude/skills/moodle-upgrade-audit/audit.py, SKILL.md
- Tests: ~/.claude/skills/moodle-upgrade-audit/tests/audit.test.sh (fixtures in tests/fixtures/)
- Sample: ~/drop/money/samples/upgrade-audit-5.2.{html,md}
