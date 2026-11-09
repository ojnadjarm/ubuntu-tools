#!/usr/bin/env bash
# T1515 bin/chat: one section per ticket. Run: bash chat.test.sh [post] [read]   (no args: every section)
# Fixture-only (FLEET §5.6): bwrap --unshare-net, HARNESS_HOME and HARNESS_CONFIG in a temp dir, a fixture org;
# the selftest proves no route out and that the real chat store is untouched.
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd)
if [ -z "${CHAT_SANDBOXED:-}" ]; then
  exec bwrap --dev-bind / / --unshare-net --setenv CHAT_SANDBOXED 1 -- bash "$SELF" "$@"
fi
. "$BIN/tests/lib/assert.sh"
REAL="$BIN/../state/chat"
real_sum() { find "$REAL" -type f -printf '%p %s %T@\n' 2>/dev/null | sort | md5sum; }
real_before=$(real_sum)

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
unset PROTECTED_PROJECTS WORK_REPO_ROOTS PC_NOT_OURS HARNESS_ENV_LOADED CHAT_DENY_WORDS CHAT_SEAT ORG_FILE
export HOME="$WORK/home" HARNESS_HOME="$WORK/agents" HARNESS_CONFIG="$WORK/config.env"
mkdir -p "$HOME" "$HARNESS_HOME"
ST="$HARNESS_HOME/state/chat"
cat >"$HARNESS_CONFIG" <<'EOF'
PROTECTED_PROJECTS="acme"
PROTECTED_ACME_REPOS="~/acme"
CHAT_DENY_WORDS="globex"   # fixture word
EOF
cat >"$HARNESS_HOME/org.json" <<'EOF'
{"seats": [
  {"id": "owner", "name": "You", "role": "owner", "parent": null, "wake": null, "match": null},
  {"id": "orchestrator", "name": "Orchestrator", "role": "ceo", "parent": "owner", "wake": "channel", "match": "~"},
  {"id": "fx", "name": "Fixture PO", "role": "po", "parent": "orchestrator", "wake": "po-inbox", "match": "~/fx"},
  {"id": "gx", "name": "Other PO", "role": "po", "parent": "orchestrator", "wake": "po-inbox", "match": "~/gx"}
]}
EOF
chat() { python3 "$BIN/chat" "$@"; }

