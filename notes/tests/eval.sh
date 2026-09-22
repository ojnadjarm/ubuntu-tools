#!/usr/bin/env bash
# The brief under fire: drives BRIEF.md headless (claude -p, Sonnet 5, the unit's tool flags) over the
# scripted exchanges in fixtures/eval/exchanges.tsv against a copy of the fixture vault in a temp dir.
# A stub `eye` records `speak` calls instead of talking; the real applier writes the fixture vault only.
# Never the real ~/obsidian-vault, never the live Eye, never the notes unit. Writes EVAL.md next to this script.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTES="$(dirname "$here")"
FIX="$here/fixtures/eval"
BRIEF="${EVAL_BRIEF:-$NOTES/BRIEF.md}"
MODEL="${NOTES_MODEL:-claude-sonnet-5}"
TURN_TIMEOUT="${EVAL_TURN_TIMEOUT:-300}"
fail() { echo "eval: FAIL — $1" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/notes-eval.XXXXXX")"
[ "${EVAL_KEEP:-0}" = 1 ] || trap 'rm -rf "$WORK"' EXIT
VAULT="$WORK/vault"; STUB="$WORK/stub"; PLANS="$WORK/plans"; TURNS="$WORK/turns"
mkdir -p "$STUB" "$PLANS" "$TURNS" "$WORK/home"
cp -r "$FIX/vault" "$VAULT" || fail "fixture vault copy"
export EVAL_CALLS="$WORK/calls.tsv" EVAL_PLANS="$PLANS" EVAL_REAL="$NOTES/notes-file.py"
export NOTES_VAULT_DIR="$VAULT" NOTES_FOLDER="audio notes" NOTES_HOME="$WORK/home"
unset EYE_BRAIN EYE_URL DARK_EYE_CONFIG
: >"$EVAL_CALLS"

cat >"$STUB/eye" <<'EOF'
#!/bin/sh
# eval stub: records every call; nothing reaches a bridge
printf '%s\t%s\n' "$EVAL_TURN" "eye $*" >>"$EVAL_CALLS"
while [ $# -gt 0 ]; do case "$1" in --as) shift 2 ;; *) break ;; esac; done
case "${1:-}" in
  health) echo '{"ok":true,"brainListening":true,"micOpen":false,"tv":"auto","active":"notes"}' ;;
  speak) echo '{"ok":true}' ;;
  brains) echo '{"active":"notes","brains":[{"name":"main","connected":true,"parked":0},{"name":"notes","connected":true,"parked":0}]}' ;;
  listen-loop) echo "listen-loop: armed by the eval harness; VOICE lines arrive as prompts" ;;
  *) echo "eye stub: '$1' is not available in the eval" >&2; exit 1 ;;
esac
EOF
cat >"$STUB/notes-file" <<'EOF'
#!/bin/sh
# eval stub: captures the plan on stdin, records the call and its result, then runs the real applier
if [ "${1:-}" = apply ] && [ "${2:-}" = - ]; then
  f="$EVAL_PLANS/$EVAL_TURN-$(ls "$EVAL_PLANS" | wc -l).json"; cat >"$f"; set -- apply "$f"
fi
printf '%s\t%s\n' "$EVAL_TURN" "notes-file $*" >>"$EVAL_CALLS"
out=$(python3 "$EVAL_REAL" "$@" 2>&1); rc=$?
printf '%s\t  -> rc=%s %s\n' "$EVAL_TURN" "$rc" "$(printf '%s' "$out" | head -1)" >>"$EVAL_CALLS"
printf '%s\n' "$out"; exit $rc
EOF
chmod +x "$STUB/eye" "$STUB/notes-file"
export PATH="$STUB:$HOME/.local/bin:/usr/bin:/bin"

# --- selftest: the stubs are what the session reaches, the real vault is out of reach ------------
[ "$(command -v eye)" = "$STUB/eye" ] || fail "selftest: eye is $(command -v eye), not the stub"
[ "$(command -v notes-file)" = "$STUB/notes-file" ] || fail "selftest: notes-file is not the stub"
command -v claude >/dev/null || fail "selftest: claude not on PATH"
case "$VAULT" in "$HOME"/obsidian-vault*) fail "selftest: fixture vault under ~/obsidian-vault" ;; esac
EVAL_TURN=selftest notes-file index | grep -q '"Kitchen lamp"' || fail "selftest: index does not read the fixture vault"
EVAL_TURN=selftest eye speak --as notes probe >/dev/null || fail "selftest: stub eye speak"
: >"$EVAL_CALLS"
real_before="$(find "$HOME/obsidian-vault" -printf '%p %s %T@\n' 2>/dev/null | md5sum)"
grep -q 'eye listen-loop --as notes' "$BRIEF" || fail "brief lacks the listen-loop"
grep -q '`persistent: true`' "$BRIEF" || fail "brief: listen-loop Monitor is not persistent: true"
grep -q 'command `sleep 600`, description `settle`, `persistent: false`' "$BRIEF" || fail "brief: settle timer Monitor"

cat "$BRIEF" - >"$WORK/BRIEF.md" <<'EOF'

