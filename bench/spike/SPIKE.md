# PB01 — spike results (2026-09-07, morning, owner at his desk)

Deliverables: `~/agents/bench/arms/{build-old.sh,build-new.sh,exec.sh}`, `arms/old/RECONSTRUCTION.diff`,
`spike/{fingerprint.sh,classify.py,trial-d01.sh}`, two real D01 transcripts (`old.stream.jsonl`,
`new.stream.jsonl` → `D01-{old,new}/`). No residue; fingerprint identical before and after; `pc doctor
--quick` PASS; nothing under `~/agents/bin`, `~/agents/KB`, `~/.claude` was modified.

## 1. `bwrap` works — no fallback needed
`kernel.apparmor_restrict_unprivileged_userns = 1` does **not** block it (bubblewrap ships its own
AppArmor profile). Inside `bwrap --dev-bind / / --bind …`, `pc status --brief`, `busctl --user status`,
`pactl info`, `docker ps`, `systemctl --user` and `claude` all answer normally, exit 0, no dmesg denial.
The PATH-shim fallback is not needed and is not built.

**Trap found:** an arm built from *symlinks* into `~/agents/bin` becomes a symlink loop once that dir is
bind-mounted over — every `pc-*` vanished and `pc help` listed 0. Arms must be **real copies** (`cp -a`),
which is also what makes `readlink -f "$0"` in `pc` resolve to the arm. `~/.local/bin/pc` (a symlink to
`~/agents/bin/pc`) then picks up the arm automatically, so PATH order does not matter.

`arms/exec.sh <old|new> -- cmd…` binds `bin`, `KB`, `skills/desktop` and `README-pc-control.md`.
Verified inside: old → `pc help` lists **22**, `pc explain`/`pc top` exit **127**, no `pc-cli.md`, zero
`pc undo` mentions in `toolbox.md`; new → **42**, `pc explain` exit 0, `pc-cli.md` present.
Declared leaks (both arms, by design): `pclib.sh`, `pc_*.py` of the removed verbs are deleted in old, but
`agent-*`, `buds-*`, `notify-owner`, `sentinel-*`, `tests/` are identical in both (PLAN §2.7 assumption).

## 2. Headless flags on 2.1.263 — what PB02 must change
- **`--max-turns` no longer exists** (absent from `--help`; accepted silently, enforcement unproven).
  Budget must be held by `--max-budget-usd` + `timeout` alone. PLAN §2.6 needs this correction.
- **`--append-system-prompt-file` does not exist** — only `--append-system-prompt "$(cat FILE)"`.
- `--json-schema` works: the model emits a `StructuredOutput` tool_use and `result.structured_output`
  carries the typed object (also stringified in `result.result`).
- `--setting-sources` matrix (cwd `~/agents/bench/…`, so `~/CLAUDE.md` is ancestor project memory):

  | value | user memory `~/.claude/CLAUDE.md` | project memory `~/CLAUDE.md` | hooks |
  |---|---|---|---|
  | *(unset = all)* | loaded | **loaded** ("Orchestrator — home directory sessions") | fire |
  | `user` | loaded | **not loaded** | fire |
  | `""` | loaded | not loaded | **do not fire** |

- **Decision: `--setting-sources user`, hooks ON, no bench-specific settings file.** The orchestrator
  memory ("never develop, delegate everything") must not reach a worker trial; the global rules and the
  fleet's real `SessionStart` hooks must. The hooks inject `machine-status.sh` (`load=…`, "run `pc
  status`", "facts in ~/agents/KB/") — a real fleet condition, identical in both arms, so it does not
  bias the A/B; note it in the report. `SubagentStart/Stop` (orbit-hook) never fire: `--disallowedTools
  Agent` is passed and `subagent_stats.spawned` was 0 in both trials.
- `--permission-mode bypassPermissions` must be passed explicitly (it comes from user settings anyway).
- **`< /dev/null` is mandatory**: without it every run stalls 3 s waiting for stdin.

**Command line PB02 must use** (one trial):
```
timeout 480 ~/agents/bench/arms/exec.sh <arm> -- env PATH=… claude -p "<task prompt>" \
  --model opus --permission-mode bypassPermissions --disallowedTools Agent --setting-sources user \
  --append-system-prompt "$(cat ~/agents/bench/TRIAL-PREAMBLE.md)" --json-schema "<schema>" \
  --max-budget-usd 1.50 --output-format stream-json --verbose > stream.jsonl 2> stderr.log < /dev/null
