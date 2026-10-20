#!/usr/bin/env bash
# reference/pitfalls.md: every scripts/<name>, --flag and env name exists in the skill, every pitfall cites a T-id.
set -u
SKILL=$(cd "$(dirname "$0")/.." && pwd)
EXTERNAL="VK_INSTANCE_LAYERS VK_LOADER_DEBUG"
fail=0 pass=0

check() { # check DOC SKILL_DIR -> prints MISSING lines, returns their count
	local doc=$1 dir=$2 n=0 name
	for name in $(grep -oE 'scripts/[A-Za-z0-9_.-]+' "$doc" | sort -u); do
		[ -e "$dir/$name" ] || { echo "MISSING script $name"; n=$((n + 1)); }
	done
	for name in $(grep -oE '(^|[^A-Za-z0-9_-])--[a-z][a-z0-9-]*' "$doc" | grep -oE -- '--[a-z0-9-]+' | sort -u); do
		grep -rqF --exclude="$(basename "$doc")" --exclude=gamedev-docs.test.sh -- "$name" "$dir" ||
			{ echo "MISSING flag $name"; n=$((n + 1)); }
	done
	for name in $(grep -oE '`\$?[A-Z][A-Z0-9]*(_[A-Z0-9]+)+[=/`]' "$doc" | tr -d '`$=/' | sort -u); do
		case " $EXTERNAL " in *" $name "*) continue ;; esac
		grep -rqwF --exclude="$(basename "$doc")" --exclude=gamedev-docs.test.sh -- "$name" "$dir" ||
			{ echo "MISSING env $name"; n=$((n + 1)); }
	done
	n=$((n + $(awk '/^- /{if(b!="")print b; b=$0; next} /^  /&&b!=""{b=b" "$0; next} {if(b!="")print b; b=""} END{if(b!="")print b}' "$doc" |
		grep -vE '\(T[0-9]{3}' | sed 's/^/MISSING T-id: /' | cut -c1-120 | tee /dev/stderr | wc -l)))
	return "$n"
}

ok() { if eval "$2"; then pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/skill/scripts" "$tmp/skill/reference"
printf -- '--real-flag REAL_ENV\n' >"$tmp/skill/scripts/real.sh"
cat >"$tmp/skill/reference/pitfalls.md" <<'EOF'
- good `scripts/real.sh --real-flag` with `REAL_ENV=1` (T100)
- bad `scripts/gone.sh --no-such-flag` with `NO_SUCH_ENV=1`
  and a wrapped line (T101)
- no ticket here
EOF
out=$(check "$tmp/skill/reference/pitfalls.md" "$tmp/skill" 2>&1); rc=$?
ok "selftest finds 4 bad references (rc=$rc)" '[ "$rc" -eq 4 ]'
ok "selftest names the missing script" 'grep -q "MISSING script scripts/gone.sh" <<<"$out"'
ok "selftest names the missing flag" 'grep -q "MISSING flag --no-such-flag" <<<"$out"'
ok "selftest names the missing env" 'grep -q "MISSING env NO_SUCH_ENV" <<<"$out"'
ok "selftest flags the pitfall without a T-id" 'grep -q "MISSING T-id: - no ticket here" <<<"$out"'

out=$(check "$SKILL/reference/pitfalls.md" "$SKILL" 2>&1); rc=$?
[ -n "$out" ] && echo "$out"
ok "pitfalls.md references are real (rc=$rc)" '[ "$rc" -eq 0 ]'
ok "pitfalls.md has >= 8 cited pitfalls" '[ "$(grep -cE "\(T[0-9]{3}" "$SKILL/reference/pitfalls.md")" -ge 8 ]'

echo "gamedev-docs: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
