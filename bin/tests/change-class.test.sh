#!/usr/bin/env bash
# change-class on throwaway git repos with real diffs: a Moodle plugin (built-in rules) and a Mooblox-shaped repo (its real .change-classes).
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
. "$HOME/agents/bin/tests/lib/assert.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
cls() { "$BIN/change-class" "$@" | sed -n 's/^class: //p'; }
reset() { git -C "$1" checkout -q -- . && git -C "$1" clean -qfd; }

P="$T/plugin"; mkdir -p "$P"/{lang/en,classes/privacy,db,templates,pix,tests}
echo "<?php \$plugin->component = 'local_x'; \$plugin->version = 1;" >"$P/version.php"
echo "<?php \$string['b'] = 'Save';" >"$P/lang/en/local_x.php"
echo "<?php class a { function f() { return 1; } }" >"$P/classes/a.php"
echo "<?php class provider {}" >"$P/classes/privacy/provider.php"
echo '<XMLDB/>' >"$P/db/install.xml"; echo '<div>{{b}}</div>' >"$P/templates/t.mustache"; echo '.a{}' >"$P/styles.css"
echo '<svg/>' >"$P/pix/i.svg"; echo '<?php' >"$P/lib.php"
git -C "$P" init -q && git -C "$P" add -A && git -C "$P" commit -qm base

is 'clean tree: none' "$(cls --repo "$P")" none
echo "<?php \$string['b'] = 'Save changes';" >"$P/lang/en/local_x.php"
is 'moodle lang string: docs' "$(cls --repo "$P")" docs
is 'moodle lang: checks skip PHPUnit' "$("$BIN/change-class" --repo "$P" | grep -c '^checks: .*lang' )" 1
is 'moodle rules: built-in default' "$("$BIN/change-class" --repo "$P" | grep -c 'rules: moodle default')" 1
reset "$P"; echo '.a{color:red}' >"$P/styles.css"
is 'moodle CSS: ui' "$(cls --repo "$P")" ui
echo '<div class="x">{{b}}</div>' >"$P/templates/t.mustache"
is 'moodle CSS + template: ui' "$(cls --repo "$P")" ui
reset "$P"; echo '<svg width="2"/>' >"$P/pix/i.svg"
is 'moodle icon: content' "$(cls --repo "$P")" content
reset "$P"; echo "<?php class a { function f() { return 2; } }" >"$P/classes/a.php"
is 'moodle class logic: logic' "$(cls --repo "$P")" logic
echo "<?php class a { function f() { require_capability('x', \$c); } }" >"$P/classes/a.php"
is 'moodle require_capability in the diff: security' "$(cls --repo "$P")" security
reset "$P"; echo '<XMLDB a="1"/>' >"$P/db/install.xml"
is 'moodle install.xml: schema' "$(cls --repo "$P")" schema
reset "$P"; echo "<?php class provider { const A = 1; }" >"$P/classes/privacy/provider.php"
is 'moodle privacy provider: security' "$(cls --repo "$P")" security
reset "$P"; echo "<?php \$string['b'] = 'Go';" >"$P/lang/en/local_x.php"; echo '<?php // x' >"$P/lib.php"; echo '.b{}' >>"$P/styles.css"
out=$("$BIN/change-class" --repo "$P")
is 'moodle mixed lang + CSS + lib.php: the highest, logic' "$(sed -n 's/^class: //p' <<<"$out")" logic
is 'moodle mixed: decided by lib.php' "$(sed -n 's/^decided by: //p' <<<"$out")" lib.php
is 'moodle mixed: per-class counts' "$(grep -c '^files: 3 (docs 1, ui 1, logic 1)' <<<"$out")" 1
reset "$P"; sed -i 's/version = 1;/version = 2;/' "$P/version.php"
is 'moodle version.php bump alone: docs, no PHPUnit' "$(cls --repo "$P")" docs
echo '<?php // x' >"$P/lib.php"
is 'moodle bump + lib.php: the rest of the diff, logic' "$(cls --repo "$P")" logic
reset "$P"; sed -i 's/version = 1;/version = 2;/' "$P/version.php"; echo '<?php // step' >"$P/db/upgrade.php"
is 'moodle bump + db/upgrade.php: schema' "$(cls --repo "$P")" schema
reset "$P"; sed -i 's/version = 1;/version = 2;/' "$P/version.php"; echo '<?php $tasks = [];' >"$P/db/tasks.php"
is 'moodle bump + db/tasks.php: schema' "$(cls --repo "$P")" schema
reset "$P"; echo x >"$P/notes.bin"
is 'moodle untracked unknown file: full' "$(cls --repo "$P")" full
reset "$P"; echo "<?php \$string['b'] = 'Ok';" >"$P/lang/en/local_x.php"
is '--at-least engine raises docs' "$(cls --repo "$P" --at-least engine)" engine
is '--at-least docs never lowers logic' "$(echo '<?php //' >"$P/lib.php"; cls --repo "$P" --at-least docs)" logic
reset "$P"; git -C "$P" commit -qam lang --allow-empty; echo "<?php \$string['b'] = 'Z';" >"$P/lang/en/local_x.php"; git -C "$P" commit -qam z
is '--base HEAD~1: the committed lang change' "$(cls --repo "$P" --base HEAD~1)" docs

