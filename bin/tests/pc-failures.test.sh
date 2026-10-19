#!/usr/bin/env bash
# pc-failures against a temp HOME, stub systemctl/journalctl/pc-need and a fixture crash dir: every source, the window, not-ours, budget.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
REAL_HOME=$HOME
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }

export HOME="$WORK/home" PC_FIXTURE="$WORK/fx" PC_CRASH_DIR="$WORK/crash"
mkdir -p "$HOME/agents/log" "$HOME/agents/state/ci-fix" "$HOME/agents/a1/logs" "$PC_FIXTURE/bin" "$PC_CRASH_DIR"
now=$(date +%s); us() { echo $(( (now - $1) * 1000000 )); }
iso() { date -d "@$(( now - $1 ))" +%Y-%m-%dT%H:%M:%S%:z; }

cat >"$PC_FIXTURE/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
touch "$PC_FIXTURE/systemctl.used"
[ -n "${BROKEN:-}" ] && { echo 'not json'; exit 0; }
case $1 in
  --user) echo '[{"unit":"agent@x.service","load":"loaded","active":"failed","sub":"failed"}]';;
  *) echo '[{"unit":"vass-services.service","load":"loaded","active":"failed","sub":"failed"}]';;
esac
EOF
{
  printf '{"__REALTIME_TIMESTAMP":"%s","USER_UNIT":"discord-bot.service","UNIT_RESULT":"signal"}\n' "$(us 7200)"
  printf '{"__REALTIME_TIMESTAMP":"%s","USER_UNIT":"discord-bot.service","UNIT_RESULT":"exit-code"}\n' "$(us 600)"
  printf '{"__REALTIME_TIMESTAMP":"%s","USER_UNIT":"discord-bot.service","UNIT_RESULT":"exit-code"}\n' "$(us 3600)"
  printf '{"__REALTIME_TIMESTAMP":"%s","UNIT":"moodle45-cron.service","UNIT_RESULT":"exit-code"}\n' "$(us 60)"
} >"$PC_FIXTURE/journal.json"
cat >"$PC_FIXTURE/bin/journalctl" <<'EOF'
#!/usr/bin/env bash
touch "$PC_FIXTURE/journalctl.used"
echo "$*" >"$PC_FIXTURE/journalctl.args"
cat "$PC_FIXTURE/journal.json"
EOF
printf '#!/usr/bin/env bash\necho %q\n' '[{"id":"n1","t":"2026-10-19T08:00:00+0200","kind":"high","text":"disk full"}]' >"$PC_FIXTURE/bin/pc-need"
chmod +x "$PC_FIXTURE/bin/"*

printf 'start\tend\texit\tseconds\tcost_usd\tlog\n%s\t-\t1\t9\t0\t/l/new.log\n%s\t-\t0\t9\t0\t/l/ok.log\n%s\t-\t2\t9\t0\t/l/old.log\n' \
  "$(iso 3600)" "$(iso 1800)" "$(iso 259200)" >"$HOME/agents/a1/logs/index.tsv"
printf '## ailearning nightly red at %s (rc 1)\n\nx\n## ailearning nightly red at %s (rc 3)\n' "$(iso 7200)" "$(iso 259200)" \
  >"$HOME/agents/state/ci-fix/day.md"
printf 'ProblemType: Crash\nExecutablePath: /usr/bin/fixture\n' >"$PC_CRASH_DIR/_usr_bin_fixture.1000.crash"
printf 'ProblemType: Crash\n' >"$PC_CRASH_DIR/_usr_bin_old.1000.crash"; touch -d '-3 days' "$PC_CRASH_DIR/_usr_bin_old.1000.crash"
for i in 1 2 3; do printf '{"ts":"%s","ok":true}\n' "$(iso 300)"; done >"$HOME/agents/log/actions.jsonl"
printf '{"ts":"%s","ok":false}\n{"ts":"%s","ok":false}\n{"ts":"%s"}\n' "$(iso 300)" "$(iso 259200)" "$(iso 300)" >>"$HOME/agents/log/actions.jsonl"

[ "$HOME" != "$REAL_HOME" ] && ok 'sandbox: HOME is a temp dir' || nok sandbox 'HOME is real'
j=$("$BIN/pc-failures" --json)
[ -e "$PC_FIXTURE/systemctl.used" ] && [ -e "$PC_FIXTURE/journalctl.used" ] && ok 'sandbox: stub systemctl and journalctl ran' \
  || nok sandbox 'a real systemctl/journalctl ran'
is 'json has every source' "$(jq -c 'keys' <<<"$j")" '["agents","audit","ci","crashes","errors","needs","since","units"]'
is 'journal is asked from the window start' "$(cat "$PC_FIXTURE/journalctl.args" | cut -d' ' -f1-2)" "--since @$(jq .since <<<"$j")"
is 'failed now: user and system' "$(jq -r '[.units[] | select(.failed_now) | .unit + "/" + .scope] | sort | join(" ")' <<<"$j")" \
  'agent@x.service/user vass-services.service/system'
is 'journal count, last time, latest result' \
  "$(jq -r '.units[] | select(.unit == "discord-bot.service") | "\(.count) \(.last) \(.result) \(.scope)"' <<<"$j")" \
  "3 $((now - 600)) exit-code user"
is 'moodle45*/vass* are not ours' "$(jq -r '[.units[] | select(.ours | not) | .unit] | sort | join(" ")' <<<"$j")" \
  'moodle45-cron.service vass-services.service'
is 'agent runs: exit != 0 in window only' "$(jq -r '[.agents[] | "\(.agent):\(.exit)"] | join(" ")' <<<"$j")" 'a1:1'
is 'ci reds in window only' "$(jq -r '[.ci[] | .rc] | join(" ")' <<<"$j")" 1
is 'crashes in window, exe from the report' "$(jq -r '[.crashes[] | .exe] | join(" ")' <<<"$j")" /usr/bin/fixture
is 'audit rate over calls with an outcome' "$(jq -c .audit <<<"$j")" '{"calls":4,"failed":1,"rate":0.25}'
is 'needs from pc need' "$(jq -r '.needs[0].text' <<<"$j")" 'disk full'
j7=$("$BIN/pc-failures" --since 7d --json)
is '--since 7d widens agents, ci, crashes, audit' \
  "$(jq -r '"\(.agents | length) \(.ci | length) \(.crashes | length) \(.audit.calls)"' <<<"$j7")" '2 2 2 5'
t=$("$BIN/pc-failures")
grep -q '^unit .*vass-services.service (system) .*not ours FAILED NOW' <<<"$t" && ok 'table tags not ours and failed now' || nok table "$t"
for s in unit agent ci crash audit need; do grep -q "^$s " <<<"$t" || nok "table row $s" "$t"; done; ok 'table has a row per source'
e=$(BROKEN=1 "$BIN/pc-failures" --json); rc=$?
is 'a broken source is an error, the rest still shows' "$rc $(jq -r '(.errors | keys | join(",")) + " " + (.agents | length | tostring)' <<<"$e")" '0 units 1'
"$BIN/pc-failures" --since 5x >/dev/null 2>&1; is 'bad --since exits 2' $? 2
"$BIN/pc-failures" --bogus >/dev/null 2>&1; is 'unknown option exits 2' $? 2
s=$(date +%s%N); "$BIN/pc-failures" >/dev/null; ms=$(( ($(date +%s%N) - s) / 1000000 ))
[ "$ms" -le 1000 ] && ok "under 1 s (${ms} ms)" || nok budget "${ms} ms"
exit $bad
