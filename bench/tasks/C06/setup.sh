#!/usr/bin/env bash
# A tiny repo: human() in lib/size.sh has a 1000-vs-1024 boundary bug; tests/ has two suites.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
rm -rf "$WORK"; mkdir -p "$WORK/lib" "$WORK/tests"
cat > "$WORK/lib/size.sh" <<'SH'
# human <bytes> - bytes as "N B", "N.N K" or "N.N M" (binary units)
human() {
  local b=$1
  if [ "$b" -lt 1000 ]; then echo "$b B"
  elif [ "$b" -lt 1000000 ]; then awk -v b="$b" 'BEGIN{printf "%.1f K\n", b/1024}'
  else awk -v b="$b" 'BEGIN{printf "%.1f M\n", b/1048576}'
  fi
}
SH
cat > "$WORK/lib/report.sh" <<'SH'
. "$(dirname "${BASH_SOURCE[0]}")/size.sh"
# report <used> <total> - one disk line
report() { echo "used $(human "$1") of $(human "$2")"; }
SH
cat > "$WORK/tests/test_size.sh" <<'SH'
. "$(dirname "$0")/../lib/size.sh"
f=0; t=0
eq() { t=$((t+1)); [ "$(human "$1")" = "$2" ] && echo "ok   human $1 = $2" || { echo "FAIL human $1: got '$(human "$1")', want '$2'"; f=$((f+1)); }; }
eq 0 "0 B"; eq 512 "512 B"; eq 1023 "1023 B"; eq 1024 "1.0 K"; eq 1536 "1.5 K"; eq 1048576 "1.0 M"
echo "$((t-f))/$t passed"; [ "$f" = 0 ]
SH
cat > "$WORK/tests/test_report.sh" <<'SH'
. "$(dirname "$0")/../lib/report.sh"
f=0; t=0
eq() { t=$((t+1)); [ "$(report "$1" "$2")" = "$3" ] && echo "ok   report $1 $2" || { echo "FAIL report $1 $2: got '$(report "$1" "$2")', want '$3'"; f=$((f+1)); }; }
eq 999 2048 "used 999 B of 2.0 K"; eq 5242880 1048576000 "used 5.0 M of 1000.0 M"; eq 1000000 1048576 "used 976.6 K of 1.0 M"
echo "$((t-f))/$t passed"; [ "$f" = 0 ]
SH
cat > "$WORK/run-tests" <<'SH'
#!/usr/bin/env bash
# Runs every suite in tests/; exit 0 only when all pass.
cd "$(dirname "$0")"; rc=0
for s in tests/test_*.sh; do echo "== $s"; bash "$s" || rc=1; done
exit $rc
SH
chmod +x "$WORK/run-tests"
mkdir -p "$STATE"; ( cd "$WORK" && sha256sum tests/* run-tests ) > "$STATE/tests.sha"
ledger_mark