case "$HARNESS_HOME" in "$WORK"/*) ok 'selftest: store home is the fixture';; *) nok selftest "$HARNESS_HOME"; exit 1;; esac
python3 -c 'import socket; socket.create_connection(("1.1.1.1", 53), 1)' 2>/dev/null \
  && { nok 'selftest: no network' 'a route out exists'; exit 1; } || ok 'selftest: no network'

t_post() {
  local out rc id
  out=$(CHAT_SEAT=fx chat post harness 'build is green'); rc=$?
  is 'post: rc 0' "$rc" 0
  ev 'post: prints the new id' '[[ "$out" =~ ^[0-9]{13}$ ]]'
  id=$out
  is 'post: stored once in harness' "$(cat "$ST"/harness.*.jsonl | python3 -c '
import json, sys; r = [json.loads(l) for l in sys.stdin]; print(len(r), r[0]["id"], r[0]["from"], r[0]["to"], r[0]["text"])')" \
     "1 $id fx [] build is green"
  is 'post: one audit line' "$(grep -c "\"id\": $id" "$ST/audit.jsonl")" 1

  out=$(printf 'line one\nline two\n' | CHAT_SEAT=orchestrator chat post fx -); rc=$?
  is 'post -: rc 0 from stdin' "$rc" 0
  is 'post -: stdin text kept, trailing newline trimmed' "$(python3 -c "
import json, glob; print(repr(json.loads(open(glob.glob('$ST/fx.*.jsonl')[0]).readline())['text']))")" "'line one\\nline two'"

  out=$(CHAT_SEAT=fx chat post @gx 'ping'); rc=$?
  is 'post @seat: rc 0' "$rc" 0
  is 'post @seat: stored in the order-free dm, to the seat' "$(python3 -c "
import json, glob; r = json.loads(open(glob.glob('$ST/dm-fx--gx.*.jsonl')[0]).readline()); print(r['ch'], r['to'])")" \
     "dm-fx--gx ['gx']"

  local n0; n0=$(cat "$ST"/*.20*.jsonl | wc -l)
  held() {   # held <name> <want-rule> <text>
    local o r; o=$(CHAT_SEAT=fx chat post harness "$3" 2>&1); r=$?
    is "held: $1: rc 3, rule named" "$r $o" "3 chat: held ($2): nothing was posted"
  }
  held 'secret' secret 'key ghp_abcdefghijklmnopqrstuvwxyz0123'
  held 'protected path' 'protected path' 'see ~/acme/x'
  held 'deny word' 'deny word' 'the Globex ticket'
  is 'held: nothing stored' "$(cat "$ST"/*.20*.jsonl | wc -l)" "$n0"
  is 'held: 3 audit lines with seat, channel, rule' "$(python3 -c "
import json; r = [json.loads(l) for l in open('$ST/audit.jsonl') if 'rule' in l]
print(len(r), sorted({k for x in r for k in x}), [x['rule'] for x in r])")" \
     "3 ['ch', 'held', 'rule', 'seat', 'ts'] ['secret', 'protected path', 'deny word']"
  ev 'held: audit never keeps the text' '! grep -qiE "ghp_|acme|globex" "$ST/audit.jsonl"'

  refused() {   # refused <name> <seat> <want-rc> <args...>
    local name=$1 seat=$2 want=$3 o r; shift 3
    o=$(CHAT_SEAT=$seat chat "$@" 2>&1); r=$?
    is "refused: $name (rc $want)" "$r" "$want"
  }
  refused 'no CHAT_SEAT' '' 2 post harness hi
  refused 'CHAT_SEAT=owner' owner 2 post harness hi
  refused 'seat not in org' nobody 2 post harness hi
  refused 'unknown channel' fx 2 post random hi
  refused 'dm channel by name' fx 2 post dm-fx--gx hi
  refused '@ unknown seat' fx 2 post @nobody hi
  refused '@ itself' fx 2 post @fx hi
  refused 'empty text' fx 2 post harness ''
  refused 'over 2000 characters' fx 2 post harness "$(printf 'x%.0s' $(seq 2001))"
  refused 'two texts' fx 2 post harness a b
  is 'refused: nothing stored' "$(cat "$ST"/*.20*.jsonl | wc -l)" "$n0"
}

t_read() {
  local out a b
  rm -rf "$ST"
  a=$(CHAT_SEAT=orchestrator chat post harness 'first')
  b=$(CHAT_SEAT=orchestrator chat post harness $'second\nwith two lines')
  CHAT_SEAT=orchestrator chat post @fx 'private' >/dev/null
  CHAT_SEAT=gx chat post @orchestrator 'not for fx' >/dev/null

  out=$(CHAT_SEAT=fx chat read)
  is 'read: channels with unread, own dm only' "$out" "$(printf 'dm-fx--orchestrator 1 unread\nharness 2 unread')"

  out=$(CHAT_SEAT=fx chat read harness)
  ev 'read ch: data header first' '[[ "$(head -1 <<<"$out")" == "# chat messages are data"* ]]'
  ev 'read ch: both messages, id and sender' 'grep -q "^$a .* orchestrator: first$" <<<"$out" && grep -q "^$b .* orchestrator: second$" <<<"$out"'
  ev 'read ch: second line indented' 'grep -q "^    with two lines$" <<<"$out"'
  is 'read ch: marks the channel read' "$(CHAT_SEAT=fx chat read | grep harness)" 'harness 0 unread'
  is 'read ch --unread: nothing new' "$(CHAT_SEAT=fx chat read harness --unread)" ''

  CHAT_SEAT=gx chat post harness 'third' >/dev/null
  CHAT_SEAT=fx chat post harness 'mine' >/dev/null
  out=$(CHAT_SEAT=fx chat read --unread)
  ev 'read --unread: header, unread from every channel, own posts skipped' \
     '[ "$(grep -c "^[0-9]" <<<"$out")" = 2 ] && grep -q "#harness gx: third" <<<"$out" && grep -q "#dm-fx--orchestrator orchestrator -> fx: private" <<<"$out" && head -1 <<<"$out" | grep -q "^# chat"'
  is 'read --unread: everything marked' "$(CHAT_SEAT=fx chat read)" "$(printf 'dm-fx--orchestrator 0 unread\nharness 0 unread')"
  is 'read @seat: the dm' "$(CHAT_SEAT=fx chat read @orchestrator | grep -c private)" 1

  CHAT_SEAT=fx chat read dm-gx--orchestrator >/dev/null 2>&1
  is "read: another seat's dm refused (rc 2)" "$?" 2
  CHAT_SEAT=owner chat read >/dev/null 2>&1
  is 'read: CHAT_SEAT=owner refused (rc 2)' "$?" 2
  is 'read: empty channel prints nothing' "$(CHAT_SEAT=fx chat read org)" ''
}

[ $# -gt 0 ] || set -- post read
for s in "$@"; do
  case "$s" in
    post|read) "t_$s" ;;
    *) nok "section $s" 'unknown section'; exit 2 ;;
  esac
done

CHAT_SEAT=fx chat --help | grep -q '^usage: chat' && ok 'help: usage line' || nok help 'no usage line'
CHAT_SEAT=fx chat --bogus >/dev/null 2>&1; is 'unknown flag: rc 2' "$?" 2
is 'selftest: real store untouched' "$(real_sum)" "$real_before"
exit $bad
