#!/usr/bin/env bash
# T1515 bin/chat: the files section (run alone or via chat.test.sh files); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_files() {
  # P33: `chat post --file`: type from the bytes, size cap, names guard-scanned (not the text inside), stored under the chat
  # store; each receiving seat gets its own copy in its own state folder (po-<seat>/state/chat-files, else the store's
  # seats/<seat>/files), never another seat's; a pull seat gets no attachments (held).
  local out rc id f n0 FX="$HARNESS_HOME/po-fx" GX="$HARNESS_HOME/po-gx" flush
  rm -rf "$ST" "$WORK/systemd-run.log" "$FX" "$GX"; mkdir -p "$FX/inbox" "$GX/inbox"; : >"$FX/BRIEF.md"; : >"$GX/BRIEF.md"
  python3 -c "import zlib, struct
def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
open('$WORK/shot.txt', 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
  + chunk(b'IDAT', zlib.compress(b'\x00\xff\x00\x00')) + chunk(b'IEND', b''))"
  printf 'token=abcdefghijklmnop1234 lives in this file\n' >"$WORK/notes.png"
  stored() { python3 -c "import json, glob
rows = sorted((json.loads(l) for p in glob.glob('$ST/*.20*.jsonl') for l in open(p)), key=lambda r: r['id'])
print(json.dumps(rows[-1].get('files', []) if rows else None))"; }
  msgs() { cat "$ST"/*.20*.jsonl 2>/dev/null | wc -l; }

  id=$(CHAT_SEAT=gx chat post @fx 'two files' --file "$WORK/shot.txt" --file "$WORK/notes.png"); rc=$?
  is 'files: post --file twice: rc 0, an id' "$rc $([[ "$id" =~ ^[0-9]{13}$ ]] && echo id)" '0 id'
  is 'files: type sniffed from the bytes, not the name' "$(stored | python3 -c 'import json, sys
print(" ".join(f["name"] + ":" + f["mime"] + ":" + str(f["size"]) for f in json.load(sys.stdin)))')" \
     "shot.txt:image/png:$(stat -c %s "$WORK/shot.txt") notes.png:text/plain:$(stat -c %s "$WORK/notes.png")"
  f=$(stored | python3 -c 'import json, sys; print(json.load(sys.stdin)[1]["id"])')
  ev 'files: kept under the chat store, bytes unchanged' 'cmp -s "$ST/files/$f" "$WORK/notes.png"'
  ev 'files: no copy in ~/drop or elsewhere in the home' \
     '[ ! -e "$HOME/drop" ] && [ -z "$(find "$HARNESS_HOME" -path "$ST" -prune -o -type f -name "*notes.png" -print)" ]'

  flush=$(sed -n 's/.* --setenv=HARNESS_HOME=[^ ]* //p' "$WORK/systemd-run.log" | head -1); $flush
  f=$(find "$FX/inbox" -type f)
  ev "files: the inbox request lists each file as a path in fx's own state folder" \
     'grep -qE "^    file: $FX/state/chat-files/[0-9a-f]{16}-shot\.txt \(image/png, [0-9]+ bytes\)$" "$f" && grep -qE "^    file: $FX/state/chat-files/[0-9a-f]{16}-notes\.png \(text/plain, [0-9]+ bytes\)$" "$f"'
  ev 'files: the copy is readable and identical to the stored file' \
     'c=$(sed -n "s/^    file: \(.*shot\.txt\) .*/\1/p" "$f"); cmp -s "$c" "$ST/files/$(basename "$c" | cut -c1-16)"'
  out=$(CHAT_SEAT=gx chat read @fx)
  ev 'files: chat read gives the reading seat its own copy' 'grep -qE "^    file: $GX/state/chat-files/[0-9a-f]{16}-shot\.txt " <<<"$out"'
  CHAT_SEAT=orchestrator chat read dm-fx--gx >/dev/null 2>&1; rc=$?
  is 'files: seat isolation: a third seat cannot read the dm (rc 2)' "$rc" 2
  ev 'files: seat isolation: no copy outside the two parties' \
     '[ ! -e "$ST/seats" ] && [ "$(find "$HARNESS_HOME" -path "*/chat-files/*" -type f | grep -vc -e "^$FX/" -e "^$GX/")" = 0 ]'
  CHAT_SEAT=orchestrator chat post harness 'for all' --file "$WORK/shot.txt" >/dev/null
  out=$(CHAT_SEAT=orchestrator chat read harness)
  ev "files: a seat without a po folder gets its copy in the store's seats/<seat>/files" \
     'grep -qE "^    file: $ST/seats/orchestrator/files/[0-9a-f]{16}-shot\.txt " <<<"$out"'

  id=$(CHAT_SEAT=gx chat post fx '' --file "$WORK/shot.txt"); rc=$?
  is 'files: a file alone, no text: rc 0' "$rc $([[ "$id" =~ ^[0-9]{13}$ ]] && echo id)" '0 id'
  n0=$(msgs)
  head -c $((10 * 1024 * 1024 + 1)) /dev/zero >"$WORK/big.bin"
  out=$(CHAT_SEAT=gx chat post fx 'big' --file "$WORK/big.bin" 2>&1); rc=$?
  is 'files: over the cap: rc 2, nothing posted' "$rc $(msgs) ${out%%:*}" "2 $n0 chat"
  ev 'files: the cap is named' 'grep -q "10 MiB" <<<"$out"'
  cp "$WORK/shot.txt" "$WORK/globex-plan.png"
  out=$(CHAT_SEAT=gx chat post fx 'see' --file "$WORK/globex-plan.png" 2>&1); rc=$?
  is 'files: a deny word in a file name is held' "$rc $(msgs) $out" "3 $n0 chat: held (deny word): nothing was posted"
  for i in 1 2 3 4 5 6; do cp "$WORK/shot.txt" "$WORK/s$i.png"; done
  CHAT_SEAT=gx chat post fx 'six' $(for i in 1 2 3 4 5 6; do printf -- '--file %s ' "$WORK/s$i.png"; done) >/dev/null 2>&1; rc=$?
  is 'files: at most 5 files a message (rc 2)' "$rc $(msgs)" "2 $n0"

  sed 's/^]}/,{"id": "acme", "name": "Acme seat", "role": "po", "parent": "orchestrator", "wake": "pull", "match": null}\n]}/' \
    "$HARNESS_HOME/org.json" >"$WORK/org-acme.json"
  out=$(ORG_FILE="$WORK/org-acme.json" CHAT_SEAT=acme chat post harness 'look' --file "$WORK/shot.txt" 2>&1); rc=$?
  is 'files: the pull seat sends no attachment (held)' "$rc $(msgs) $out" "3 $n0 chat: held (attachment): nothing was posted"
  out=$(ORG_FILE="$WORK/org-acme.json" CHAT_SEAT=fx chat post @acme 'look' --file "$WORK/shot.txt" 2>&1); rc=$?
  is 'files: the pull seat gets no attachment (held)' "$rc $(msgs) $out" "3 $n0 chat: held (attachment): nothing was posted"
  is 'files: held or refused posts left no stored file behind' "$(ls "$ST/files" | grep -vc '\.json$\|\.thumb\.webp$')" 4
}

t_files
chat_done