## Headless eval harness (this run only)

This is a scripted run without the Monitor tool. The harness has armed the ear: `eye listen-loop`
returns at once, and every `VOICE:` line arrives as your prompt, one prompt per utterance. Do not
run `sleep`; the settle timer is simulated — a prompt `[Monitor 'settle' (sleep 600) finished:
exit 0]` means the settle timer you would have started after the last unfiled note ended.
Everything else in the brief applies unchanged.
EOF

# --- the turns ----------------------------------------------------------------------------------
SID="$(uuidgen)"; first=1
run_turn() { # id kind prompt
  local id="$1" kind="$2" prompt="$3" vault="$VAULT" t0 rc
  [ "$kind" = novault ] && vault="$WORK/missing"
  local resume=(--session-id "$SID"); [ "$first" = 1 ] || resume=(--resume "$SID"); first=0
  t0=$(date +%s)
  printf '%s' "$prompt" | EVAL_TURN="$id" NOTES_VAULT_DIR="$vault" timeout "$TURN_TIMEOUT" claude -p \
    --model "$MODEL" --output-format json --append-system-prompt-file "$WORK/BRIEF.md" \
    --tools Bash,Read --permission-mode dontAsk --strict-mcp-config --add-dir "$VAULT" \
    --allowedTools "Bash(eye:*),Bash(notes-file:*),Bash(sleep:*)" \
    --disallowedTools "Bash(eye tv:*),Bash(eye talk-to:*),Bash(eye mic:*),Bash(eye show:*)" \
    "${resume[@]}" >"$TURNS/$id.json" 2>"$TURNS/$id.err"
  rc=$?
  printf '%s\t%s\t%s\t%s\n' "$id" "$rc" "$(( $(date +%s) - t0 ))" "$kind" >>"$WORK/turns.tsv"
  echo "turn $id ($kind): rc=$rc $(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(str(d.get("result",""))[:100].replace("\n"," "))' "$TURNS/$id.json" 2>/dev/null)"
}
(cd "$NOTES" && while IFS=$'\t' read -r id kind _ _ _ _ prompt; do
  case "$id" in ''|'#'*) continue ;; esac
  run_turn "$id" "$kind" "$prompt"
done <"$FIX/exchanges.tsv")

real_after="$(find "$HOME/obsidian-vault" -printf '%p %s %T@\n' 2>/dev/null | md5sum)"
[ "$real_before" = "$real_after" ] || fail "the real ~/obsidian-vault changed during the eval"

# --- scoring + EVAL.md --------------------------------------------------------------------------
python3 - "$FIX/exchanges.tsv" "$WORK" "$here/EVAL.md" "$MODEL" <<'EOF'
import json, os, re, sys, datetime
tsv, work, out, model = sys.argv[1:5]
rows = [l.rstrip("\n").split("\t") for l in open(tsv, encoding="utf-8") if l.strip() and not l.startswith("#")]
calls = {}
for l in open(f"{work}/calls.tsv", encoding="utf-8"):
    t, _, c = l.rstrip("\n").partition("\t"); calls.setdefault(t, []).append(c)
turns = {r[0]: r for r in (l.rstrip("\n").split("\t") for l in open(f"{work}/turns.tsv"))}
plans = {}
for f in sorted(os.listdir(f"{work}/plans")):
    t = f.rsplit("-", 1)[0]
    try: plans.setdefault(t, []).append((f, json.load(open(f"{work}/plans/{f}", encoding="utf-8"))))
    except ValueError: plans.setdefault(t, []).append((f, {"actions": []}))
raw_seen, stamps = [], set()
def has(text, kw): return all(any(alt.lower() in text.lower() for alt in k.split("|")) for k in kw.split(";"))
def words(s): return len(s.split())
def sentences(s): return len([p for p in re.split(r"[.!?…]+", s) if p.strip()])
def speak_text(c):
    a = c.split(" ", 1)[1] if " " in c else ""
    a = re.sub(r"--as \S+ ?", "", a).replace("speak", "", 1).strip()
    return a.strip("'\"")
