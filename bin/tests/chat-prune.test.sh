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
  out=$(chat prune)
  is 'prune: dry run names one stale upload, deletes nothing' "$out $(ls "$ST/files" | wc -l)" \
     "chat: would drop 1 upload never posted ($(cat "$ST/files/$old" "$ST/files/$old.json" | wc -c) bytes) 6"
  out=$(chat prune --apply)
  is 'prune: --apply drops the stale orphan and its metadata' "${out%% (*} $(ls "$ST/files" | grep -c "^$old")" 'chat: dropped 1 upload never posted 0'
  ev 'prune: a posted file and a fresh upload stay' '[ -e "$ST/files/$kept" ] && [ -e "$ST/files/$new.json" ]'
  is 'prune: --days 0 takes the fresh one too' "$(chat prune --days 0 --apply | cut -d' ' -f2-3) $(ls "$ST/files" | sed -n 's/\.json$//p')" "dropped 1 $kept"
  rm -rf "$ST"; is 'prune: no store: nothing to drop' "$(chat prune --apply)" 'chat: dropped 0 uploads never posted (0 bytes)'
}

t_prune
chat_done
