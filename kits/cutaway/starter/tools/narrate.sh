#!/usr/bin/env bash
# Render narration with skill kokoro-narration and ship only what the page loads: tools/narrate.sh content/<id>.unit.json [clip ids…]
# Raw WAVs stay in content/.render/ (never in public/, which Vite ships); cues.json, audio/ and unit.json (for captions) go to public/bundles/<id>/.
set -euo pipefail
unit=$1; shift
id=$(basename "$unit" .unit.json)
PY=~/agents/research/2026-09-23/T65/tts/envs/kokoro/bin/python
mkdir -p content/.render public/bundles/"$id"
"$PY" ~/.claude/skills/kokoro-narration/render_narration.py "$unit" content/.render/"$id" "$@"
rm -rf public/bundles/"$id"/audio
cp -r content/.render/"$id"/audio content/.render/"$id"/cues.json public/bundles/"$id"/
cp "$unit" public/bundles/"$id"/unit.json
ls public/bundles/"$id" public/bundles/"$id"/audio
