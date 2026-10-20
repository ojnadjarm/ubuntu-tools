#!/usr/bin/env bash
# body-sandbox.test.sh skip-unchanged (T852) on a git fixture with a stub body test and a fake HOME; never reads ~/the-dark-eye.
set -uo pipefail
w="$(cd "$(dirname "$0")" && pwd)/body-sandbox.test.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
repo="$t/eye" stamp="$t/state/body-sandbox.green" runs="$t/runs" fail=0
ok() { if [ "$2" = 1 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

case "$repo" in "$t"/*) ;; *) echo "FAIL selftest: fixture outside tmp"; exit 1;; esac
mkdir -p "$repo/body/test" && cd "$repo" && git init -q && git config user.email t@t && git config user.name t
printf '#!/usr/bin/env bash\necho run >> "%s"; exit "${STUB_RC:-0}"\n' "$runs" > body/test/body-sandbox.test.sh
echo a > body/a.js && git add -A && git commit -qm init
snap() { find "$repo/.git" -newer "$t/mark" -print | grep -c .; }
touch "$t/mark"; sleep 1

go() { env -u FLEET_CI_FULL HOME="$t/home" BODY_SANDBOX_REPO="$repo" BODY_SANDBOX_STAMP="$stamp" FLEET_CI_DOW="${DOW:-3}" "$@" bash "$w"; }
n() { grep -c . "$runs" 2>/dev/null || echo 0; }

out=$(go); rc=$?
ok "green run: rc 0, stub ran, stamp written" "$([ $rc = 0 ] && [ "$(n)" = 1 ] && [ -s "$stamp" ] && echo 1)"
out=$(go); rc=$?
ok "unchanged: SKIP unchanged, rc 0, stub not run" "$([ $rc = 0 ] && [ "$(n)" = 1 ] && grep -q '^SKIP unchanged body (green [0-9-]*)' <<<"$out" && echo 1)"
echo b > body/a.js
go >/dev/null
ok "dirty tracked file: runs again" "$([ "$(n)" = 2 ] && echo 1)"
echo c > body/a.js
go >/dev/null
ok "further edit of a dirty file: runs again" "$([ "$(n)" = 3 ] && echo 1)"
echo u > body/new.js
go >/dev/null
ok "untracked file: runs again" "$([ "$(n)" = 4 ] && echo 1)"
DOW=7 go >/dev/null
ok "Sunday: runs although unchanged" "$([ "$(n)" = 5 ] && echo 1)"
go FLEET_CI_FULL=1 >/dev/null
ok "FLEET_CI_FULL=1: runs although unchanged" "$([ "$(n)" = 6 ] && echo 1)"
before=$(cat "$stamp"); echo d > body/a.js
go STUB_RC=1 >/dev/null; rc=$?
ok "red: rc 1, stamp unchanged" "$([ $rc = 1 ] && [ "$(cat "$stamp")" = "$before" ] && echo 1)"
go >/dev/null
ok "after red: runs again" "$([ "$(n)" = 8 ] && echo 1)"
rm -rf "$t/nogit" && mkdir -p "$t/nogit/body/test" && cp body/test/body-sandbox.test.sh "$t/nogit/body/test/"
go BODY_SANDBOX_REPO="$t/nogit" >/dev/null; go BODY_SANDBOX_REPO="$t/nogit" >/dev/null
ok "non-git repo: always runs" "$([ "$(n)" = 10 ] && echo 1)"
ok "no write in the fixture's .git (GIT_OPTIONAL_LOCKS=0)" "$([ "$(snap)" = 0 ] && echo 1)"
ok "nothing written under the fake HOME" "$([ ! -e "$t/home" ] && echo 1)"
exit "$fail"
