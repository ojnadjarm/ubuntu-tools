#!/usr/bin/env bash
# T952/T1003: `install.sh --plan` writes nothing and names every change, the adapter's too; its count equals a real install's, and a second plan is 0.
# Fixture harness + HOME in mktemp; PATH stubs for apt-get, sudo, ln, cp, systemctl fail if a plan calls them.
set -uo pipefail
. "$HOME/agents/bin/tests/lib/assert.sh"
REAL="$HOME/agents"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
H="$W/h"; FH="$W/home"; S="$W/stubs"; A="$W/apply-stubs"; CALLED="$W/called"
mkdir -p "$H/bin" "$H/units" "$H/KB" "$H/agentx" "$H/skills/gamedev/templates/cpp-vulkan" "$FH" "$S" "$A"
cp "$REAL/install.sh" "$H/"; cp "$REAL/bin/env.sh" "$H/bin/"
printf '#!/bin/sh\n' >"$H/bin/toolx"; printf '#!/bin/sh\n' >"$H/bin/pc-foo"; chmod +x "$H/bin/toolx" "$H/bin/pc-foo"
cat >"$H/bin/pc" <<'EOF'
#!/bin/sh
[ "$1 $2" = "status --facts" ] && echo "facts new" >"$PC_FACTS_FILE"
exit 0
EOF
chmod +x "$H/bin/pc"
echo "facts old" >"$H/KB/machine.md"
# Tab-separated rows; the apt column of zzfake1 and the gamedev-cpp list carry a double space.
printf '%s\n' '# test-also: zzfake2' '# gamedev-cpp: aa  bb cc' \
  "$(printf 'bash\tbash\tx\trequired')" "$(printf 'zzfake1\tzzpkg1  zzpkg1b\tx\ttest')" \
  "$(printf 'zzfake2\tzzpkg2\tx\tadvisory')" >"$H/bin/DEPS.tsv"
printf '[Timer]\nOnCalendar=daily\n' >"$H/units/demo.timer"
printf '[Service]\nExecStart=/bin/true\n[Install]\nWantedBy=default.target\n' >"$H/units/demo.service"
printf '[Service]\nExecStart=/bin/true\n' >"$H/units/agent@.service"
echo brief >"$H/agentx/BRIEF.md"; printf 'SCHEDULE=daily\nENABLED=yes\nUNIT_TIMEOUT=60\n' >"$H/agentx/agent.env"
echo '{"builtin-baseline":"abc123"}' >"$H/skills/gamedev/templates/cpp-vulkan/vcpkg.json"

for c in apt-get sudo ln cp; do printf '#!/bin/sh\necho "%s $*" >>"%s"; exit 97\n' "$c" "$CALLED" >"$S/$c"; done
# systemctl: read verbs answer from the enabled list; anything else is a write (recorded, rc 97 in plan stubs).
cat >"$S/systemctl" <<EOF
#!/bin/sh
case "\$2" in
  show-environment) exit 0;;
  is-enabled) grep -qx "\$3" "$W/enabled" 2>/dev/null && { echo enabled; exit 0; }; echo disabled; exit 1;;
esac
echo "systemctl \$*" >>"$CALLED"; exit 97
EOF
printf '#!/bin/sh\necho "ii  aa"\n' >"$S/dpkg-query"
cp "$S/systemctl" "$S/dpkg-query" "$A/"
cat >"$A/systemctl" <<EOF
#!/bin/sh
case "\$2" in
  show-environment|daemon-reload) exit 0;;
  is-enabled) grep -qx "\$3" "$W/enabled" 2>/dev/null && { echo enabled; exit 0; }; echo disabled; exit 1;;
  enable) echo "\$4" >>"$W/enabled"; exit 0;;
