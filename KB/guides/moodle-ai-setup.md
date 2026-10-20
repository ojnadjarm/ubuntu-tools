# Set up Moodle AI: provider, placements, role access, hourly limits, usage policy

Ticket: T424 · Last verified: 2026-10-20 by `ai-setup --help`, code read, moodle53-app-1 up; test 2026-10-19 tests/setup.test.sh (21/21) on the moodle53 throwaway env

## When to use
Turning on Moodle's built-in AI (4.5+) for a site: days 3-6 of the Moodle AI offer, or re-checking that a site still
matches its AI setup. Not for the Vass/4.5 site or the 5.2 dev site (real aicharts key). Custom AI plugins: out of scope.

## The path we took
Survey: core `\core_ai\manager` already has create/update/enable provider instance; placements are plugins
(`aiplacement::enable_plugin`); rate limits are provider-instance config keys; the policy text is the lang string
`core_ai/userpolicy` (no admin setting), so it goes in a local language pack like tool_customlang does. No CLI or
contrib tool covered this; local_ai_manager is a different (credit) model. Chosen: a bash front plus one PHP
reconciler piped into the app container, so nothing is installed on the site.

## Exact commands
```bash
~/.claude/skills/moodle-ai-setup/ai-setup moodle53 --provider ollama --roles editingteacher --limit 20
~/.claude/skills/moodle-ai-setup/ai-setup moodle53 --check
bash ~/.claude/skills/moodle-ai-setup/tests/setup.test.sh
```

## Pitfalls (measured)
- Placement actions with no config row count as enabled (`is_action_enabled` returns true on `false`); the tool
  writes `1` explicitly so `--check` is exact. First run on a fresh 5.3: 20 changes, second run 0.
- Default archetypes allow all 4 placement caps to manager, editingteacher, teacher and student; "only these roles"
  therefore means 12 prevents at system context for `--roles editingteacher`.
- Run PHP as `-u www-data`: as root the policy file and caches in moodledata become root-owned.
- `generate_image` placement action has no Ollama backend; it stays enabled but unused with Ollama.

## Links
- Code: ~/.claude/skills/moodle-ai-setup/{ai-setup,apply.php,policy.en.html}
- Tests: `bash ~/.claude/skills/moodle-ai-setup/tests/setup.test.sh` (offline fake docker in bwrap, then live moodle53)
- Design / results: ~/.claude/skills/moodle-ai-setup/SKILL.md (Architecture), backlog ~/agent-work/research/2026-10-19/T411/BACKLOG.md #12