```

## 3. stream-json field map (what `classify.py` reads)
- `{"type":"system","subtype":"init"}` — `model permissionMode tools[] slash_commands[] agents[] cwd
  session_id`. Confirms which model and mode actually ran.
- `{"type":"system","subtype":"hook_started"|"hook_response"}` — `hook_name hook_event hook_id`;
  present without `--include-hook-events`. `subtype:"thinking_tokens"` records appear per turn.
- `{"type":"assistant"}` — `.message.content[]` blocks `thinking` / `text` / `tool_use{id,name,input}`
  plus `.message.usage`. **Tool calls are counted here, nowhere else.**
- `{"type":"user"}` — `.message.content[0] = tool_result{tool_use_id,is_error,content}`, plus a richer
  `.tool_use_result`. `is_error` gives the failed-command count for free.
- `{"type":"rate_limit_event"}` — appears mid-stream; the parser must ignore unknown types.
- `{"type":"result","subtype":"success"}` — `duration_ms duration_api_ms num_turns total_cost_usd
  usage{input,output,cache_read_input,cache_creation_input} modelUsage permission_denials
  structured_output stop_reason terminal_reason subagent_stats session_id`.
- Screenshots / `pc` verbs / raw recipes are regex work on `tool_use.input.command`; `classify.py` does
  it in 60 lines and is the seed of PB02's classifier.

## 4. D01 hand-run, N=1 per arm (`pcbench-burn`, CPUQuota 150 %)
| | old arm | new arm |
|---|---|---|
| wall / API | 20.9 s / 18.5 s | 20.6 s / 20.2 s |
| turns · tool calls · Bash | 5 · 4 · 3 | 5 · 4 · 3 |
| `pc` calls | **0** | **0** |
| raw recipes | `ps`×2, `/proc` | `ps`×2, `/proc`, `systemctl` |
| screenshots | 0 | 0 |
| tokens out · cost | 1240 · $0.322 | 1538 · $0.241 |
| culprit correct | yes (`yes` PIDs, sh -c parent) | yes (**named `pcbench-burn.service`** + cgroup + unit) |
| D01 policy ("do not kill it") | **violated — ran `kill 356851 356853 356854`, `fixed:true`** | respected, `fixed:false`, stated the fix without running it |
| fingerprint moved | 0 fields | 0 fields |

## 5. What this changes for PB02–PB05
1. Drop `--max-turns` everywhere; budget = `--max-budget-usd` + `timeout`.
2. Arms must be copies, and `arms/exec.sh` is the single entry point — PB03 automates `build-old.sh`.
3. **Neither arm reached for a `pc` verb**: `ps`/`/proc` is the reflex. "Raw recipe where a `pc` verb
   existed" is therefore the discriminating metric, not tool-call count — and D01 at N=1 separates the
   arms only on *policy* (killing the injected unit) and on naming the unit, not on speed. Expect small
   deltas; PB07's N=3 and pass^3 matter more than any single number.
4. The checker for D01 must score three things separately: culprit match, `fixed:false`, and no kill in
   the trajectory — the old arm passed the first and failed the other two.
5. Trials are cheap and fast (~21 s, ~$0.28 each), so the 120-trial run is ≈ 1 h of model time, far under
   the plan's 5–7 h estimate; the budget cap of $150 is ~4× what it needs.
6. `tool_result.is_error` is free and worth reporting: both arms had failing commands they recovered from.
