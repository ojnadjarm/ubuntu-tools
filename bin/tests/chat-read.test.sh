#!/usr/bin/env bash
# T1515 bin/chat: the read section (run alone or via chat.test.sh read); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

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

t_read
chat_done
