#!/usr/bin/env bash
# T1633 secret-mask and the po-work image-key mask: a listed file reads empty (cat, python open, a copy) in the whole
# process tree, other files read as is; po-work runs a worker without `AI image grant:` under it, a granted one not.
# Fixture-only (FLEET §5.6): fake key and secrets in a temp HARNESS_HOME, fake systemd-run/agent-exec/agent-run, no
# network call. Not inside a bwrap sandbox: bwrap cannot nest here (AppArmor), and secret-mask is bwrap.
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd)
. "$BIN/tests/lib/assert.sh"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
export HARNESS_ENV_LOADED=1 HARNESS_HOME="$WORK/agents" AGENT_WORK="$WORK/agent-work" HARNESS_CONFIG=/dev/null PO_PAPERS="$WORK/agent-work/po" WORK
K="$HARNESS_HOME/secrets/openrouter.key"; T="$HARNESS_HOME/secrets/discord-bot-token"
mkdir -p "$HARNESS_HOME/secrets" "$HARNESS_HOME/po-mg/inbox" "$AGENT_WORK/briefs" "$WORK/stubs"
printf 'FXKEY-T1633' >"$K"; printf 'fxtoken' >"$T"; : >"$HARNESS_HOME/AGENT-PREAMBLE.md"; echo 'You are po-mg.' >"$HARNESS_HOME/po-mg/BRIEF.md"

# reads <file>: bytes by cat, by python open, by a copy
reads() { cp "$1" "$WORK/copy.$$"; echo "$(wc -c <"$1") $(python3 -c 'import sys; print(len(open(sys.argv[1]).read()))' "$1") $(wc -c <"$WORK/copy.$$")"; }
export -f reads

# Fake systemd-run: run the unit's command detached; fake agent-exec: report the key's reads and another secret.
printf '#!/usr/bin/env bash\nwhile [ $# -gt 0 ]; do case "$1" in --*) shift ;; *) break ;; esac; done\nsetsid "$@" </dev/null >>"$WORK/unit.out" 2>&1 &\n' >"$WORK/stubs/systemd-run"
printf '#!/usr/bin/env bash\necho "$(reads "$HARNESS_HOME/secrets/openrouter.key") $(cat "$HARNESS_HOME/secrets/discord-bot-token")"\n' >"$WORK/stubs/agent-exec"
printf '#!/bin/sh\nexit 0\n' >"$WORK/stubs/agent-run"; cp "$WORK/stubs/agent-run" "$WORK/stubs/plan-usage"
chmod +x "$WORK"/stubs/*
export PATH="$WORK/stubs:$BIN:$PATH"

# selftest
for c in systemd-run agent-exec agent-run; do is "selftest: $c is the fake" "$(command -v $c)" "$WORK/stubs/$c"; done
case "$K" in "$WORK"/*) ok 'selftest: the key is the fixture';; *) nok 'selftest: key' "$K";; esac
[ "$(readlink -f "$K")" != "$(readlink -f "$HOME/agents/secrets/openrouter.key")" ] && ok 'selftest: not the real key path' || nok 'selftest' 'real key path'

# secret-mask
is 'mask: cat, python open and a copy read 0 bytes' "$(secret-mask "$K" -- bash -c 'reads "$1"' _ "$K")" '0 0 0'
is 'mask: another file in the same folder reads as is' "$(secret-mask "$K" -- cat "$T")" 'fxtoken'
is 'mask: a child of a child reads 0 too' "$(secret-mask "$K" -- bash -c 'bash -c "wc -c <\"\$0\"" "$1"' _ "$K")" '0'
is 'mask: through a relative path and a symlink' "$(ln -s "$K" "$WORK/link"; cd "$HARNESS_HOME" && secret-mask secrets/openrouter.key -- bash -c 'wc -c <"$1"' _ "$WORK/link")" '0'
secret-mask "$K" -- sh -c 'exit 7'; is 'mask: exit code passes through' "$?" 7
is 'mask: env and cwd kept' "$(cd "$WORK" && FX=1 secret-mask "$K" -- sh -c 'echo "$FX $PWD"')" "1 $WORK"
secret-mask "$WORK/missing" -- true; is 'mask: a missing path runs the command' "$?" 0
[ ! -e "$WORK/missing" ] && ok 'mask: a missing path is not created' || nok 'mask: missing path' 'created'
secret-mask "$K" >/dev/null 2>&1; is 'mask: no command exits 2' "$?" 2
is 'mask: the key file itself is unchanged' "$(cat "$K")" 'FXKEY-T1633'

# po-work: no grant -> masked; a grant -> the key reads
echo 'draw him' >"$AGENT_WORK/briefs/T501-mg-masked.md"
printf 'AI image grant: "hazme una imagen con IA"\n' >"$AGENT_WORK/briefs/T502-mg-granted.md"
for t in T501 T502; do
  po-work mg start $t --brief "$(ls "$AGENT_WORK"/briefs/$t-*.md)" >/dev/null 2>&1
  timeout 15 wait-for --every 0.1 --until "[ \"\$(jq -r .status '$HARNESS_HOME/po-mg/state/work/$t.json')\" = done ]" >/dev/null 2>&1
done
is 'po-work: no grant: the key reads 0 three ways; another secret reads' "$(cat "$HARNESS_HOME/po-mg/logs/work/T501.out")" '0 0 0 fxtoken'
is 'po-work: a grant: the worker reads the key' "$(cat "$HARNESS_HOME/po-mg/logs/work/T502.out")" '11 11 11 fxtoken'
exit $bad
