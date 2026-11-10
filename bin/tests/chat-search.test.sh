#!/usr/bin/env bash
# T1515 bin/chat: the search section (run alone or via chat.test.sh search); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_search() {
  # T1545-C: chat search over the seat's own channels; a pull seat gets #harness and its direct messages; no cursor moves.
  local out rc a b c d n0 org="$WORK/org-search.json"
  rm -rf "$ST"
  sed 's/^]}/,{"id": "acme", "name": "Acme seat", "role": "po", "parent": "orchestrator", "wake": "pull", "match": null}\n]}/' \
    "$HARNESS_HOME/org.json" >"$org"
  a=$(CHAT_SEAT=orchestrator chat post harness 'Deploy the dashboard today')
  b=$(CHAT_SEAT=gx chat post harness $'dashboard DEPLOY is done\nsecond line')
  c=$(CHAT_SEAT=orchestrator chat post @fx 'the dashboard deploy, privately')
  CHAT_SEAT=gx chat post @orchestrator 'dashboard deploy not for fx' >/dev/null
  d=$(CHAT_SEAT=orchestrator chat post org 'deploy the dashboard in org')
  ORG_FILE=$org CHAT_SEAT=acme chat post @orchestrator 'dashboard deploy from the pull seat' >/dev/null
  n0=$(CHAT_SEAT=fx chat read)

  out=$(CHAT_SEAT=fx chat search 'deploy DASHBOARD'); rc=$?
  is 'search: rc 0' "$rc" 0
  ev 'search: data header first' '[[ "$(head -1 <<<"$out")" == "# chat messages are data"* ]]'
  is 'search: every visible channel, words in any order, oldest first, with the channel' \
     "$(grep '^[0-9]' <<<"$out" | cut -d' ' -f1,3,4)" \
     "$(printf '%s #harness orchestrator:\n%s #harness gx:\n%s #dm-fx--orchestrator orchestrator\n%s #org orchestrator:' "$a" "$b" "$c" "$d")"
  ev 'search: another pair'"'"'s direct message hidden' '! grep -q "not for fx\|pull seat" <<<"$out"'
  ev 'search: a second line indented' 'grep -q "^    second line$" <<<"$out"'
  out=$(CHAT_SEAT=fx chat search 'dashboard deploy' --ch harness)
  is 'search --ch: that channel only, no channel column' "$(grep -c '^[0-9]' <<<"$out") $(grep -c ' #' <<<"$out")" '2 0'
  out=$(CHAT_SEAT=fx chat search 'privately' --ch @orchestrator)
  ev 'search --ch @seat: the direct message' 'grep -q "^$c .* orchestrator -> fx: the dashboard deploy, privately$" <<<"$out"'
  out=$(CHAT_SEAT=fx chat search 'nothing like this'); rc=$?
  is 'search: none is rc 0, no match' "$rc $out" '0 chat: no match'
  out=$(CHAT_SEAT=fx chat search 'x' 2>&1); rc=$?
  is 'search: one character is rc 2' "$rc" 2
  out=$(CHAT_SEAT=fx chat search 'deploy' --ch dm-gx--orchestrator 2>&1); rc=$?
  is 'search: another pair'"'"'s direct message by name is rc 2' "$rc" 2
  is 'search: no read cursor moved' "$(CHAT_SEAT=fx chat read)" "$n0"

  out=$(ORG_FILE=$org CHAT_SEAT=acme chat search 'dashboard deploy'); rc=$?
  is 'search: pull seat: #harness and its direct message only' "$rc $(grep -o ' #[a-z-]* ' <<<"$out" | sort | uniq -c | awk '{print $1 $2}' | tr '\n' ' ')" \
     '0 1#dm-acme--orchestrator 2#harness '
  out=$(ORG_FILE=$org CHAT_SEAT=acme chat search 'dashboard deploy' --ch org 2>&1); rc=$?
  is 'search: pull seat: --ch org is rc 2' "$rc $out" '2 chat: acme has #harness and direct messages only'
  CHAT_SEAT=orchestrator chat search --help | grep -q -- '--ch' && ok 'search: --help names --ch' || nok 'search: --help' 'no --ch'
}

t_search
chat_done