M="$T/mooblox"; mkdir -p "$M"/client/src/{world/props,world,hub,boot} "$M"/client/test "$M"/client/public/assets "$M"/moodle/local/mooblox/lang/en
cp "$HOME/projects/personal/mooblox/.change-classes" "$M/.change-classes"
echo 'export const a = 1;' >"$M/client/src/world/props/bench.ts"; echo 'export const s = 1;' >"$M/client/src/world/island-streamer.ts"
echo 'export const h = 1;' >"$M/client/src/hub/portal-arch.ts"; echo 'export const g = 1;' >"$M/client/src/world/dressing.ts"
echo 'png' >"$M/client/public/assets/tree.png"; echo '{"scripts":{}}' >"$M/client/package.json"; echo '# M' >"$M/README.md"
echo "<?php \$plugin->component = 'local_mooblox';" >"$M/moodle/local/mooblox/version.php"
echo "<?php \$string['go'] = 'Go';" >"$M/moodle/local/mooblox/lang/en/local_mooblox.php"
git -C "$M" init -q && git -C "$M" add -A && git -C "$M" commit -qm base
echo 'export const a = 2;' >"$M/client/src/world/props/bench.ts"
is 'mooblox prop tweak: content' "$(cls --repo "$M")" content
is 'mooblox rules: the repo file' "$("$BIN/change-class" --repo "$M" | grep -c "rules: $M/.change-classes")" 1
echo 'png2' >"$M/client/public/assets/tree.png"
is 'mooblox prop + art: content' "$(cls --repo "$M")" content
reset "$M"; echo 'export const h = 2;' >"$M/client/src/hub/portal-arch.ts"
is 'mooblox hub UI: ui' "$(cls --repo "$M")" ui
reset "$M"; echo 'export const g = 2;' >"$M/client/src/world/dressing.ts"
is 'mooblox world logic: logic' "$(cls --repo "$M")" logic
reset "$M"; echo 'export const s = 2;' >"$M/client/src/world/island-streamer.ts"
is 'mooblox streamer: engine' "$(cls --repo "$M")" engine
echo 'export const a = 3;' >"$M/client/src/world/props/bench.ts"; echo '# M2' >"$M/README.md"
is 'mooblox mixed prop + docs + streamer: engine' "$(cls --repo "$M")" engine
reset "$M"; echo '{"scripts":{"t":"x"}}' >"$M/client/package.json"
is 'mooblox package.json scripts only: docs' "$(cls --repo "$M")" docs
echo '{"scripts":{},"dependencies":{"three":"0.186.1"}}' >"$M/client/package.json"
is 'mooblox package.json new dependency: engine' "$(cls --repo "$M")" engine
git -C "$M" commit -qam deps; echo '{"scripts":{},"dependencies":{"three":"0.187.0"}}' >"$M/client/package.json"
is 'mooblox package.json version range: engine' "$(cls --repo "$M")" engine
reset "$M"; echo 'not json' >"$M/client/package.json"
is 'mooblox package.json unparsable: engine' "$(cls --repo "$M")" engine
reset "$M"; echo "<?php \$plugin->component = 'local_mooblox'; \$plugin->version = 2;" >"$M/moodle/local/mooblox/version.php"
is 'mooblox deploy bump alone: docs' "$(cls --repo "$M")" docs
echo 'export const a = 9;' >"$M/client/src/world/props/bench.ts"
is 'mooblox bump + prop: content' "$(cls --repo "$M")" content
reset "$M"; echo "<?php \$string['go'] = 'Play';" >"$M/moodle/local/mooblox/lang/en/local_mooblox.php"
is 'mooblox Moodle lang string from the repo root: docs' "$(cls --repo "$M")" docs
is 'mooblox plugin dir uses the Moodle default: docs' "$("$BIN/change-class" --repo "$M/moodle/local/mooblox" | grep -c '^class: docs$\|rules: moodle default' )" 2

is 'not a git repo: full' "$(mkdir -p "$T/plain"; cls --repo "$T/plain")" full
"$BIN/change-class" --at-least huge >/dev/null 2>&1; is 'bad --at-least: rc 2' $? 2
exit $bad
