#!/usr/bin/env bash
# TSP-010: moodle-keep must read its envs root from MOODLE_ENVS_DIR, not a hardcoded $HOME path.
# It also finds config.php through the compose mount at /var/www/html and skips stacks without one.
# Runs against a temp MOODLE_ENVS_DIR with one fake env dir and stubbed docker/curl on PATH —
# never the real ~/moodle-envs or real docker (AGENTS.md §5.6).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEEP="$HERE/../moodle-keep"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ENVS="$TMP/envs"
STUBS="$TMP/stubs"
mkdir -p "$ENVS/v1/www" "$ENVS/v2" "$ENVS/svc" "$TMP/elsewhere/moodle" "$STUBS"

cat > "$ENVS/v1/docker-compose.yml" <<'EOF'
name: v1
services:
  app:
    volumes:
      - ./www:/var/www/html
EOF

cat > "$ENVS/v2/docker-compose.yml" <<EOF
name: v2
services:
  app:
    volumes:
      - $TMP/elsewhere/moodle:/var/www/html
EOF

cat > "$ENVS/svc/docker-compose.yml" <<'EOF'
name: svc
services:
  redis:
    image: redis:7-alpine
EOF

for cfg in "$ENVS/v1/www/config.php" "$TMP/elsewhere/moodle/config.php"; do
  cat > "$cfg" <<'EOF'
<?php
$CFG->wwwroot = 'http://fixture.invalid';
$CFG->dbuser = 'u';
$CFG->dbname = 'd';
EOF
done

cat > "$STUBS/docker" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  ps) echo cid1 ;;
  exec)
    args="$*"
    case "$args" in
      *pg_dump*) echo "-- fixture dump" ;;
      *"count(*)"*) echo 150 ;;
      *) exit 0 ;;
    esac
    ;;
  image|builder) echo "stub prune" ;;
  compose) exit 0 ;;
  *) exit 0 ;;
esac
EOF

cat > "$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
echo 200
EOF

chmod +x "$STUBS"/docker "$STUBS"/curl

# Fake HOME too: BACKUPS/logrotate under moodle-keep are $HOME-relative, and a test must
# never write into the real ~/agents/backups tree (AGENTS.md §5.6).
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME"

out="$(HOME="$FAKE_HOME" MOODLE_ENVS_DIR="$ENVS" PATH="$STUBS:$PATH" bash "$KEEP" 2>&1)"
rc=$?

pass=1
echo "$out" | grep -q '^== v1$' || { echo "FAIL: fixture env 'v1' not found under MOODLE_ENVS_DIR"; pass=0; }
echo "$out" | grep -q "$HOME/moodle-envs" && { echo "FAIL: real ~/moodle-envs path leaked into output"; pass=0; }
[ -e "$HOME/agents/backups/moodle/v1" ] && { echo "FAIL: fixture backup leaked into real ~/agents/backups"; pass=0; }
[ "$rc" = 0 ] || { echo "FAIL: rc=$rc"; pass=0; }
for v in v1 v2; do
  [ -s "$FAKE_HOME/agents/backups/moodle/$v/$(date +%F).sql.gz" ] || { echo "FAIL: no dump for $v"; pass=0; }
done
echo "$out" | grep -A1 '^== svc$' | grep -q 'skipped: not a Moodle env' || { echo "FAIL: svc not skipped"; pass=0; }
[ -e "$FAKE_HOME/agents/backups/moodle/svc" ] && { echo "FAIL: svc was dumped"; pass=0; }

if [ "$pass" = 1 ]; then
  echo "PASS moodle-keep honours MOODLE_ENVS_DIR (rc=$rc)"
  exit 0
else
  echo "$out"
  exit 1
fi