esac
exit 97
EOF
chmod +x "$S"/* "$A"/*

run() { local stubs="$1"; shift; env -i HOME="$FH" USER=fx PATH="$stubs:/usr/bin:/bin" HARNESS_HOME="$H" HARNESS_AGENT="${AGENT:-none}" bash "$H/install.sh" "$@" </dev/null 2>&1; }
snap() { (cd "$W" && find h home -printf '%p %s %l\n' | sort; find h home -type f -exec md5sum {} + | sort); }

before="$(snap)"; out="$(run "$S" --plan)"; rc=$?
is "plan rc" "$rc" 0
is "plan last line" "$(tail -1 <<<"$out")" "plan: 13 changes"
is "plan would lines" "$(grep -c '^would: ' <<<"$out")" 13
for l in "would: config $FH/.config/pc-harness/config.env" "would: link toolx" "would: link pc" "would: unit demo.timer" \
         "would: unit agent@agentx.timer.d/schedule.conf = daily" "would: unit agent@agentx.service.d/timeout.conf = 60 s" \
         "would: unit daemon-reload" "would: unit enable agent@agentx.timer" "would: config $H/KB/machine.md"; do
  grep -qxF "$l" <<<"$out" && ok "$l" || nok "$l" "missing"
done
grep -q 'would: link pc-foo' <<<"$out" && nok "pc-* not linked" "planned" || ok "pc-* not linked"
is "plan wrote nothing" "$(snap)" "$before"
is "plan called no writer" "$(cat "$CALLED" 2>/dev/null)" ""

out="$(run "$S" --plan --test-deps)"
is "test-deps words (double space)" "$(grep '^would: apt' <<<"$out")" "would: apt install zzpkg1 zzpkg1b zzpkg2"
is "test-deps count" "$(tail -1 <<<"$out")" "plan: 1 changes"
out="$(run "$S" --plan --gamedev)"
is "gamedev words (double space)" "$(grep '^would: apt' <<<"$out")" "would: apt install bb cc"
is "gamedev count" "$(tail -1 <<<"$out")" "plan: 4 changes"
out="$(run "$S" --plan --links)"
is "links count" "$(tail -1 <<<"$out")" "plan: 2 changes"
is "flag plans wrote nothing" "$(snap)" "$before"
is "flag plans called no writer" "$(cat "$CALLED" 2>/dev/null)" ""

applied="$(run "$A" | grep -oE '^install.sh: [0-9]+ change')"
is "apply count = plan count" "$applied" "install.sh: 13 change"
out="$(run "$S" --plan)"
is "second plan" "$(tail -1 <<<"$out")" "plan: 0 changes"
is "second plan called no writer" "$(cat "$CALLED" 2>/dev/null)" ""

# T1003: the claude adapter step is planned (fixture skill link + settings merge), applied with the same count, then 0.
mkdir -p "$H/adapters/claude" "$H/skills/sk1"; echo sk >"$H/skills/sk1/SKILL.md"
cp "$REAL/adapters/claude/"{install,merge-settings.py,settings.fragment.json} "$H/adapters/claude/"
before="$(snap)"; out="$(AGENT=claude run "$S" --plan)"
is "adapter planned" "$(grep -c 'not planned' <<<"$out")" 0
is "adapter plan lines" "$(grep -cE "^would: (link $FH/.claude/skills/sk1|settings merge into $FH/.claude/settings.json \([0-9]+ diff lines\))\$" <<<"$out")" 2
is "adapter plan count" "$(tail -1 <<<"$out")" "plan: 2 changes"
is "adapter plan wrote nothing" "$(snap)" "$before"
is "adapter plan called no writer" "$(cat "$CALLED" 2>/dev/null)" ""
is "adapter apply count = plan count" "$(AGENT=claude run "$A" | grep -oE '^install.sh: [0-9]+ change')" "install.sh: 2 change"
is "adapter second plan" "$(tail -1 <<<"$(AGENT=claude run "$S" --plan)")" "plan: 0 changes"

# Unreachable user bus: the plan names its blocker, rc 3.
B="$W/nobus"; mkdir -p "$B"; cp "$S"/* "$B/"; printf '#!/bin/sh\nexit 1\n' >"$B/systemctl"; chmod +x "$B/systemctl"
out="$(run "$B" --plan)"; rc=$?
is "no bus rc" "$rc" 3
is "no bus last line" "$(tail -1 <<<"$out")" "plan: blocked: systemd --user unreachable"

# Adapter --plan alone on a fake HOME with no links: one would line per skill + settings + stale symlink + include; nothing written.
AH="$W/ahome"; mkdir -p "$AH/.claude/hooks"; echo '# home' >"$AH/CLAUDE.md"; ln -s /nonexistent "$AH/.claude/hooks/audit-log.sh"
nsk=$(compgen -G "$REAL/skills/*/SKILL.md" | wc -l)
asnap() { (find "$AH" "$REAL/adapters/claude" -printf '%p %s %l %T@\n' | sort; find "$AH" "$REAL/adapters/claude" -type f -exec sha1sum {} + | sort); }
before="$(asnap)"; out="$(env -i HOME="$AH" PATH="$S:/usr/bin:/bin" HARNESS_HOME="$REAL" bash "$REAL/adapters/claude/install" --plan 2>&1)"; rc=$?
is "fake home plan rc" "$rc" 0
is "fake home would lines" "$(grep -c '^would: ' <<<"$out")" "$((nsk + 3))"
is "fake home skill links" "$(grep -c "^would: link $AH/.claude/skills/" <<<"$out")" "$nsk"
is "fake home wrote nothing" "$(asnap)" "$before"

# This box: the adapter is already installed, so its plan is 0 and settings.json is untouched.
st="$(stat -c '%Y %s' "$HOME/.claude/settings.json"; sha1sum <"$HOME/.claude/settings.json")"
out="$(bash "$REAL/adapters/claude/install" --plan 2>&1)"
is "this box adapter plan" "$(grep -c '^would: ' <<<"$out")" 0
is "this box settings untouched" "$(stat -c '%Y %s' "$HOME/.claude/settings.json"; sha1sum <"$HOME/.claude/settings.json")" "$st"
exit $bad
