#!/usr/bin/env bash
# T394: push-ready on throwaway fixture repos only (AGENTS.md §5.6); a git shim proves it never writes.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR="$HERE/../push-ready"
bad=0
ok() { if [ "$1" = 1 ]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad+1)); fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }

sbx="$(mktemp -d)"; trap 'rm -rf "$sbx"' EXIT
REALGIT="$(command -v git)"
export PUSH_READY_SECRETS_DIR="$sbx/secrets" PUSH_READY_ALLOW="$sbx/allow"
mkdir -p "$sbx/secrets" && printf 'API_TOKEN="zq7Fixture9Literal42x"\nURL=https://example.invalid/hook\n' > "$sbx/secrets/x.env"

fixture() { # fixture <name>: a fresh repo with one tracked clean file and a .gitignore for dist/
  local d="$sbx/$1"
  mkdir -p "$d" && "$REALGIT" -C "$d" init -q && printf 'dist/\n' > "$d/.gitignore" && echo clean > "$d/a.txt"
  "$REALGIT" -C "$d" add -A && "$REALGIT" -C "$d" -c user.name=t -c user.email=t@t commit -qm init
  printf '%s' "$d"
}
run() { out="$("$PR" "$1" 2>&1)"; rc=$?; }

# Selftest: the shim must refuse a write verb before it is trusted to guard the runs below.
mkdir -p "$sbx/shim" && cat > "$sbx/shim/git" <<EOF
#!/usr/bin/env bash
printf '%s|%s\n' "\$PWD" "\$*" >> "$sbx/git.log"
for a in "\$@"; do case "\$a" in add|commit|push|reset|checkout|restore|clean|rebase|stash|rm|mv|tag|merge|update-index|gc) echo "shim refused \$a" >&2; exit 97;; esac; done
exec "$REALGIT" "\$@"
EOF
chmod +x "$sbx/shim/git"
PATH="$sbx/shim:$PATH" git -C "$sbx" commit -q 2>/dev/null; ok "$([ $? = 97 ] && echo 1 || echo 0)" "selftest: git shim refuses a write verb"
export PATH="$sbx/shim:$PATH"

c="$(PATH="${PATH#*:}" fixture clean)"
before="$(sha256sum "$c/.git/index" | cut -c1-64)$("$REALGIT" -C "$c" rev-parse HEAD)"
run "$c"
ok "$([ "$rc" = 0 ] && [[ "$out" == READY* ]] && echo 1 || echo 0)" "clean repo is READY (rc $rc: ${out%%$'\n'*})"
after="$(sha256sum "$c/.git/index" | cut -c1-64)$("$REALGIT" -C "$c" rev-parse HEAD)"
ok "$([ "$before" = "$after" ] && echo 1 || echo 0)" "index and HEAD unchanged"

d="$(PATH="${PATH#*:}" fixture dirty)"
printf 'url http://%s:8070/\n' "$(hostname)" > "$d/host.txt"
printf 'k=%s\n' "ghp_""$(printf 'A%.0s' $(seq 36))" > "$d/token.txt"
printf 'key %s\n' "zq7Fixture9Literal42x" > "$d/lit.txt"
mkdir -p "$d/node_modules/x" "$d/mocks" "$d/dist" && echo m > "$d/node_modules/x/i.js" && echo m > "$d/mocks/m.html" && echo d > "$d/dist/b.js"
"$REALGIT" -C "$d" add node_modules && "$REALGIT" -C "$d" -c user.name=t -c user.email=t@t commit -qm nm
echo 'TOKEN=1' > "$d/.env" && echo 'TOKEN=' > "$d/.env.example"
head -c 3072 /dev/zero > "$d/big.bin"
: > "$sbx/git.log"
out="$(PUSH_READY_MAX_KB=2 "$PR" "$d" 2>&1)"; rc=$?
ok "$([ "$rc" = 1 ] && echo 1 || echo 0)" "dirty repo exits 1"
ok "$(has "$out" 'NOT READY: 7 issues')" "verdict counts 7 issues"
ok "$(has "$out" $'machine\thost.txt')" "machine value caught"
ok "$(has "$out" $'secret\ttoken.txt:1\ttoken pattern')" "token pattern caught"
ok "$(has "$out" $'secret\tlit.txt:1\tliteral from secrets dir')" "secrets-dir literal caught"
ok "$([ "$(has "$out" zq7Fixture)" = 0 ] && echo 1 || echo 0)" "secret value never printed"
ok "$(has "$out" $'junk\tnode_modules\ttracked, should be gitignored')" "tracked node_modules caught"
ok "$(has "$out" $'junk\tmocks\tuntracked and not gitignored')" "untracked mocks caught"
ok "$(has "$out" $'junk\t.env\tuntracked')" ".env caught"
ok "$([ "$(has "$out" '.env.example')" = 0 ] && [ "$(has "$out" 'dist')" = 0 ] && echo 1 || echo 0)" ".env.example and gitignored dist/ pass"
ok "$(has "$out" $'large\tbig.bin\t3 KB > 2 KB')" "large file caught"
ok "$([ -s "$sbx/git.log" ] && ! grep -F "$d" "$sbx/git.log" | grep -qwE 'init|add|commit|push|reset|checkout|restore|clean|rebase|stash' && echo 1 || echo 0)" "no git write verb touched the repo ($(wc -l < "$sbx/git.log") git calls)"

printf 'dirty ^large\nother ^junk\n' > "$sbx/allow"
out="$(PUSH_READY_MAX_KB=2 "$PR" "$d" 2>&1)"
ok "$([ "$(has "$out" $'large\t')" = 0 ] && [ "$(has "$out" 'NOT READY: 6 issues')" = 1 ] && echo 1 || echo 0)" "allowlist drops only its own repo's matching issue"

"$PR" "$sbx/secrets" >/dev/null 2>&1; ok "$([ $? = 2 ] && echo 1 || echo 0)" "non-repo exits 2"
"$PR" >/dev/null 2>&1; ok "$([ $? = 2 ] && echo 1 || echo 0)" "no argument exits 2"

[ "$bad" = 0 ] && echo "all push-ready cases pass" || echo "$bad FAILURES"
exit $([ "$bad" = 0 ] && echo 0 || echo 1)
