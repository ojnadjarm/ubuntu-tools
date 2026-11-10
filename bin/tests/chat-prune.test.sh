#!/usr/bin/env bash
# T1515 bin/chat: the prune section (run alone or via chat.test.sh prune); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_prune() {
  # P30: uploads never posted (composer attach, then no send) are dropped by age; posted ones stay.
  local out kept old new
  rm -rf "$ST"; mkdir -p "$WORK/pr"
  printf 'posted\n' >"$WORK/pr/a.txt"
  CHAT_SEAT=fx chat post harness 'with a file' --file "$WORK/pr/a.txt" >/dev/null
  kept=$(ls "$ST/files" | sed -n 's/\.json$//p')
  mk() { python3 -c "import sys; sys.path.insert(0, '$BIN/../lib'); import chat_files; print(chat_files.save(b'$1', '$1.txt')['id'])"; }
  old=$(mk stale); new=$(mk fresh)
  touch -d '3 days ago' "$ST/files/$kept" "$ST/files/$kept.json" "$ST/files/$old" "$ST/files/$old.json"
  out=$(chat prune | head -1)
  is 'prune: dry run names one stale upload, deletes nothing' "$out $(ls "$ST/files" | wc -l)" \
     "chat: would drop 1 upload never posted ($(cat "$ST/files/$old" "$ST/files/$old.json" | wc -c) bytes) 6"
  out=$(chat prune --apply)
  is 'prune: --apply drops the stale orphan and its metadata' "${out%% (*} $(ls "$ST/files" | grep -c "^$old")" 'chat: dropped 1 upload never posted 0'
  ev 'prune: a posted file and a fresh upload stay' '[ -e "$ST/files/$kept" ] && [ -e "$ST/files/$new.json" ]'
  is 'prune: --days 0 takes the fresh one too' "$(chat prune --days 0 --apply | head -1 | cut -d' ' -f2-3) $(ls "$ST/files" | sed -n 's/\.json$//p')" "dropped 1 $kept"
  rm -rf "$ST"; is 'prune: no store: nothing to drop' "$(chat prune --apply)" \
     $'chat: dropped 0 uploads never posted (0 bytes)\nchat: dropped 0 seat copies older than 30 days (0 bytes)'
}

t_copies() {
  # T1546-X9 (A11): per-seat copies older than --copies-days are dropped (give() copies again on the next read); a pull
  # seat's read names the file and makes no copy.
  local out FX="$HARNESS_HOME/po-fx" old new
  rm -rf "$ST" "$FX"; mkdir -p "$FX/inbox" "$WORK/pr"; : >"$FX/BRIEF.md"
  printf 'abc\n' >"$WORK/pr/c.txt"
  CHAT_SEAT=orchestrator chat post harness 'copy me' --file "$WORK/pr/c.txt" >/dev/null
  CHAT_SEAT=fx chat read harness >/dev/null; CHAT_SEAT=orchestrator chat read harness >/dev/null
  old=$(ls "$FX"/state/chat-files/*-c.txt); new=$(ls "$ST"/seats/orchestrator/files/*-c.txt)
  touch -d '40 days ago' "$old"
  is 'copies: dry run names the aged copy, deletes nothing' "$(chat prune | sed -n 2p) $(ls "$old" | wc -l)" \
     'chat: would drop 1 seat copy older than 30 days (4 bytes) 1'
  is 'copies: --apply drops it' "$(chat prune --apply | sed -n 2p)" 'chat: dropped 1 seat copy older than 30 days (4 bytes)'
  ev 'copies: the aged copy is gone, the fresh one and the store file stay' \
     '[ ! -e "$old" ] && [ -e "$new" ] && [ -e "$ST/files/$(basename "$new" | cut -c1-16)" ]'
  is 'copies: --copies-days 0 takes the fresh one too' "$(chat prune --copies-days 0 --apply | sed -n 2p | cut -d' ' -f2-3)" 'dropped 1'
  ev 'copies: the next read copies again' 'CHAT_SEAT=fx chat read harness | grep -q "file: $FX/state/chat-files/"'
  sed 's/^]}/,{"id": "acme", "name": "Acme seat", "role": "po", "parent": "orchestrator", "wake": "pull", "match": null}\n]}/' \
    "$HARNESS_HOME/org.json" >"$WORK/org-acme.json"
  out=$(ORG_FILE="$WORK/org-acme.json" CHAT_SEAT=acme chat read harness)
  ev 'copies: a pull seat reads the file name, not sent' 'grep -qx "    file: c.txt (not sent to this seat)" <<<"$out"'
  ev 'copies: a pull seat read makes no file under seats/' '[ ! -e "$ST/seats/acme" ]'
}

t_prune
t_copies
chat_done
