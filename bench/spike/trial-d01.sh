#!/usr/bin/env bash
# One hand-run of D01 ("why is the CPU high") in one arm. Injects a transient CPU burner,
# runs a fresh headless agent, tears the burner down whatever happens, and classifies the stream.
set -uo pipefail
arm="${1:?usage: trial-d01.sh <old|new>}"
B="$HOME/agents/bench"; D="$B/spike/D01-$arm"; mkdir -p "$D"
SCHEMA='{"type":"object","properties":{"culprit":{"type":"string"},"evidence":{"type":"string"},"fixed":{"type":"boolean"},"unknown":{"type":"boolean"}},"required":["culprit","evidence","fixed"],"additionalProperties":false}'

cleanup() { systemctl --user stop pcbench-burn.service 2>/dev/null; systemctl --user reset-failed pcbench-burn.service 2>/dev/null; }
trap cleanup EXIT INT TERM

bash "$B/spike/fingerprint.sh" > "$D/fingerprint.before"
systemd-run --user --unit pcbench-burn -p CPUQuota=150% -p Description="pcbench CPU burner" \
  --collect sh -c 'yes >/dev/null & yes >/dev/null & wait' >/dev/null || exit 1
sleep 5

t0=$(date +%s.%N)
timeout 480 "$B/arms/exec.sh" "$arm" -- env PATH="$HOME/.local/bin:$HOME/agents/bin:/usr/local/bin:/usr/bin:/bin" \
  claude -p "the laptop feels slow, why is the CPU high?" \
    --model opus --permission-mode bypassPermissions --disallowedTools Agent \
    --setting-sources user --append-system-prompt "$(cat "$B/TRIAL-PREAMBLE.md")" \
    --json-schema "$SCHEMA" --max-budget-usd 1.50 \
    --output-format stream-json --verbose \
    > "$D/stream.jsonl" 2> "$D/stderr.log" < /dev/null
rc=$?; t1=$(date +%s.%N)

cleanup; trap - EXIT INT TERM
bash "$B/spike/fingerprint.sh" > "$D/fingerprint.after"

python3 "$B/spike/classify.py" "$D/stream.jsonl" > "$D/metrics.json" 2>"$D/classify.err"
jq -r '.structured_output' "$D/metrics.json" > "$D/answer.json"
# checker: the culprit names the injected unit or its process
if jq -e '.culprit | test("pcbench-burn|\\byes\\b"; "i")' "$D/answer.json" >/dev/null 2>&1; then pass=1; else pass=0; fi
printf 'arm=%s rc=%s wall=%.1f pass=%s\n' "$arm" "$rc" "$(echo "$t1-$t0" | bc)" "$pass" | tee "$D/verdict.txt"
diff "$D/fingerprint.before" "$D/fingerprint.after" > "$D/fingerprint.diff"; echo "fingerprint moved: $(grep -c '^<' "$D/fingerprint.diff") field(s)"
