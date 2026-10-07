#!/usr/bin/env bash
# Build and drop under the unit's own name: tools/drop.sh <name> <sub> → https://<tailnet>:8470/<sub>/<name>/
# drop-link names the dropped folder after the source folder, so dist/ is staged as out/drop/<name> first.
set -euo pipefail
name=$1; sub=$2
npx vite build >/dev/null
rm -rf out/drop && mkdir -p out/drop && cp -r dist out/drop/"$name"
drop-link out/drop/"$name" "$sub"
