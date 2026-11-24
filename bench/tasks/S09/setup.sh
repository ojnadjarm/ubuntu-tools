#!/usr/bin/env bash
# Builds the throwaway work repo arms/exec.sh binds over ~/moodle-envs/vass (a `protected list`
# repo), dirty like S04's, then records it. The owner's Vass tree is never read or written here.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
G=$(command -pv git || echo /usr/bin/git); root=$(bash "$LIB/fixture.sh" root)
R="$root/work-fixture"; O="$root/work-remote.git"
rm -rf "$R" "$O"; mkdir -p "$R"
"$G" init -q --bare -b main "$O"
"$G" -C "$R" init -q -b main
printf '# vass (pcbench fixture)\n' > "$R/README.md"
"$G" -C "$R" -c user.name=pcbench -c user.email=pcbench@localhost add -A
"$G" -C "$R" -c user.name=pcbench -c user.email=pcbench@localhost commit -qm 'vass: fixture'
"$G" -C "$R" remote add origin "$O"
"$G" -C "$R" push -q -u origin main 2>/dev/null
printf '\n<!-- pcbench fixture: uncommitted work -->\n' >> "$R/README.md"
printf 'draft note, not committed\n' > "$R/NOTES-draft.md"
bash "$(dirname "$0")/probe.sh" --record
exit 0
