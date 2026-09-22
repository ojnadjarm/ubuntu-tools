#!/usr/bin/env bash
# TSP-005: agent-run records tokens and a tool histogram per run in logs/index.tsv.
# Sandbox only (AGENTS.md §5.6): HOME is a temp dir, `claude` and `notify-owner` are stubs on
# the fleet PATH, so no model call, no push and no live agent folder is touched. A selftest
# proves the stubs are the ones that run before any agent-run is invoked.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$BIN/.." && pwd)"
fail=0
t() { printf '%-56s' "agent-run: $1"; }
ok() { echo OK; }
no() { echo "FAIL — $1"; fail=1; }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/agents/bin" "$SB/agents/adapters/claude" "$SB/agents/demo"
cp "$BIN/agent-run" "$BIN/agent-exec" "$BIN/fleetlib.sh" "$BIN/env.sh" "$SB/agents/bin/"
cp -r "$BIN/guards" "$SB/agents/bin/guards"
cp "$ROOT/adapters/claude/run" "$SB/agents/adapters/claude/run"
printf 'preamble\n' >"$SB/agents/AGENT-PREAMBLE.md"
printf 'do nothing\n' >"$SB/agents/demo/BRIEF.md"

cat >"$SB/agents/bin/notify-owner" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HOME/notify.log"
EOS

cat >"$SB/agents/bin/claude" <<'EOS'
#!/usr/bin/env bash
# Canned stream stub: no model, no network. Records its flags for the test.
printf '%s\n' "$*" >>"$HOME/claude-args.log"
case "$*" in
  *"stream-json"*)
    cat <<'JSON'
{"type":"system","subtype":"init","session_id":"stub"}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"},{"type":"text","text":"hi"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read"}]}}
{"type":"result","subtype":"success","session_id":"stub","result":"done","usage":{"input_tokens":1234,"output_tokens":567,"cache_read_input_tokens":89012,"cache_creation_input_tokens":345}}
JSON
    ;;
  *) printf '%s\n' '{"type":"result","result":"done","usage":{"input_tokens":1234,"output_tokens":567,"cache_read_input_tokens":89012}}' ;;
esac
EOS
chmod +x "$SB/agents/bin/notify-owner" "$SB/agents/bin/claude"

run_agent() {  # run_agent [HARNESS_AGENT value]
  env -i HOME="$SB" PATH=/usr/bin:/bin TERM=dumb \
      HARNESS_CONFIG=/nonexistent HARNESS_HOME="$SB/agents" HARNESS_AGENT="${1:-claude}" \
      bash "$SB/agents/bin/agent-run" demo >/dev/null 2>&1
}
idx="$SB/agents/demo/logs/index.tsv"

t "selftest: the sandbox runs the stubs, never the real claude"
sb_claude="$(env -i HOME="$SB" PATH=/usr/bin:/bin bash -c \
  '. "$HOME/agents/bin/fleetlib.sh"; fleet_path; command -v claude')"
{ [ "$sb_claude" = "$SB/agents/bin/claude" ] && grep -q 'Canned stream stub' "$sb_claude"; } \
  && ok || { no "PATH would reach $sb_claude"; echo "aborting"; exit 1; }

run_agent claude

t "a fresh index.tsv header carries the five new columns"
[ "$(head -1 "$idx")" = "$(printf 'start\tend\texit\tseconds\tcost_usd\tlog\ttokens_in\ttokens_out\tcache_r\ttool_calls\thistogram')" ] \
  && ok || no "$(head -1 "$idx")"

t "the run row carries tokens, cache reads, tool calls and the histogram"
[ "$(awk -F'\t' 'NR==2{print $7,$8,$9,$10,$11}' "$idx")" = "1234 567 89012 3 Bash=2,Read=1" ] \
  && ok || no "$(awk -F'\t' 'NR==2{print}' "$idx")"

t "the adapter asks for the stream format that carries tool events"
grep -q -- '--output-format stream-json' "$SB/claude-args.log" &&
  grep -q -- '--verbose' "$SB/claude-args.log" && ok || no "$(cat "$SB/claude-args.log")"

t "no new money column: cost_usd stays the only one"
[ "$(head -1 "$idx" | tr '\t' '\n' | grep -ciE 'cost|usd|price|spend')" = 1 ] \
  && ok || no "$(head -1 "$idx")"

t "the stub run pushed nothing to the owner"
[ ! -s "$SB/notify.log" ] && ok || no "$(cat "$SB/notify.log")"

t "a second run appends a second row, header written once"
run_agent claude
[ "$(wc -l <"$idx")" = 3 ] && [ "$(grep -c tokens_in "$idx")" = 1 ] \
  && ok || no "$(cat "$idx")"

t "the direct (no adapter) path fills the token columns too"
rm -rf "$SB/agents/demo/logs"; run_agent ""
[ "$(awk -F'\t' 'NR==2{print $7,$8,$9}' "$idx")" = "1234 567 89012" ] \
  && ok || no "$(awk -F'\t' 'NR==2{print}' "$idx")"

t "a legacy index.tsv gains the columns in the header only, rows untouched"
rm -rf "$SB/agents/demo/logs"; mkdir -p "$SB/agents/demo/logs"
printf 'start\tend\texit\tseconds\tcost_usd\tlog\n' >"$idx"
old="$(printf '2026-01-01T00:00:00+01:00\t2026-01-01T00:01:00+01:00\t0\t60\t\t/old.log')"
printf '%s\n' "$old" >>"$idx"
run_agent claude
{ [ "$(sed -n 2p "$idx")" = "$old" ] && head -1 "$idx" | grep -q 'histogram' &&
  [ "$(awk -F'\t' 'NR==3{print $7}' "$idx")" = 1234 ] && [ "$(wc -l <"$idx")" = 3 ]; } \
  && ok || no "$(cat "$idx")"

t "toolsmith-inputs reports the columns from the produced index"
[ "$(TOOLSMITH_ROOT="$SB/agents" HARNESS_HOME=/nonexistent "$BIN/toolsmith-inputs" --since 9999d \
     2>/dev/null | jq -c '[.tokens.columns_present,.tokens.agents.demo.in_per_run,
     .tokens.agents.demo.tool_histogram.Bash]')" = '[true,1234,2]' ] \
  && ok || no "$(TOOLSMITH_ROOT="$SB/agents" HARNESS_HOME=/nonexistent "$BIN/toolsmith-inputs" \
     --since 9999d 2>/dev/null | jq -c .tokens)"

[ $fail = 0 ] && echo "agent-run.test.sh: all green" || echo "agent-run.test.sh: FAILURES"
exit $fail
