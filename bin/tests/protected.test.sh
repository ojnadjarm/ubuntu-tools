#!/usr/bin/env bash
# protected (T1513): the one matcher on a fixture config (projects acme + beta, legacy fallback); no real config is read.
set -uo pipefail
BIN="$HOME/agents/bin"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$BIN/tests/lib/assert.sh"
unset PROTECTED_PROJECTS WORK_REPO_ROOTS PC_NOT_OURS HARNESS_ENV_LOADED
export HARNESS_CONFIG="$WORK/config.env"
cat >"$HARNESS_CONFIG" <<'EOF'
PROTECTED_PROJECTS="acme beta-2"
PROTECTED_ACME_REPOS="~/acme $HOME/acme2"
PROTECTED_ACME_PATHS="/srv/acme-data"
PROTECTED_ACME_CONTAINERS="acme* 9.9"
PROTECTED_ACME_UNITS="acme-*.service acme.timer"
PROTECTED_ACME_WORDS="acme Moodle99"
PROTECTED_BETA_2_UNITS="beta?.service"
EOF
p() { "$BIN/protected" "$@"; }
case "$HARNESS_CONFIG" in "$WORK"/*) ok 'selftest: config is the fixture';; *) nok selftest "$HARNESS_CONFIG"; exit 1;; esac

is 'projects in config order' "$(p projects | paste -sd' ')" 'acme beta-2'
is 'repo: a dir under a root' "$(p match repo "$HOME/acme/sub/dir")" acme
is 'repo: the root itself, $HOME form' "$(p match repo "$HOME/acme2")" acme
p match repo "$HOME/acme-other" >/dev/null; is 'repo: a sibling prefix is not a match (exit 1)' $? 1
is 'path: repos count as paths' "$(p match path "$HOME/acme/x")" acme
is 'path: PATHS entries' "$(p match path /srv/acme-data/db)" acme
p match repo /srv/acme-data >/dev/null; is 'repo: PATHS are not repos' $? 1
is 'container: glob' "$(p match container acme-db-1)" acme
is 'container: env dir exact' "$(p match container 9.9)" acme
p match container 9.99 >/dev/null; is 'container: no partial env dir' $? 1
is 'unit: second project, ? glob, name with a dash' "$(p match unit beta7.service)" beta-2
p match unit acme.service >/dev/null; is 'unit: acme.service matches neither glob' $? 1
is 'text: any case' "$(p match text /tmp/claude/-home-x-MOODLE99/sess)" acme
is 'text: default word is the name' "$(p match text 'x beta-2 y')" beta-2
is 'ere unit' "$(p ere unit)" '(^acme-.*\.service$|^acme\.timer$|^beta.\.service$)'
is 'eres text' "$(p eres text)" "$(printf 'acme\t(acme|moodle99)\nbeta-2\t(beta-2)')"
is 'eres: only projects with entries' "$(p eres container | cut -f1)" acme
[[ acme-web.service =~ $(p ere unit) ]] && ok 'ere unit works with bash =~' || nok 'bash =~' x
python3 -c "import re,sys; sys.exit(0 if re.search(sys.argv[1], 'acme.timer') else 1)" "$(p ere unit)" && ok 'ere unit works with python re' || nok 'python re' x
PYTHONPATH="$BIN" python3 -c 'import protectedlib as p; print(p.project(p.eres("container"), "acme-x"))' >"$WORK/py"
is 'protectedlib.project' "$(cat "$WORK/py")" acme
is 'pclib: PC_NOT_OURS is the unit ERE' "$(bash -c ". '$BIN/pclib.sh'; echo \"\$PC_NOT_OURS\"")" "$(p ere unit)"
is 'stale env (HARNESS_ENV_LOADED, no keys) still reads config.env' \
  "$(HARNESS_ENV_LOADED=1 bash -c ". '$BIN/pclib.sh'; protected_match container acme-1")" acme
is 'nothing protected: ERE never matches' "$(PROTECTED_PROJECTS= p ere unit)" '^$'
is 'list rows' "$(p list | wc -l)" 7

# Fallback: PROTECTED_PROJECTS empty, legacy WORK_REPO_ROOTS is project "work" (repos, paths; no words).
is 'legacy: project work' "$(PROTECTED_PROJECTS= WORK_REPO_ROOTS='~/w' p match repo "$HOME/w/r")" work
is 'legacy: no text words' "$(PROTECTED_PROJECTS= WORK_REPO_ROOTS='~/w' p ere text)" '^$'
PROTECTED_PROJECTS=acme WORK_REPO_ROOTS='~/w' p match repo "$HOME/w/r" >/dev/null; is 'legacy ignored once PROTECTED_PROJECTS is set' $? 1
p match nokind x >/dev/null 2>&1; is 'unknown kind exits 2' $? 2
p nosuch >/dev/null 2>&1; is 'unknown verb exits 2' $? 2
p -h >/dev/null; is '-h exits 0' $? 0

[ "$bad" = 0 ] && echo 'PASS protected' || echo 'FAIL protected'
exit "$bad"
