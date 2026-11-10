#!/usr/bin/env bash
# T1515 bin/chat: the post section (run alone or via chat.test.sh post); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_post() {
  local out rc id
  out=$(CHAT_SEAT=fx chat post harness 'build is green'); rc=$?
  is 'post: rc 0' "$rc" 0
  ev 'post: prints the new id' '[[ "$out" =~ ^[0-9]{13}$ ]]'
  id=$out
  is 'post: stored once in harness' "$(cat "$ST"/harness.*.jsonl | python3 -c '
import json, sys; r = [json.loads(l) for l in sys.stdin]; print(len(r), r[0]["id"], r[0]["from"], r[0]["to"], r[0]["text"])')" \
     "1 $id fx [] build is green"
  is 'post: one audit line besides the wakes' "$(grep "\"id\": $id" "$ST/audit.jsonl" | grep -vc '"wake"')" 1

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

t_post
chat_done
