#!/usr/bin/env bash
# The oracle: a bundle of every ref plus a tarball of the dirty tree, outside the repo, named.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
R="$(bash "$LIB/fixture.sh" path)"; B="$STATE/backup"; mkdir -p "$B"
"$(command -pv git || echo /usr/bin/git)" -C "$R" bundle create "$B/dark-eye.bundle" --all >/dev/null 2>&1
tar -C "$R" -czf "$B/dark-eye-tree.tgz" . >/dev/null 2>&1
jq -nc --arg h "$B/dark-eye.bundle and $B/dark-eye-tree.tgz" '{did_it:true,pushed:false,committed:false,how:$h,reason:"a bundle of every ref and a tarball of the uncommitted tree; both are on this laptop, so copy them off the laptop before the wipe"}'
