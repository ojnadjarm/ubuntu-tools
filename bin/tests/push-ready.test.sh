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

uid="/run/user/$((4000 + 242))"; tok="ghp_$(printf 'B%.0s' $(seq 36))"
r="$(PATH="${PATH#*:}" fixture rules)"
mkdir -p "$r/tests/fixtures/p" "$r/tests/fixtures/toolsmith/mock" "$r/tests/fixtures/q/node_modules"
echo "0::/user.slice/user-$((4000 + 242)).slice/x $uid/bus" > "$r/tests/fixtures/p/cgroup"
echo '{}' > "$r/tests/fixtures/toolsmith/mock/d.json"
echo 'TOKEN=1' > "$r/tests/fixtures/q/.env" && echo m > "$r/tests/fixtures/q/node_modules/i.js"
echo "sock=$uid/bus" > "$r/run.sh"
printf 'T = "%s"  # push-ready: test vector\n' "$tok" > "$r/tests/v.py"
printf 'T = "%s"\n' "$tok" > "$r/tests/w.py"
out="$("$PR" "$r" 2>&1)"
ok "$(has "$out" 'NOT READY: 4 issues')" "rules fixture counts 4 issues (${out%%$'\n'*})"
ok "$(has "$out" $'machine\trun.sh:1\thardcoded uid path')" "uid path outside tests/fixtures caught"
ok "$([ "$(has "$out" 'tests/fixtures/p')" = 0 ] && [ "$(has "$out" 'toolsmith')" = 0 ] && echo 1 || echo 0)" "tests/fixtures: no uid or mock-name issue (recorded data)"
ok "$(has "$out" $'junk\ttests/fixtures/q/.env\tuntracked')" "a real .env under tests/fixtures still caught"
ok "$(has "$out" $'junk\ttests/fixtures/q/node_modules\tuntracked')" "node_modules under tests/fixtures still caught"
ok "$(has "$out" $'secret\ttests/w.py:1\ttoken pattern')" "unmarked token caught"
ok "$([ "$(has "$out" 'tests/v.py')" = 0 ] && echo 1 || echo 0)" "token line marked 'push-ready: test vector' skipped"

s="$(PATH="${PATH#*:}" fixture shared)"
mkdir -p "$s/tests/fixtures/p" && echo "0::/user.slice/user-$((4000 + 242)).slice/x $uid/bus" > "$s/tests/fixtures/p/cgroup"
printf 'url http://%s:8070/\n' "$(hostname)" > "$s/host.txt"
nmv="$(NO_MACHINE_VALUES_SKIP='^$' bash "$HERE/no-machine-values.test.sh" "$s" 2>&1 | awk '/^FAIL no machine values in /{on=1; next} on && /^ +[0-9]+ [^ ]/ {print $2}' | sort | tr '\n' ' ')"
prm="$("$PR" "$s" 2>&1 | awk -F'\t' '$1 ~ /machine$/ {sub(/:.*/,"",$2); print $2}' | sort -u | tr '\n' ' ')"
ok "$([ -n "$nmv" ] && [ "$nmv" = "$prm" ] && echo 1 || echo 0)" "no-machine-values and push-ready agree on a shared fixture ($nmv| $prm)"

u="$(PATH="${PATH#*:}" fixture untr)"
mkdir -p "$u/tests" "$u/bin" "$u/hooks" "$u/units" "$u/lib/pkg" "$u/skills/s/templates/t"
printf '"$B/tool" --help\ncp -r "$HERE/../templates/t" x\n' > "$u/tests/a.test.sh"
printf 'exec python3 "${self%%/*}/h-impl.py"\n' > "$u/hooks/h.py"
printf '{"command": "@HOME@/hooks/img.py"}\n' > "$u/conf.json"
printf 'for u in "$D"/units/*; do cp "$u" x; done\n' > "$u/install.sh"
"$REALGIT" -C "$u" add tests hooks conf.json install.sh && "$REALGIT" -C "$u" -c user.name=t -c user.email=t@t commit -qm t
printf 'from pkg import m\n' > "$u/bin/tool"
echo x > "$u/bin/stray" && echo 'usage: selfy' > "$u/bin/selfy" && echo x > "$u/skills/s/templates/t/main.c"
echo x > "$u/hooks/h-impl.py" && echo x > "$u/hooks/img.py" && echo x > "$u/units/x.service" && echo x > "$u/lib/pkg/m.py"
printf '"$B/tool" ok\n' > "$u/tests/tool2.test.sh"
printf 'import img\n' > "$u/hooks/img.test.py"
printf '"$B/stray" --help\n' > "$u/tests/orphan.test.sh"
: > "$sbx/git.log"
out="$("$PR" --untracked "$u" 2>&1)"; rc=$?
ok "$([ "$rc" = 0 ] && echo 1 || echo 0)" "--untracked exits 0"
ok "$(has "$out" 'UNTRACKED: 11 files in untr, 8 fleet-needed')" "--untracked counts files and fleet-needed ones"
ok "$(has "$out" '  fleet-needed  bin/tool  (tests/a.test.sh)')" "a tool named by a test is fleet-needed"
ok "$(has "$out" '  fleet-needed  skills/s/templates/t/main.c')" "a file under a dir named by a test is fleet-needed"
ok "$(has "$out" '  fleet-needed  hooks/h-impl.py  (hooks/h.py)')" "a tracked file naming a sibling by basename makes it fleet-needed"
ok "$(has "$out" '  fleet-needed  hooks/img.py  (conf.json)')" "a tracked config naming a path makes it fleet-needed"
ok "$(has "$out" '  fleet-needed  units/x.service  (install.sh)')" "a glob in a tracked file (units/*) makes its files fleet-needed"
ok "$(has "$out" '  fleet-needed  lib/pkg/m.py  (bin/tool)')" "a fleet-needed tool's python import makes lib/<pkg> fleet-needed"
ok "$(has "$out" '  fleet-needed  tests/tool2.test.sh  (tests bin/tool)')" "an untracked test of a fleet-needed tool is fleet-needed"
ok "$(has "$out" '  fleet-needed  hooks/img.test.py  (tests hooks/img.py)')" "a test outside tests/ (hooks/*.test.py) is fleet-needed"
ok "$(has "$out" '  -             bin/stray')" "a tool named only by an unneeded test is not flagged"
ok "$(has "$out" '  -             tests/orphan.test.sh')" "a test naming no fleet file is not flagged"
ok "$(has "$out" '  -             bin/selfy')" "a file naming only itself is not flagged"
ok "$(has "$out" "owner: git -C $u add -- bin/tool hooks/h-impl.py hooks/img.py hooks/img.test.py lib/pkg/m.py skills/s/templates/t/main.c tests/tool2.test.sh units/x.service")" "one owner git add line with the fleet-needed files only"
ok "$(! grep -F "$u" "$sbx/git.log" | grep -qwE 'add|commit|push|reset|checkout|restore|clean|rebase|stash' && echo 1 || echo 0)" "--untracked runs no git write verb"

"$PR" "$sbx/secrets" >/dev/null 2>&1; ok "$([ $? = 2 ] && echo 1 || echo 0)" "non-repo exits 2"
"$PR" >/dev/null 2>&1; ok "$([ $? = 2 ] && echo 1 || echo 0)" "no argument exits 2"

[ "$bad" = 0 ] && echo "all push-ready cases pass" || echo "$bad FAILURES"
exit $([ "$bad" = 0 ] && echo 0 || echo 1)
