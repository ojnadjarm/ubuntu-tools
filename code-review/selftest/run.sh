#!/usr/bin/env bash
# run.sh [--keep] — the code-review selftest: a real swarm run (real model) on a throwaway fleet-like home with 4
# seeded defects, through the same BRIEF, agent-exec, adapter and sandbox as the timer. Proves the fixture is fixed
# (oracle.sh) and that nothing outside it changed (sha256 snapshot of every real root before and after).
set -uo pipefail
. "$HOME/agents/bin/fleetlib.sh"
fleet_path
ME="$HOME/agents/code-review"; here="$ME/selftest"
ts="$(date +%Y%m%d-%H%M%S)"; S="$ME/state/selftest/$ts"; FX="$S/home"
mkdir -p "$S"
python3 "$here/build.py" "$FX" >/dev/null || exit 2
echo "selftest: fixture $FX"

code-review-sandbox --fixture "$FX" --selftest || exit 1

roots=("$HOME/agents/bin" "$HOME/agents/dashboard" "$HOME/agents/hooks" "$HOME/agents/eye-relay" "$HOME/agents/adapters"
       "$HOME/agents/units" "$HOME/agents/KB" "$HOME/agents/improve" "$HOME/agents/toolsmith" "$HOME/agents/briefs"
       "$HOME/agents/backups/code-review" "$HOME/agents/backups/retired" "$HOME/.claude/skills" "$HOME/.claude/agents"
       "$HOME/.claude/hooks" "$HOME/.claude/projects/${HOME//\//-}/memory" "$HOME/.config/pc-harness"
       "$HOME/.config/systemd/user" "$HOME/.local/bin")
files=("$HOME/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "$HOME/.claude/settings.json" "$HOME/.bashrc" "$HOME/agents/AGENTS.md"
       "$HOME/agents/README.md" "$HOME/agents/RUNNER.md" "$ME/BRIEF.md" "$ME/swarm.js" "$ME/LANES.md" "$ME/agent.env")
snap() { code-review snapshot "$1" "${roots[@]}" >/dev/null
         python3 - "$1" "${files[@]}" <<'EOF'
import hashlib, json, sys
p = sys.argv[1]; d = json.load(open(p))
for f in sys.argv[2:]:
    try: d[f] = hashlib.sha256(open(f, 'rb').read()).hexdigest()
    except OSError: d[f] = 'absent'
json.dump(d, open(p, 'w'))
EOF
}
snap "$S/before.json"

start=$SECONDS
CR_HOME="$FX" CR_FIX_CAP=20 HARNESS_AGENT=claude AGENT_TOOLS=Bash,Read,Write,Edit,Workflow \
AGENT_WRAP="code-review-sandbox --fixture $FX --post --" \
  agent-exec --prompt-file "$ME/BRIEF.md" --system-file "$HOME/agents/AGENT-PREAMBLE.md" --model opus \
    --cwd "$FX/agents/code-review" --name code-review-selftest --timeout 14000 \
    --raw-out "$S/raw.json" --meta-out "$S/meta.json" >"$S/session.log" 2>&1
rc=$?
echo "selftest: swarm session rc=$rc in $((SECONDS - start)) s · cost $(jq -r '.cost_usd // "?"' "$S/meta.json" 2>/dev/null) USD"

snap "$S/after.json"
left="$(pgrep -af "$FX" | grep -v -e pgrep -e 'selftest/run.sh' || true)"
[ -z "$left" ] || echo "selftest: LEFTOVER processes after the session: $left"
bash "$here/oracle.sh" "$FX" "$(date +%F)" | tee "$S/oracle.txt"; orc=${PIPESTATUS[0]}
code-review snapdiff "$S/before.json" "$S/after.json" | tee "$S/snapdiff.txt"; sdc=${PIPESTATUS[0]}
# A change counts against the swarm unless the audit log shows another session wrote that path during the run.
if [ "$sdc" != 0 ]; then
  python3 - "$S" "$(jq -r '.session_id // ""' "$S/raw.json" 2>/dev/null | cut -c1-8)" "$ts" <<'EOF2' && sdc=0
import json, os, re, sys, datetime as dt
S, me, ts = sys.argv[1:]
t0 = dt.datetime.strptime(ts, '%Y%m%d-%H%M%S').astimezone()
home = os.path.expanduser('~')
paths = [l.split(None, 1)[1].strip() for l in open(f'{S}/snapdiff.txt') if re.match(r'(changed|added|removed)\s+/', l)]
rows = []
for l in open(os.path.join(home, 'agents/log/actions.jsonl')):
    try: d = json.loads(l); d['t'] = dt.datetime.fromisoformat(d['ts'])
    except (ValueError, KeyError): continue
    if d['t'] >= t0: rows.append(d)
def names(d, p):
    s = d.get('summary', '')
    return p in s or p.replace(home, '~', 1) in s
ok = bool(paths)
for p in paths:
    who = {d['session'] for d in rows if names(d, p)}
    if not who and os.path.exists(p):
        # Audit summaries are cut at 500 chars: fall back to write calls within 5 s before the file's mtime.
        m = dt.datetime.fromtimestamp(os.path.getmtime(p)).astimezone()
        # Attribute only to a session whose call in that window names the file.
        near = [d for d in rows if d.get('tool') in ('Bash', 'Edit', 'Write', 'NotebookEdit')
                and m - dt.timedelta(seconds=5) <= d['t'] <= m + dt.timedelta(seconds=1)
                and os.path.basename(p) in d.get('summary', '')]
        who = {d['session'] for d in near}
    mine = bool(me) and me in who
    print(f"{'NOT attributed' if mine or not who else 'attributed to session ' + ','.join(sorted(who))}: {p}")
    ok = ok and bool(who) and not mine
sys.exit(0 if ok else 1)
EOF2
fi
echo "selftest: session $rc · oracle $([ "$orc" = 0 ] && echo pass || echo FAIL) · outside-fixture changes $([ "$sdc" = 0 ] && echo 0 || echo FOUND) · $S"
[ "$rc" = 0 ] && [ "$orc" = 0 ] && [ "$sdc" = 0 ] && [ -z "$left" ]
