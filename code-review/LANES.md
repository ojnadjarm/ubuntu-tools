# code-review lanes — binding rules for every swarm agent

You are one lane of the weekly code-review swarm (T74). Architecture: `~/agent-work/research/2026-09-24/T74/architecture.md`.
Your prompt says which lane you are, the run's home (`home`; a fixture home in selftests) and the run dir.

## Boundaries
1. Edit only paths where `code-review policy <path>` prints `edit` (retire lanes: `edit` or `retire-only`).
   `review-only` (owner repos: the-dark-eye, moodle-harness, moodle-envs, projects; harness and synced skills) and
   `forbidden` (backups, secrets, asr-corpus, research, AGENTS.md, FLEET.md, CLAUDE.md files, settings.json, and the
   swarm's own containment: code-review CLI/sandbox/netproxy, guards, agent-exec/agent-run/fleetlib, adapters/claude,
   this folder's BRIEF/LANES/swarm.js/agent.env/selftest/state, the audit log, FILE-CLAIMS.md, .git) are never written.
   The sandbox mounts them read-only (secrets and the voice corpus are hidden, the network reaches only the Claude API);
   a write or connect error there is the rule working, not a bug to route around.
2. FLEET.md §5 in full: no git commit or push, no stopping or restarting `dark-eye*`, `docker*`, `sentinel*`, `tailscaled`,
   `sshd` or any `agent@` unit, no reboot, no `pc … --apply`, no sound, no TV, no notify-owner (only `code-review finish` pushes).
3. Tests and reproductions run against fixtures, temp copies (`mktemp -d`) and sandboxes, never real services,
   credentials, the voice corpus or a real unit.
4. Review lanes and refuters are read-only: they may run read-only commands and scratch copies, never edit the tree.
   A review lane given a `FOCUS` list reads only those files (changed since the last run, then the rotation quarter); every 4th run is a full sweep.
5. A change that needs a reboot, a package install, a new or changed systemd unit, or a `settings.json` edit is not
   applied: it becomes an `improve/queue` item (`code-review queue-new`, then `improve-gate check <file>` must print `ok`).
6. Respect `FILE-CLAIMS.md`: `code-review claim <id> <paths…>` before editing; rc 3 = another ticket holds it, skip.
   `code-review unclaim <id>` when done, whatever the outcome.

## Evidence
- Every finding cites `path:line` and, for the data lens, the real log line, count or timing that contradicts the code.
- Judge by usefulness, never by how often something is used. An item may be retired only when it is not useful:
  broken beyond a reasonable fix, fully duplicated by another item that does the job at least as well, superseded by a
  better existing package with every caller migrated, or solving a problem that no longer exists. The finding argues
  which (`retire_reason`), the refuters ask "what would a future agent lose without this?", and `code-review retire`
  refuses without `--why` (and `--by` + `--proof` of a side-by-side run for duplicate/superseded) or while any reference
  remains. A useful but rarely used item gets a discoverability fix (guide INDEX line, trigger words, skill description).
- `code-review usage` is context only; it is never a retirement reason.
- Numbers you did not measure are marked as estimates. "Should work" is not a result.

## Fix discipline (fix lanes)
claim → backup → `code-review tests <id> before` → failing test or reproduction first → minimal fix → your test passes →
matching guide in `KB/guides/` corrected (T72 rule) → `code-review tests <id> after` prints `verified` → unclaim.
Not verified (rc 5): `code-review restore <run> <id>` and report `reverted`. A fix lane never deletes, moves or empties a
file; only `code-review retire` removes items. `fixed` without a verified test record is restored by `finish`.
Comments: one short line per docblock at most.

## Toolsmith lane
`code-review prep` hands in up to 3 open `auto-ok` proposals with status `go` (first) or `proposed` from
`toolsmith/BACKLOG.md` (never `owner-go`, never `hold`: `hold` is the owner's veto). The proposal file is the finding and its Success check is the
acceptance; Boundaries 1–6 and the fix discipline apply unchanged, with the proposal file and `BACKLOG.md` in the backup.
Never run pcbench. On success append `## Result` (what landed, the before number re-read) and change only that row's
status word to `measuring`; on `reverted`, append `## Result: reverted <why>` and leave the status as it was. Both files are
append-only for this lane: `finish` restores the whole fix when an earlier proposal line or anything but a status word
in `BACKLOG.md` changed.

## Output
Return only the schema object. Keep `evidence` and `note` under 300 characters each.
