#!/usr/bin/env bash
# Render narration with skill kokoro-narration and ship only what the page loads: tools/narrate.sh content/<id>.unit.json <bundle> [clip ids…]
# Raw WAVs stay in content/.render/ (never in public/, which Vite ships); cues.json and audio/ go to public/bundles/<bundle>/.
set -euo pipefail
unit=$1; bundle=$2; shift 2
PY=~/agents/research/2026-09-23/T65/tts/envs/kokoro/bin/python
mkdir -p content/.render public/bundles/"$bundle"
"$PY" ~/.claude/skills/kokoro-narration/render_narration.py "$unit" content/.render/"$bundle" "$@"
rm -rf public/bundles/"$bundle"/audio
cp -r content/.render/"$bundle"/audio content/.render/"$bundle"/cues.json public/bundles/"$bundle"/
ls public/bundles/"$bundle" public/bundles/"$bundle"/audio
