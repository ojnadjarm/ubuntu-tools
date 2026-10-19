#!/usr/bin/env bash
# moodle-envs and moodle-login-check find the code dir through the compose /var/www/html mount and skip stacks without one.
# Runs against a temp HOME with stubbed docker/tailscale/curl on PATH, never the real ~/moodle-envs (AGENTS.md §5.6).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVS_BIN="$HERE/../moodle-envs"
LOGIN_BIN="$HERE/../moodle-login-check"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ROOT="$TMP/moodle-envs"
STUBS="$TMP/stubs"
mkdir -p "$ROOT/v1/www/public" "$ROOT/v2" "$ROOT/svc" "$TMP/elsewhere/moodle" "$STUBS"

cat > "$ROOT/v1/docker-compose.yml" <<'EOF'
name: v1
services:
  app:
    ports:
      - "8001:80"
    volumes:
      - ./www:/var/www/html
EOF
cat > "$ROOT/v2/docker-compose.yml" <<EOF
name: v2
services:
  app:
    ports:
      - "8002:80"
    volumes:
      - $TMP/elsewhere/moodle:/var/www/html
EOF
cat > "$ROOT/svc/docker-compose.yml" <<'EOF'
name: svc
services:
  redis:
    image: redis:7-alpine
EOF

printf "<?php\n\$CFG->wwwroot = 'http://v1.invalid';\n" > "$ROOT/v1/www/config.php"
printf "<?php\n\$release = '5.2dev (Build: 1)';\n" > "$ROOT/v1/www/public/version.php"
printf "<?php\n\$CFG->wwwroot = 'http://v2.invalid';\n" > "$TMP/elsewhere/moodle/config.php"
printf "<?php\n\$release = '4.5.12+ (Build: 2)';\n" > "$TMP/elsewhere/moodle/version.php"

printf '#!/usr/bin/env bash\nexit 0\n' > "$STUBS/docker"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUBS/tailscale"
cat > "$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in *http_code*) printf 200 ;; *) echo '<input name="username">' ;; esac
EOF
chmod +x "$STUBS"/*

pass=0; fail=0
check() { if eval "$2"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }

out="$(HOME="$TMP" PATH="$STUBS:$PATH" bash "$ENVS_BIN" 2>&1)"
check "v1 (./www mount) shows url and release" 'grep -Eq "^v1 +5\.2dev .*http://v1\.invalid" <<<"$out"'
check "v2 (absolute mount) shows url and release" 'grep -Eq "^v2 +4\.5\.12\+ .*http://v2\.invalid" <<<"$out"'
check "svc (no /var/www/html mount) is not listed" '! grep -q "^svc" <<<"$out"'

out="$(HOME="$TMP" PATH="$STUBS:$PATH" bash "$LOGIN_BIN" v2 2>&1)"
check "login-check v2 reads the mounted config" 'grep -q "url:   http://v2.invalid" <<<"$out" && grep -q "login: OK" <<<"$out"'
out="$(HOME="$TMP" PATH="$STUBS:$PATH" bash "$LOGIN_BIN" svc 2>&1)"; rc=$?
check "login-check svc fails as not a Moodle env" '[ "$rc" = 1 ] && grep -q "no env svc" <<<"$out"'

ALT="$TMP/alt-envs"
mkdir -p "$ALT"; cp -r "$ROOT/v1" "$ALT/v3"; sed -i 's/^name: v1/name: v3/' "$ALT/v3/docker-compose.yml"
printf "<?php\nif (\$x) {\n    \$CFG->wwwroot = 'https://' . \$_SERVER['HTTP_HOST'];\n}\n\$CFG->wwwroot = 'http://v3.invalid';\n" > "$ALT/v3/www/config.php"
out="$(HOME="$TMP" MOODLE_ENVS_DIR="$ALT" PATH="$STUBS:$PATH" bash "$ENVS_BIN" 2>&1)"
check "moodle-envs honours MOODLE_ENVS_DIR" 'grep -Eq "^v3 .*http://v3\.invalid" <<<"$out" && ! grep -q "^v1" <<<"$out"'
out="$(HOME="$TMP" MOODLE_ENVS_DIR="$ALT" PATH="$STUBS:$PATH" bash "$LOGIN_BIN" v3 2>&1)"
check "login-check honours MOODLE_ENVS_DIR and skips a dynamic wwwroot" 'grep -q "url:   http://v3.invalid$" <<<"$out" && grep -q "login: OK" <<<"$out"'

echo "moodle-envs: $pass passed, $fail failed"
[ "$fail" = 0 ]