table, detail, passed, total = [], [], 0, 0
for id_, kind, exp_speak, exp_ops, exp_files, exp_kw, prompt in rows:
    cs = calls.get(id_, [])
    speaks = [c for c in cs if re.match(r"eye (--as \S+ )?speak", c)]
    raws = [i for i, c in enumerate(cs) if c.startswith("notes-file raw")]
    applied_ok = {os.path.basename(cs[i-1].split(" ", 2)[2]) for i, c in enumerate(cs) if c.startswith("  -> rc=0") and i and cs[i-1].startswith("notes-file apply")}
    stamps |= {m.group(1) for c in cs for m in [re.match(r"  -> rc=0 - (\d\d:\d\d) — ", c)] if m}
    pl = [p for f, p in plans.get(id_, []) if f in applied_ok]
    acts = [a for p in pl for a in p.get("actions", [])]
    if kind in ("voice", "remote", "dropped"):
        raw_seen.append(re.sub(r"^VOICE( \[remote\])?: ", "", prompt))
    checks = []
    n = len(speaks)
    checks.append(("speak count", n <= 1 if exp_speak == "le1" else n == int(exp_speak), f"{n} spoken"))
    checks.append(("--as notes", all("--as notes" in s for s in speaks), ""))
    checks.append(("never main/tv/talk-to/mic/show", not any(re.search(r"--as main|eye (tv|talk-to|mic|show)\b", c) for c in cs), ""))
    if kind == "remote": checks.append(("no --to on the phone", not any("--to" in s for s in speaks), ""))
    if kind == "chat": checks.append(("no raw line", not raws, ""))
    if kind in ("voice", "remote", "dropped", "novault") and speaks:
        first_speak = next(i for i, c in enumerate(cs) if c in speaks)
        checks.append(("raw before speak", bool(raws) and raws[0] < first_speak, ""))
    for s in speaks:
        t = speak_text(s)
        checks.append(("<= 40 words, <= 2 sentences", words(t) <= 40 and sentences(t) <= 2, f"{words(t)}w/{sentences(t)}s"))
    ops = sorted(a["op"] for a in acts)
    checks.append(("filed ops", ops == (sorted(exp_ops.split(",")) if exp_ops != "none" else []), ",".join(ops) or "none"))
    files = sorted({a["file"] for a in acts})
    if exp_files != "-":
        checks.append(("files", all(any(sub in f for f in files) for sub in exp_files.split(";")), ";".join(files)))
    for a in acts:
        norm = lambda s: re.sub(r"\W+", " ", s.lower()).strip()
        checks.append(("text != transcript", norm(a["text"]) not in [norm(r) for r in raw_seen] and not any(norm(r) in norm(a["text"]) for r in raw_seen if len(r) > 30), ""))
        if kind != "dropped": checks.append(("clean -> no [?", "[?" not in a["text"], ""))
    for r in (r for p in pl for r in p.get("refined", [])) if acts else []:
        checks.append(("at from raw", r.get("at") in stamps, str(r.get("at"))))
    if exp_kw == "?":
        checks.append(("one question", n == 1 and "?" in speak_text(speaks[0]), ""))
    elif exp_kw != "-" and exp_ops != "none":
        checks.append(("refined carries", has(" ".join(a["text"] for a in acts), exp_kw), exp_kw))
    elif exp_kw != "-":
        checks.append(("spoken carries", any(has(speak_text(s), exp_kw) for s in speaks), exp_kw))
    if kind == "novault":
        checks.append(("raw refused", any("rc=1 refused: no vault" in c for c in cs), ""))
    rc, secs = turns.get(id_, ["", "?", "?"])[1:3]
    checks.append(("turn exit 0", rc == "0", f"rc={rc}"))
    ok = all(c[1] for c in checks); total += 1; passed += ok
    got = "; ".join(f"“{speak_text(s)}”" for s in speaks) or "silent"
    if acts: got += " · " + "; ".join(f"{a['op']} {a['file']}" + (f" ▸ {a['heading']}" if a.get("heading") else "") + f" tags={a.get('tags', [])} sure={a.get('sure')}" for a in acts)
    if kind == "novault": got += " · raw " + ("refused" if any("rc=1" in c for c in cs) else "accepted")
    exp = f"speak {exp_speak}, {exp_ops}" + (f" {exp_files}" if exp_files != "-" else "") + (f", kw {exp_kw}" if exp_kw != "-" else "")
    failing = ", ".join(f"{c[0]} ({c[2]})" if c[2] else c[0] for c in checks if not c[1])
    table.append(f"| {id_} | {kind} | {prompt[:70]} | {exp} | {got} | {float(secs):.0f} | {'PASS' if ok else 'FAIL: ' + failing} |")
    for a in acts:
        detail.append(f"- **{id_}** → `{a['file']}`" + (f" ▸ {a['heading']}" if a.get("heading") else "") + f" · tags {a.get('tags', [])} · sure {a.get('sure')}\n  - raw: " + " / ".join(raw_seen[-3:]) + f"\n  - refined: {a['text']}")
daily = ""
for f in sorted(os.listdir(f"{work}/vault/audio notes")):
    if re.match(r"\d{4}-\d{2}-\d{2}\.md$", f) and f != "2026-09-13.md":
        daily += open(f"{work}/vault/audio notes/{f}", encoding="utf-8").read()
with open(out, "w", encoding="utf-8") as f:
    f.write(f"# The brief under fire — headless eval\n\n{datetime.date.today()} · `{model}` · {passed}/{total} exchanges pass · "
            f"fixture vault, stub `eye`, `claude -p` with the unit's tool flags · generated by `tests/eval.sh`\n\n"
            "| # | kind | said | expected | got | s | result |\n|---|---|---|---|---|---|---|\n" + "\n".join(table) +
            "\n\n## Raw → refined (the owner's read)\n\n" + ("\n".join(detail) or "nothing filed") +
            "\n\n## Today's daily file after the run\n\n```\n" + daily + "```\n")
print(f"eval: {passed}/{total} pass → {out}")
sys.exit(0 if passed == total else 1)
EOF
